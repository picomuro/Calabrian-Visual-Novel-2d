class_name DialogueRunner
extends Node
## DialogueRunner — interpreta un dialogo JSON, separato dalla UI.
##
## Non conosce nessun nodo grafico: annuncia cosa mostrare tramite segnali e
## avanza quando la UI chiama [method advance] o [method choose].
## Effetti e requisiti sono delegati a GameState (stesso formato usato dalla mappa).
##
## Struttura del file (vedi README per la guida completa):
## [codeblock]
## {
##   "id": "spiaggia",
##   "start": "inizio",
##   "characters": { "oste": { "name": "...", "color": "#b5803a",
##                             "default_expression": "neutro",
##                             "expressions": { "neutro": "res://...png" } } },
##   "nodes": {
##     "inizio": {
##       "background": "#3b2a1e" | "res://...png" | {"image": "res://...", "color": "#..."},
##       "characters": { "left": {"id": "oste", "expression": "neutro"}, "right": null },
##       "clear_characters": false,
##       "speaker": "oste",          # id personaggio, nome libero, o assente = narratore
##       "text": "Testo con [b]BBCode[/b]",
##       "effects": { ... },         # applicati all'ingresso nel nodo
##       "choices": [ {"text": "...", "next": "...", "effects": {...},
##                     "requires": {...}, "hidden_if_locked": false} ],
##       "branches": [ {"requires": {...}, "next": "..."} ],  # primo che vale vince
##       "next": "altro_nodo" | "@end" | "@map" | "@location:<id>"
##     }
##   }
## }
## [/codeblock]


signal dialogue_started(dialogue_id: String)
signal node_entered(node_id: String)
## [param background]: stringa (colore "#rrggbb" o percorso) oppure Dictionary {image, color}.
signal background_changed(background: Variant)
## [param character]: {id, name, color, expression, texture}.
signal character_shown(slot: String, character: Dictionary)
signal character_hidden(slot: String)
## Una battuta da mostrare. [param speaker_id] è "" per il narratore o per nomi liberi.
signal line_ready(speaker_id: String, speaker_name: String, speaker_color: Color, text: String)
## Scelte da mostrare: ognuna è {index, text, available, locked_reason}.
signal choices_ready(choices: Array[Dictionary])
## Fine dialogo. [param exit_target]: "@end", "@map" oppure "@location:<id>".
signal dialogue_finished(exit_target: String)


const SLOTS: Array[String] = ["left", "center", "right"]
const EXIT_END: String = "@end"
const EXIT_MAP: String = "@map"
const EXIT_LOCATION_PREFIX: String = "@location:"
## Protezione da cicli infiniti tra nodi senza testo né scelte.
const MAX_AUTO_STEPS: int = 64

const DEFAULT_SPEAKER_COLOR: Color = Color(0.95, 0.9, 0.8)

enum State { IDLE, WAITING_ADVANCE, WAITING_CHOICE, FINISHED }


var dialogue_id: String = ""
var state: State = State.IDLE

var _start_node: String = ""
var _nodes: Dictionary = {}
var _characters: Dictionary = {}
var _current_id: String = ""
var _current_node: Dictionary = {}


#region Caricamento

## Carica un dialogo da file JSON. Ritorna false (con errore in console) se non è valido.
func load_dialogue(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("DialogueRunner: file inesistente '%s'." % path)
		return false
	var json: JSON = JSON.new()
	var parse_error: Error = json.parse(FileAccess.get_file_as_string(path))
	if parse_error != OK:
		push_error("DialogueRunner: JSON non valido in '%s' alla riga %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return false
	if not json.data is Dictionary:
		push_error("DialogueRunner: '%s' deve contenere un oggetto JSON." % path)
		return false
	return load_from_dict(json.data, path.get_file().get_basename())


## Carica un dialogo già letto (utile per test o dialoghi generati da codice).
func load_from_dict(data: Dictionary, fallback_id: String = "") -> bool:
	var nodes: Variant = data.get("nodes", null)
	if not nodes is Dictionary or (nodes as Dictionary).is_empty():
		push_error("DialogueRunner: il dialogo '%s' non ha 'nodes'." % fallback_id)
		return false
	_nodes = nodes
	var characters: Variant = data.get("characters", {})
	_characters = characters if characters is Dictionary else {}
	dialogue_id = str(data.get("id", fallback_id))
	_start_node = str(data.get("start", ""))
	if _start_node.is_empty():
		_start_node = str(_nodes.keys()[0])
	state = State.IDLE
	for issue: String in validate():
		push_warning("DialogueRunner [%s]: %s" % [dialogue_id, issue])
	return true

#endregion


#region Controllo del flusso (chiamato dalla UI)

## Avvia il dialogo dal nodo indicato (o da "start" se vuoto/inesistente).
func start(node_id: String = "") -> void:
	var first: String = node_id if _nodes.has(node_id) else _start_node
	dialogue_started.emit(dialogue_id)
	_enter_node(first)


## Passa al nodo successivo dopo una battuta senza scelte.
func advance() -> void:
	if state != State.WAITING_ADVANCE:
		return
	state = State.IDLE
	_enter_node(_resolve_next(_current_node))


## Seleziona la scelta con indice [param choice_index] (indice nell'array "choices" del JSON).
func choose(choice_index: int) -> void:
	if state != State.WAITING_CHOICE:
		return
	var raw_choices: Array = _get_raw_choices(_current_node)
	if choice_index < 0 or choice_index >= raw_choices.size() or not raw_choices[choice_index] is Dictionary:
		push_warning("DialogueRunner: scelta %d non valida nel nodo '%s'." % [choice_index, _current_id])
		return
	var choice: Dictionary = raw_choices[choice_index]
	# Ricontrolla i requisiti: lo stato potrebbe essere cambiato.
	if not GameState.meets_requirements(_get_dict(choice, "requires")):
		push_warning("DialogueRunner: requisiti non soddisfatti per la scelta %d." % choice_index)
		return
	state = State.IDLE
	GameState.apply_effects(_get_dict(choice, "effects"))
	var next_id: String = str(choice["next"]) if choice.has("next") else _resolve_next(_current_node)
	_enter_node(next_id)


func get_current_node_id() -> String:
	return _current_id

#endregion


#region Interpretazione dei nodi

func _enter_node(node_id: String) -> void:
	var next_id: String = node_id
	for _step: int in MAX_AUTO_STEPS:
		if next_id.begins_with("@"):
			_finish(next_id)
			return
		if not _nodes.has(next_id) or not _nodes[next_id] is Dictionary:
			push_error("DialogueRunner [%s]: nodo inesistente '%s'." % [dialogue_id, next_id])
			_finish(EXIT_END)
			return

		_current_id = next_id
		_current_node = _nodes[next_id]
		GameState.current_dialogue_node = next_id
		node_entered.emit(next_id)
		GameState.apply_effects(_get_dict(_current_node, "effects"))
		_apply_presentation(_current_node)

		var text: String = str(_current_node.get("text", ""))
		if not text.is_empty():
			_emit_line(_current_node, text)
		var choices: Array[Dictionary] = _build_choices(_current_node)
		if not choices.is_empty():
			state = State.WAITING_CHOICE
			choices_ready.emit(choices)
			return
		if not text.is_empty():
			state = State.WAITING_ADVANCE
			return
		# Nodo puramente logico (solo effetti/branches): prosegue subito.
		next_id = _resolve_next(_current_node)

	push_error("DialogueRunner [%s]: troppi nodi consecutivi senza testo (ciclo?) da '%s'." % [dialogue_id, node_id])
	_finish(EXIT_END)


func _finish(exit_target: String) -> void:
	state = State.FINISHED
	GameState.current_dialogue_node = ""
	dialogue_finished.emit(exit_target)


## Prossimo nodo: il primo "branch" con requisiti soddisfatti, altrimenti "next", altrimenti fine.
func _resolve_next(node: Dictionary) -> String:
	var branches: Variant = node.get("branches", [])
	if branches is Array:
		for branch: Variant in branches:
			if branch is Dictionary and GameState.meets_requirements(_get_dict(branch, "requires")):
				return str(branch.get("next", EXIT_END))
	return str(node.get("next", EXIT_END))


func _apply_presentation(node: Dictionary) -> void:
	if node.has("background"):
		background_changed.emit(node["background"])
	if node.get("clear_characters", false) == true:
		for slot: String in SLOTS:
			character_hidden.emit(slot)
	var characters: Dictionary = _get_dict(node, "characters")
	for slot_key: Variant in characters:
		var slot: String = str(slot_key)
		if not slot in SLOTS:
			continue
		var entry: Variant = characters[slot_key]
		if entry == null:
			character_hidden.emit(slot)
		elif entry is Dictionary:
			character_shown.emit(slot, _resolve_character(str(entry.get("id", "")), str(entry.get("expression", ""))))
		elif entry is String:
			# Forma breve: "left": "oste" usa l'espressione di default.
			character_shown.emit(slot, _resolve_character(entry, ""))


func _emit_line(node: Dictionary, text: String) -> void:
	var speaker: String = str(node.get("speaker", ""))
	if _characters.has(speaker):
		var character: Dictionary = _characters[speaker]
		line_ready.emit(speaker, str(character.get("name", speaker)), _parse_color(character.get("color", ""), DEFAULT_SPEAKER_COLOR), text)
	else:
		# Nome libero (es. "Voce lontana") oppure narratore se vuoto.
		line_ready.emit("", speaker, DEFAULT_SPEAKER_COLOR, text)


func _build_choices(node: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_choices: Array = _get_raw_choices(node)
	for index: int in raw_choices.size():
		var choice: Variant = raw_choices[index]
		if not choice is Dictionary:
			continue
		var requires: Dictionary = _get_dict(choice, "requires")
		var available: bool = GameState.meets_requirements(requires)
		if not available and choice.get("hidden_if_locked", false) == true:
			continue
		var reason: String = ""
		if not available:
			reason = GameState.describe_requirements(requires)
			if reason.is_empty():
				reason = "Non disponibile"
		result.append({
			"index": index,
			"text": str(choice.get("text", "...")),
			"available": available,
			"locked_reason": reason,
		})
	return result


func _resolve_character(character_id: String, expression: String) -> Dictionary:
	var definition: Dictionary = _get_dict(_characters, character_id)
	var expressions: Dictionary = _get_dict(definition, "expressions")
	var chosen: String = expression if not expression.is_empty() else str(definition.get("default_expression", ""))
	return {
		"id": character_id,
		"name": str(definition.get("name", character_id)),
		"color": _parse_color(definition.get("color", ""), Color.GRAY),
		"expression": chosen,
		"texture": str(expressions.get(chosen, "")),
	}

#endregion


#region Validazione (aiuta chi scrive i dialoghi: i problemi finiscono in console)

## Controlla i riferimenti del dialogo caricato. Ritorna l'elenco dei problemi trovati.
func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	if not _nodes.has(_start_node):
		issues.append("nodo iniziale '%s' inesistente" % _start_node)
	for node_key: Variant in _nodes:
		var node_id: String = str(node_key)
		var node: Variant = _nodes[node_key]
		if not node is Dictionary:
			issues.append("il nodo '%s' non è un oggetto" % node_id)
			continue
		if node.has("next"):
			_check_target(issues, node_id, str(node["next"]))
		var branches: Variant = node.get("branches", [])
		if branches is Array:
			for branch: Variant in branches:
				if branch is Dictionary and branch.has("next"):
					_check_target(issues, node_id, str(branch["next"]))
		for choice: Variant in _get_raw_choices(node):
			if not choice is Dictionary:
				issues.append("scelta non valida nel nodo '%s'" % node_id)
				continue
			if str(choice.get("text", "")).is_empty():
				issues.append("scelta senza testo nel nodo '%s'" % node_id)
			if choice.has("next"):
				_check_target(issues, node_id, str(choice["next"]))
		var characters: Dictionary = _get_dict(node, "characters")
		for slot: Variant in characters:
			if not str(slot) in SLOTS:
				issues.append("posizione '%s' non valida nel nodo '%s' (usa left/center/right)" % [slot, node_id])
			var entry: Variant = characters[slot]
			var character_id: String = str(entry.get("id", "")) if entry is Dictionary else (str(entry) if entry != null else "")
			if not character_id.is_empty() and not _characters.has(character_id):
				issues.append("personaggio '%s' non definito (nodo '%s')" % [character_id, node_id])
	return issues


func _check_target(issues: PackedStringArray, from_id: String, target: String) -> void:
	if target == EXIT_END or target == EXIT_MAP:
		return
	if target.begins_with(EXIT_LOCATION_PREFIX):
		if target.length() == EXIT_LOCATION_PREFIX.length():
			issues.append("'%s' senza id di location (nodo '%s')" % [target, from_id])
		return
	if not _nodes.has(target):
		issues.append("il nodo '%s' punta a '%s', che non esiste" % [from_id, target])

#endregion


#region Utilità

static func _get_dict(source: Dictionary, key: String) -> Dictionary:
	var value: Variant = source.get(key, {})
	return value if value is Dictionary else {}


static func _get_raw_choices(node: Dictionary) -> Array:
	var value: Variant = node.get("choices", [])
	return value if value is Array else []


static func _parse_color(value: Variant, fallback: Color) -> Color:
	if value is String and not (value as String).is_empty():
		return Color.from_string(value, fallback)
	return fallback

#endregion
