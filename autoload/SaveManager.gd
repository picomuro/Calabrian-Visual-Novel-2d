extends Node
## SaveManager — salva e carica lo stato di GameState su file JSON.
##
## Si occupa solo di I/O: il contenuto del salvataggio è deciso da
## GameState.to_dict() / GameState.from_dict(), che converte anche i salvataggi
## delle versioni precedenti.
##
## Ci sono due slot:
## - "auto": scritto da solo ogni volta che si torna sulla mappa e quando l'app va
##   in background mentre si è sulla mappa. All'avvio il gioco riprende da qui.
## - "manuale": scritto solo dal pulsante "Salva" del menu; "Carica" torna qui.
## Si salva solo sulla mappa: a metà dialogo gli effetti sono già applicati e
## riprendere da lì li applicherebbe due volte.
##
## Protezioni contro la perdita dei dati:
## - si scrive su un file temporaneo poi rinominato: un crash a metà scrittura non
##   rovina il salvataggio precedente;
## - prima di sostituire un salvataggio, quello vecchio viene copiato in "<file>.bak";
## - se il file non si legge (danneggiato, o di una versione più recente del gioco)
##   si carica la copia .bak; se non si legge neanche quella, il file viene copiato
##   in "<file>.illeggibile" così il salvataggio successivo non lo cancella.


signal game_saved(path: String)
## [param from_backup] è true se il file principale era illeggibile ed è stata usata la copia .bak.
signal game_loaded(path: String, from_backup: bool)
signal save_failed(path: String, error_message: String)
signal load_failed(path: String, error_message: String)
signal save_deleted(path: String)


const DEFAULT_SAVE_PATH: String = "user://save.json"
const SLOT_AUTO: String = "auto"
const SLOT_MANUAL: String = "manuale"
const BACKUP_SUFFIX: String = ".bak"
const UNREADABLE_SUFFIX: String = ".illeggibile"

const NOTICE_RESTORED: String = "Il salvataggio era danneggiato: ripresa la copia precedente."
const NOTICE_UNREADABLE: String = "Il salvataggio non si può leggere: si riparte da zero. Una copia del file è stata conservata."

## Percorso dello slot automatico; gli altri slot stanno nella stessa cartella
## (es. user://save_manuale.json). Modificabile, es. per i test.
var save_path: String = DEFAULT_SAVE_PATH
## Se false non c'è né salvataggio automatico né ripresa all'avvio (usato dai test).
var autosave_enabled: bool = true

## Messaggio per il giocatore sulla ripresa all'avvio ("" se è andato tutto bene).
var _startup_notice: String = ""


func _ready() -> void:
	# Ripresa all'avvio: lo stato è caricato prima che venga creata la scena principale.
	if autosave_enabled and has_save(SLOT_AUTO):
		game_loaded.connect(_on_startup_loaded, CONNECT_ONE_SHOT)
		if not load_game(SLOT_AUTO):
			game_loaded.disconnect(_on_startup_loaded)
			_startup_notice = NOTICE_UNREADABLE
	# SceneManager è registrato dopo SaveManager: il collegamento va rimandato.
	_connect_scene_manager.call_deferred()


func _notification(what: int) -> void:
	# Su mobile l'app può essere chiusa dal sistema mentre è in background.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if SceneManager.is_on_map() and not SceneManager.is_transitioning:
			autosave()


## Restituisce (una volta sola) l'avviso sulla ripresa all'avvio, da mostrare sulla mappa.
func take_startup_notice() -> String:
	var notice: String = _startup_notice
	_startup_notice = ""
	return notice


## Percorso del file di uno slot.
func get_slot_path(slot: String = SLOT_AUTO) -> String:
	if slot == SLOT_AUTO:
		return save_path
	return save_path.get_base_dir().path_join("%s_%s.json" % [save_path.get_file().get_basename(), slot])


## True se c'è qualcosa da caricare nello slot (il file o la sua copia di sicurezza).
func has_save(slot: String = SLOT_AUTO) -> bool:
	var path: String = get_slot_path(slot)
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + BACKUP_SUFFIX)


## Salvataggio automatico: non fa nulla se è disattivato. Ritorna true se ha salvato.
func autosave() -> bool:
	if not autosave_enabled:
		return false
	return save_game(SLOT_AUTO)


## Salva lo stato corrente. Ritorna true se è andato a buon fine.
func save_game(slot: String = SLOT_AUTO) -> bool:
	var path: String = get_slot_path(slot)
	var data: Dictionary = GameState.to_dict()
	data["saved_at"] = Time.get_datetime_string_from_system(true)  # UTC, ISO 8601
	var json_text: String = JSON.stringify(data, "\t")

	var tmp_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _fail_save(path, "impossibile aprire il file (%s)" % error_string(FileAccess.get_open_error()))
	file.store_string(json_text)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _fail_save(path, "errore di scrittura (%s)" % error_string(write_error))

	# Copia di sicurezza del salvataggio precedente, solo se è leggibile: una copia
	# danneggiata non servirebbe e cancellerebbe quella buona.
	if _read_save_data(path) != null:
		var backup_error: Error = DirAccess.copy_absolute(path, path + BACKUP_SUFFIX)
		if backup_error != OK:
			push_warning("SaveManager: copia di sicurezza non riuscita (%s)." % error_string(backup_error))
	elif FileAccess.file_exists(path):
		_preserve_unreadable(path)

	# Sostituisce il vecchio salvataggio con quello appena scritto.
	var rename_error: Error = DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK and FileAccess.file_exists(path):
		# Alcune piattaforme non sovrascrivono in rename: rimuove e riprova
		# (se qui si interrompe tutto, resta la copia .bak).
		DirAccess.remove_absolute(path)
		rename_error = DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		return _fail_save(path, "impossibile finalizzare il file (%s)" % error_string(rename_error))

	game_saved.emit(path)
	return true


## Carica il salvataggio in GameState. Se il file non si legge prova la copia .bak.
## Ritorna true se è andato a buon fine; in caso di errore lo stato corrente non cambia.
func load_game(slot: String = SLOT_AUTO) -> bool:
	var path: String = get_slot_path(slot)
	var data: Variant = _read_save_data(path)
	if data != null and GameState.from_dict(data):
		game_loaded.emit(path, false)
		return true

	var backup: Variant = _read_save_data(path + BACKUP_SUFFIX)
	if backup != null and GameState.from_dict(backup):
		push_warning("SaveManager: %s illeggibile, caricata la copia di sicurezza." % path)
		_preserve_unreadable(path)
		game_loaded.emit(path, true)
		return true

	if not FileAccess.file_exists(path) and not FileAccess.file_exists(path + BACKUP_SUFFIX):
		_fail_load(path, "nessun salvataggio presente")
	else:
		_preserve_unreadable(path)
		_fail_load(path, "file danneggiato o di una versione più recente del gioco (copia conservata in %s)" % (path + UNREADABLE_SUFFIX))
	return false


## Legge informazioni sul salvataggio senza caricarlo (es. per il menu).
## Ritorna {} se né il file né la sua copia di sicurezza sono leggibili.
func peek_save_info(slot: String = SLOT_AUTO) -> Dictionary:
	var path: String = get_slot_path(slot)
	var data: Variant = _read_save_data(path)
	if data == null:
		data = _read_save_data(path + BACKUP_SUFFIX)
	if data == null:
		return {}
	return {
		"saved_at": str(data.get("saved_at", "")),
		"location_id": str(data.get("location_id", "")),
	}


## Elimina lo slot e la sua copia di sicurezza (la copia ".illeggibile" resta).
func delete_save(slot: String = SLOT_AUTO) -> void:
	var path: String = get_slot_path(slot)
	var deleted: bool = false
	for file_path: String in [path, path + BACKUP_SUFFIX]:
		if not FileAccess.file_exists(file_path):
			continue
		var error: Error = DirAccess.remove_absolute(file_path)
		if error == OK:
			deleted = true
		else:
			push_warning("SaveManager: impossibile eliminare %s (%s)." % [file_path, error_string(error)])
	if deleted:
		save_deleted.emit(path)


## Data di "saved_at" (UTC) nell'ora locale, es. "21/11/2026 alle 10:32". "" se non valida.
static func format_saved_at(saved_at: String) -> String:
	if saved_at.is_empty():
		return ""
	var unix_time: int = Time.get_unix_time_from_datetime_string(saved_at)
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%02d/%02d/%d alle %02d:%02d" % [local.day, local.month, local.year, local.hour, local.minute]


func _on_startup_loaded(_path: String, from_backup: bool) -> void:
	if from_backup:
		_startup_notice = NOTICE_RESTORED


## Ogni ritorno sulla mappa è un punto di salvataggio automatico.
func _connect_scene_manager() -> void:
	SceneManager.scene_changed.connect(_on_scene_changed)


func _on_scene_changed(new_scene: Node) -> void:
	if new_scene != null and new_scene.scene_file_path == SceneManager.MAP_SCENE_PATH:
		autosave()


## Copia un file illeggibile in "<file>.illeggibile", così il prossimo salvataggio non
## lo cancella e si può tentare di recuperarlo a mano. Non fa nulla se il file manca.
func _preserve_unreadable(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var error: Error = DirAccess.copy_absolute(path, path + UNREADABLE_SUFFIX)
	if error != OK:
		push_warning("SaveManager: impossibile conservare %s (%s)." % [path, error_string(error)])


## Legge e controlla il file JSON (anche la versione). Ritorna il Dictionary oppure null.
## Non segnala errori: decide chi chiama come comportarsi.
func _read_save_data(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		return null
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		push_warning("SaveManager: JSON non valido in %s alla riga %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		push_warning("SaveManager: %s non contiene un oggetto JSON." % path)
		return null
	if GameState.get_save_version(json.data) > GameState.SAVE_FORMAT_VERSION:
		push_warning("SaveManager: %s viene da una versione più recente del gioco." % path)
		return null
	return json.data


func _fail_save(path: String, message: String) -> bool:
	push_error("SaveManager: salvataggio fallito: %s" % message)
	save_failed.emit(path, message)
	return false


func _fail_load(path: String, message: String) -> void:
	push_error("SaveManager: caricamento fallito: %s" % message)
	load_failed.emit(path, message)
