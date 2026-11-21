class_name GameRegistry
extends RefCounted
## GameRegistry — personaggi e location condivisi da tutto il gioco.
##
## I dati stanno in due file JSON, letti una volta sola e poi tenuti in memoria:
## - res://data/characters.json: {"characters": {id: {name, color, default_expression, expressions}}}
## - res://data/locations.json:  {"locations": {id: {name}}}
## Le chiavi che iniziano con "_" (es. "_descrizione") sono note e vengono ignorate.
##
## I dialoghi usano i personaggi per id ("speaker": "padre", "left": "madre") senza
## ridefinirli; un dialogo può comunque aggiungere o sostituire personaggi nel suo
## campo "characters". Ogni location deve avere il suo data/dialogues/<id>.json.


const CHARACTERS_PATH: String = "res://data/characters.json"
const LOCATIONS_PATH: String = "res://data/locations.json"
const DIALOGUES_DIR: String = "res://data/dialogues/"

static var _characters: Dictionary = {}
static var _locations: Dictionary = {}
static var _loaded: bool = false


## Tutti i personaggi condivisi (id -> definizione). Non modificare il risultato.
static func get_characters() -> Dictionary:
	_ensure_loaded()
	return _characters


static func has_character(character_id: String) -> bool:
	return get_characters().has(character_id)


## Tutte le location (id -> {name}). Non modificare il risultato.
static func get_locations() -> Dictionary:
	_ensure_loaded()
	return _locations


static func has_location(location_id: String) -> bool:
	return get_locations().has(location_id)


## Nome da mostrare per una location (l'id leggibile se non è nel registro).
static func get_location_name(location_id: String) -> String:
	var location: Variant = get_locations().get(location_id, {})
	var location_name: String = str(location.get("name", "")) if location is Dictionary else ""
	return location_name if not location_name.is_empty() else location_id.capitalize()


## Percorso del dialogo di una location (convenzione: un file per location).
static func get_dialogue_path(location_id: String) -> String:
	return DIALOGUES_DIR.path_join(location_id + ".json")


## Rilegge i file (utile ai test o dopo averli modificati a gioco avviato).
static func reload() -> void:
	_loaded = false
	_ensure_loaded()


## Controlla i due registri. Ritorna l'elenco dei problemi (vuoto = tutto valido).
static func validate() -> PackedStringArray:
	_ensure_loaded()
	var issues: PackedStringArray = []
	if _characters.is_empty():
		issues.append("nessun personaggio in %s" % CHARACTERS_PATH)
	for character_id: Variant in _characters:
		for issue: String in validate_character(str(character_id), _characters[character_id]):
			issues.append(issue)
	if _locations.is_empty():
		issues.append("nessuna location in %s" % LOCATIONS_PATH)
	for location_id: Variant in _locations:
		var location: Variant = _locations[location_id]
		if not location is Dictionary or str(location.get("name", "")).is_empty():
			issues.append("la location '%s' non ha un nome" % location_id)
		if not FileAccess.file_exists(get_dialogue_path(str(location_id))):
			issues.append("la location '%s' non ha un dialogo (%s)" % [location_id, get_dialogue_path(str(location_id))])
	return issues


## Controlla la definizione di un personaggio (usato anche per quelli definiti in un dialogo).
## L'esistenza dei file dei ritratti non è controllata qui: le immagini mancanti sono segnaposto.
static func validate_character(character_id: String, definition: Variant) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not definition is Dictionary:
		issues.append("la definizione del personaggio '%s' non è un oggetto" % character_id)
		return issues
	if str(definition.get("name", "")).is_empty():
		issues.append("il personaggio '%s' non ha un nome" % character_id)
	var color: String = str(definition.get("color", ""))
	if not color.is_empty() and Color.from_string(color, Color.BLACK) != Color.from_string(color, Color.WHITE):
		issues.append("colore '%s' non valido per '%s'" % [color, character_id])
	var raw_expressions: Variant = definition.get("expressions", {})
	if not raw_expressions is Dictionary:
		issues.append("'expressions' di '%s' deve essere un oggetto" % character_id)
		return issues
	var default_expression: String = str(definition.get("default_expression", ""))
	if not default_expression.is_empty() and not (raw_expressions as Dictionary).has(default_expression):
		issues.append("espressione di default '%s' non definita per '%s'" % [default_expression, character_id])
	return issues


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_characters = _read_section(CHARACTERS_PATH, "characters")
	_locations = _read_section(LOCATIONS_PATH, "locations")


## Legge {section: {...}} da un file JSON, scartando le chiavi che iniziano con "_".
static func _read_section(path: String, section: String) -> Dictionary:
	var result: Dictionary = {}
	if not FileAccess.file_exists(path):
		push_error("GameRegistry: file mancante %s." % path)
		return result
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("GameRegistry: JSON non valido in %s alla riga %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return result
	var data: Variant = json.data.get(section, null) if json.data is Dictionary else null
	if not data is Dictionary:
		push_error("GameRegistry: %s deve contenere un oggetto \"%s\"." % [path, section])
		return result
	for key: Variant in data:
		if not str(key).begins_with("_"):
			result[str(key)] = data[key]
	return result
