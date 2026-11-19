extends Node
## SaveManager — salva e carica lo stato di GameState su file JSON.
##
## Si occupa solo di I/O: il contenuto del salvataggio è deciso da
## GameState.to_dict() / GameState.from_dict(). La scrittura avviene su un file
## temporaneo poi rinominato, così un crash a metà scrittura non corrompe il
## salvataggio precedente.


signal game_saved(path: String)
signal game_loaded(path: String)
signal save_failed(path: String, error_message: String)
signal load_failed(path: String, error_message: String)
signal save_deleted(path: String)


const DEFAULT_SAVE_PATH: String = "user://save.json"

## Percorso del salvataggio (modificabile, es. per slot multipli o per i test).
var save_path: String = DEFAULT_SAVE_PATH


func has_save() -> bool:
	return FileAccess.file_exists(save_path)


## Salva lo stato corrente. Ritorna true se è andato a buon fine.
func save_game() -> bool:
	var data: Dictionary = GameState.to_dict()
	data["saved_at"] = Time.get_datetime_string_from_system(true)  # UTC, ISO 8601
	var json_text: String = JSON.stringify(data, "\t")

	var tmp_path: String = save_path + ".tmp"
	var file: FileAccess = FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		return _fail_save("impossibile aprire il file (%s)" % error_string(FileAccess.get_open_error()))
	file.store_string(json_text)
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return _fail_save("errore di scrittura (%s)" % error_string(write_error))

	# Sostituisce il vecchio salvataggio con quello appena scritto.
	var rename_error: Error = DirAccess.rename_absolute(tmp_path, save_path)
	if rename_error != OK and FileAccess.file_exists(save_path):
		# Alcune piattaforme non sovrascrivono in rename: rimuove e riprova.
		DirAccess.remove_absolute(save_path)
		rename_error = DirAccess.rename_absolute(tmp_path, save_path)
	if rename_error != OK:
		return _fail_save("impossibile finalizzare il file (%s)" % error_string(rename_error))

	game_saved.emit(save_path)
	return true


## Carica il salvataggio in GameState. Ritorna true se è andato a buon fine;
## in caso di errore lo stato corrente non viene modificato.
func load_game() -> bool:
	var data: Variant = _read_save_data()
	if data == null:
		return false
	GameState.from_dict(data)
	game_loaded.emit(save_path)
	return true


## Legge informazioni sul salvataggio senza caricarlo (es. per un pulsante "Continua").
## Ritorna {} se non esiste o non è valido.
func peek_save_info() -> Dictionary:
	if not has_save():
		return {}
	var data: Variant = _read_save_data(false)
	if data == null:
		return {}
	return {
		"saved_at": str(data.get("saved_at", "")),
		"location_id": str(data.get("location_id", "")),
	}


func delete_save() -> void:
	if not has_save():
		return
	var error: Error = DirAccess.remove_absolute(save_path)
	if error == OK:
		save_deleted.emit(save_path)
	else:
		push_warning("SaveManager: impossibile eliminare %s (%s)." % [save_path, error_string(error)])


## Legge e valida il file JSON. Ritorna il Dictionary oppure null in caso di errore.
func _read_save_data(emit_errors: bool = true) -> Variant:
	if not has_save():
		if emit_errors:
			_fail_load("nessun salvataggio presente")
		return null
	var text: String = FileAccess.get_file_as_string(save_path)
	if text.is_empty():
		if emit_errors:
			_fail_load("file vuoto o illeggibile (%s)" % error_string(FileAccess.get_open_error()))
		return null
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(text)
	if parse_error != OK:
		if emit_errors:
			_fail_load("JSON non valido alla riga %d: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	if not json.data is Dictionary:
		if emit_errors:
			_fail_load("il contenuto non è un oggetto JSON")
		return null
	return json.data


func _fail_save(message: String) -> bool:
	push_error("SaveManager: salvataggio fallito: %s" % message)
	save_failed.emit(save_path, message)
	return false


func _fail_load(message: String) -> void:
	push_error("SaveManager: caricamento fallito: %s" % message)
	load_failed.emit(save_path, message)
