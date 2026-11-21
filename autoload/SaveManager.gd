extends Node
## SaveManager — salva e carica lo stato di GameState su file JSON.
##
## Si occupa solo di I/O: il contenuto del salvataggio è deciso da
## GameState.to_dict() / GameState.from_dict(). La scrittura avviene su un file
## temporaneo poi rinominato, così un crash a metà scrittura non corrompe il
## salvataggio precedente.
##
## Ci sono due slot:
## - "auto": scritto da solo ogni volta che si torna sulla mappa e quando l'app va
##   in background mentre si è sulla mappa. All'avvio il gioco riprende da qui.
## - "manuale": scritto solo dal pulsante "Salva" del menu; "Carica" torna qui.
## Si salva solo sulla mappa: a metà dialogo gli effetti sono già applicati e
## riprendere da lì li applicherebbe due volte.


signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(path: String, error_message: String)
signal load_failed(path: String, error_message: String)
signal save_deleted(path: String)


const DEFAULT_SAVE_PATH: String = "user://save.json"
const SLOT_AUTO: String = "auto"
const SLOT_MANUAL: String = "manuale"

## Percorso dello slot automatico; gli altri slot stanno nella stessa cartella
## (es. user://save_manuale.json). Modificabile, es. per i test.
var save_path: String = DEFAULT_SAVE_PATH
## Se false non c'è né salvataggio automatico né ripresa all'avvio (usato dai test).
var autosave_enabled: bool = true


func _ready() -> void:
	# Ripresa all'avvio: lo stato è caricato prima che venga creata la scena principale.
	if autosave_enabled and has_save(SLOT_AUTO):
		load_game(SLOT_AUTO)
	# SceneManager è registrato dopo SaveManager: il collegamento va rimandato.
	_connect_scene_manager.call_deferred()


func _notification(what: int) -> void:
	# Su mobile l'app può essere chiusa dal sistema mentre è in background.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		if SceneManager.is_on_map() and not SceneManager.is_transitioning:
			autosave()


## Percorso del file di uno slot.
func get_slot_path(slot: String = SLOT_AUTO) -> String:
	if slot == SLOT_AUTO:
		return save_path
	return save_path.get_base_dir().path_join("%s_%s.json" % [save_path.get_file().get_basename(), slot])


func has_save(slot: String = SLOT_AUTO) -> bool:
	return FileAccess.file_exists(get_slot_path(slot))


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

	# Sostituisce il vecchio salvataggio con quello appena scritto.
	var rename_error: Error = DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK and FileAccess.file_exists(path):
		# Alcune piattaforme non sovrascrivono in rename: rimuove e riprova.
		DirAccess.remove_absolute(path)
		rename_error = DirAccess.rename_absolute(tmp_path, path)
	if rename_error != OK:
		return _fail_save(path, "impossibile finalizzare il file (%s)" % error_string(rename_error))

	game_saved.emit(path)
	return true


## Carica il salvataggio in GameState. Ritorna true se è andato a buon fine;
## in caso di errore lo stato corrente non viene modificato.
func load_game(slot: String = SLOT_AUTO) -> bool:
	var path: String = get_slot_path(slot)
	var data: Variant = _read_save_data(path)
	if data == null:
		return false
	GameState.from_dict(data)
	game_loaded.emit(path)
	return true


## Legge informazioni sul salvataggio senza caricarlo (es. per il menu).
## Ritorna {} se non esiste o non è valido.
func peek_save_info(slot: String = SLOT_AUTO) -> Dictionary:
	var path: String = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var data: Variant = _read_save_data(path, false)
	if data == null:
		return {}
	return {
		"saved_at": str(data.get("saved_at", "")),
		"location_id": str(data.get("location_id", "")),
	}


func delete_save(slot: String = SLOT_AUTO) -> void:
	var path: String = get_slot_path(slot)
	if not FileAccess.file_exists(path):
		return
	var error: Error = DirAccess.remove_absolute(path)
	if error == OK:
		save_deleted.emit(path)
	else:
		push_warning("SaveManager: impossibile eliminare %s (%s)." % [path, error_string(error)])


## Data di "saved_at" (UTC) nell'ora locale, es. "21/11/2026 alle 10:32". "" se non valida.
static func format_saved_at(saved_at: String) -> String:
	if saved_at.is_empty():
		return ""
	var unix_time: int = Time.get_unix_time_from_datetime_string(saved_at)
	var bias_minutes: int = int(Time.get_time_zone_from_system().get("bias", 0))
	var local: Dictionary = Time.get_datetime_dict_from_unix_time(unix_time + bias_minutes * 60)
	return "%02d/%02d/%d alle %02d:%02d" % [local.day, local.month, local.year, local.hour, local.minute]


## Ogni ritorno sulla mappa è un punto di salvataggio automatico.
func _connect_scene_manager() -> void:
	SceneManager.scene_changed.connect(_on_scene_changed)


func _on_scene_changed(new_scene: Node) -> void:
	if new_scene != null and new_scene.scene_file_path == SceneManager.MAP_SCENE_PATH:
		autosave()


## Legge e valida il file JSON. Ritorna il Dictionary oppure null in caso di errore.
func _read_save_data(path: String, emit_errors: bool = true) -> Variant:
	if not FileAccess.file_exists(path):
		if emit_errors:
			_fail_load(path, "nessun salvataggio presente")
		return null
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		if emit_errors:
			_fail_load(path, "file vuoto o illeggibile (%s)" % error_string(FileAccess.get_open_error()))
		return null
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		if emit_errors:
			_fail_load(path, "JSON non valido alla riga %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		if emit_errors:
			_fail_load(path, "il contenuto non è un oggetto JSON")
		return null
	return json.data


func _fail_save(path: String, message: String) -> bool:
	push_error("SaveManager: salvataggio fallito: %s" % message)
	save_failed.emit(path, message)
	return false


func _fail_load(path: String, message: String) -> void:
	push_error("SaveManager: caricamento fallito: %s" % message)
	load_failed.emit(path, message)
