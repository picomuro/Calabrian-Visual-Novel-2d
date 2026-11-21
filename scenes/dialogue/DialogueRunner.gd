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
##   # facoltativo: i personaggi stanno in data/characters.json (GameRegistry);
##   # qui solo quelli da aggiungere o ridefinire per questo dialogo
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
##       "effects": { ... },         # applicati all'ingresso nel nodo, una volta sola
##       "repeat": false,            # true = effetti del nodo a ogni passaggio
##       "choices": [ {"text": "...", "next": "...", "effects": {...},
##                     "requires": {...}, "hidden_if_locked": false, "repeat": false} ],
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
## Suffisso della chiave degli effetti delle scelte (vedi _apply_effects).
const CHOICE_EFFECTS_SUFFIX: String = "#scelta"
## Protezione da cicli infiniti tra nodi senza testo né scelte.
const MAX_AUTO_STEPS: int = 64

const DEFAULT_SPEAKER_COLOR: Color = Color(0.95, 0.9, 0.8)

enum State { IDLE, WAITING_ADVANCE, WAITING_CHOICE, FINISHED }


var dialogue_id: String = ""
var state: State = State.IDLE

var _start_node: String = ""
var _nodes: Dictionary = {}
## Personaggi usabili: registro condiviso + definizioni del dialogo.
var _characters: Dictionary = {}
## Solo i personaggi definiti nel file del dialogo (quelli del registro li controlla GameRegistry).
var _local_characters: Dictionary = {}
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
	# Personaggi: quelli condivisi del registro, più (o al posto di) quelli del dialogo.
	var local_characters: Variant = data.get("characters", {})
	_local_characters = local_characters if local_characters is Dictionary else {}
	_characters = GameRegistry.get_characters().duplicate()
	_characters.merge(_local_characters, true)
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
	_apply_effects(choice, _current_id + CHOICE_EFFECTS_SUFFIX)
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
		node_entered.emit(next_id)
		_apply_effects(_current_node, next_id)
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


## Applica gli effetti di un nodo o di una scelta. Di norma valgono una volta sola per
## partita: rigiocando il dialogo non si raccolgono di nuovo ricompense e karma. Per le
## scelte conta la prima decisione presa in quel nodo: sceglierne un'altra in seguito non
## dà altri effetti. Con "repeat": true gli effetti si applicano a ogni passaggio.
## [param key_suffix] è l'id del nodo (più "#scelta" per le scelte).
func _apply_effects(source: Dictionary, key_suffix: String) -> void:
	var effects: Dictionary = _get_dict(source, "effects")
	if GameState.is_true(source.get("repeat", false)):
		GameState.apply_effects(effects)
	else:
		GameState.apply_effects_once(get_effects_key(key_suffix), effects)


## Chiave con cui GameState ricorda gli effetti già applicati (es. "spiaggia/inizio").
func get_effects_key(key_suffix: String) -> String:
	return "%s/%s" % [dialogue_id, key_suffix]


func _finish(exit_target: String) -> void:
	state = State.FINISHED
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
	if GameState.is_true(node.get("clear_characters", false)):
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
		if not available and GameState.is_true(choice.get("hidden_if_locked", false)):
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

## Controlla il dialogo caricato: riferimenti tra nodi, location di uscita, personaggi
## ed espressioni, formato di sfondi, effetti e requisiti.
## Ritorna l'elenco dei problemi trovati (vuoto = tutto valido).
## Le immagini non ancora presenti non sono errori: vedi find_missing_assets().
func validate() -> PackedStringArray:
	var issues: PackedStringArray = []
	if not _nodes.has(_start_node):
		issues.append("nodo iniziale '%s' inesistente" % _start_node)
	_validate_character_definitions(issues)
	for node_key: Variant in _nodes:
		var node_id: String = str(node_key)
		var node: Variant = _nodes[node_key]
		if not node is Dictionary:
			issues.append("il nodo '%s' non è un oggetto" % node_id)
			continue
		if node.has("next"):
			_check_target(issues, node_id, str(node["next"]))
		if node.has("effects"):
			_append_prefixed(issues, GameState.validate_effects(node["effects"]), "nodo '%s'" % node_id)
		if node.has("repeat") and not node["repeat"] is bool:
			issues.append("'repeat' nel nodo '%s' deve valere true o false" % node_id)
		if node.has("background"):
			_check_background(issues, node_id, node["background"])
		var branches: Variant = node.get("branches", [])
		if not branches is Array:
			issues.append("'branches' nel nodo '%s' deve essere un elenco" % node_id)
		else:
			for branch: Variant in branches:
				if not branch is Dictionary:
					issues.append("branch non valido nel nodo '%s'" % node_id)
					continue
				if branch.has("next"):
					_check_target(issues, node_id, str(branch["next"]))
				_append_prefixed(issues, GameState.validate_requirements(branch.get("requires", {})), "branch del nodo '%s'" % node_id)
		var raw_choices: Array = _get_raw_choices(node)
		for index: int in raw_choices.size():
			var choice: Variant = raw_choices[index]
			if not choice is Dictionary:
				issues.append("scelta non valida nel nodo '%s'" % node_id)
				continue
			if str(choice.get("text", "")).is_empty():
				issues.append("scelta senza testo nel nodo '%s'" % node_id)
			if choice.has("next"):
				_check_target(issues, node_id, str(choice["next"]))
			var where: String = "scelta %d del nodo '%s'" % [index + 1, node_id]
			_append_prefixed(issues, GameState.validate_effects(choice.get("effects", {})), where)
			_append_prefixed(issues, GameState.validate_requirements(choice.get("requires", {})), where)
			if choice.has("repeat") and not choice["repeat"] is bool:
				issues.append("%s: 'repeat' deve valere true o false" % where)
		var characters: Dictionary = _get_dict(node, "characters")
		for slot: Variant in characters:
			if not str(slot) in SLOTS:
				issues.append("posizione '%s' non valida nel nodo '%s' (usa left/center/right)" % [slot, node_id])
			var entry: Variant = characters[slot]
			var character_id: String = str(entry.get("id", "")) if entry is Dictionary else (str(entry) if entry != null else "")
			if character_id.is_empty():
				continue
			if not _characters.has(character_id):
				issues.append("personaggio '%s' non definito (nodo '%s')" % [character_id, node_id])
				continue
			var expression: String = str(entry.get("expression", "")) if entry is Dictionary else ""
			var expressions: Dictionary = _get_dict(_get_dict(_characters, character_id), "expressions")
			if not expression.is_empty() and not expressions.has(expression):
				issues.append("espressione '%s' non definita per '%s' (nodo '%s')" % [expression, character_id, node_id])
		# Se ogni scelta ha requisiti, il giocatore che non ne soddisfa nessuno resta bloccato.
		if not raw_choices.is_empty():
			var has_free_choice: bool = false
			for choice: Variant in raw_choices:
				if choice is Dictionary and _get_dict(choice, "requires").is_empty():
					has_free_choice = true
					break
			if not has_free_choice:
				issues.append("nel nodo '%s' ogni scelta ha requisiti: serve almeno una scelta sempre disponibile, o il giocatore può restare bloccato" % node_id)
	for node_id: String in _find_unreachable_nodes():
		issues.append("il nodo '%s' è irraggiungibile (nessun percorso dal nodo iniziale)" % node_id)
	return issues


## Nodi a cui non si arriva mai partendo dal nodo iniziale (seguendo next, branches e scelte).
func _find_unreachable_nodes() -> PackedStringArray:
	var reached: Dictionary = {}
	var pending: Array[String] = [_start_node]
	while not pending.is_empty():
		var node_id: String = pending.pop_back()
		if reached.has(node_id) or not _nodes.has(node_id) or not _nodes[node_id] is Dictionary:
			continue
		reached[node_id] = true
		var node: Dictionary = _nodes[node_id]
		if node.has("next"):
			pending.append(str(node["next"]))
		var branches: Variant = node.get("branches", [])
		if branches is Array:
			for branch: Variant in branches:
				if branch is Dictionary and branch.has("next"):
					pending.append(str(branch["next"]))
		for choice: Variant in _get_raw_choices(node):
			if choice is Dictionary and choice.has("next"):
				pending.append(str(choice["next"]))
	var unreachable: PackedStringArray = []
	for node_key: Variant in _nodes:
		if not reached.has(str(node_key)):
			unreachable.append(str(node_key))
	return unreachable


## Personaggi: espressione di default esistente e file dei ritratti presenti.
## (Solo quelli definiti nel dialogo: il registro condiviso lo controlla GameRegistry.validate().)
func _validate_character_definitions(issues: PackedStringArray) -> void:
	for character_key: Variant in _local_characters:
		for issue: String in GameRegistry.validate_character(str(character_key), _local_characters[character_key]):
			issues.append(issue)


## Id dei personaggi che il dialogo usa davvero: in scena negli slot o come "speaker".
func get_used_character_ids() -> PackedStringArray:
	var used: PackedStringArray = []
	for node_key: Variant in _nodes:
		var node: Variant = _nodes[node_key]
		if not node is Dictionary:
			continue
		var speaker: String = str(node.get("speaker", ""))
		if _characters.has(speaker) and not speaker in used:
			used.append(speaker)
		var slots: Dictionary = _get_dict(node, "characters")
		for slot: Variant in slots:
			var entry: Variant = slots[slot]
			var character_id: String = str(entry.get("id", "")) if entry is Dictionary else (str(entry) if entry != null else "")
			if _characters.has(character_id) and not character_id in used:
				used.append(character_id)
	return used


## Immagini (ritratti e sfondi) citate dal dialogo ma non ancora presenti nel progetto.
## Non sono errori: finché manca il file il gioco mostra un segnaposto (riquadro col
## nome del personaggio, o il colore di sfondo). Serve come elenco delle immagini da fornire.
func find_missing_assets() -> PackedStringArray:
	var missing: PackedStringArray = []
	for character_id: String in get_used_character_ids():
		var expressions: Dictionary = _get_dict(_get_dict(_characters, character_id), "expressions")
		for expression: Variant in expressions:
			_append_if_missing(missing, str(expressions[expression]))
	for node_key: Variant in _nodes:
		var node: Variant = _nodes[node_key]
		if node is Dictionary and node.has("background"):
			_append_if_missing(missing, str(_split_background(node["background"]).get("image", "")))
	return missing


static func _append_if_missing(missing: PackedStringArray, path: String) -> void:
	if not path.is_empty() and not ResourceLoader.exists(path) and not path in missing:
		missing.append(path)


## Sfondo: percorso "res://..." di un'immagine, colore ("#rrggbb" o nome come "black"),
## oppure {image, color}. Stesse regole di DialogueScene. Ritorna {image, color}, oppure
## {} se il valore non è di nessuno di questi tipi.
static func _split_background(background: Variant) -> Dictionary:
	if background is Dictionary:
		return {"image": str(background.get("image", "")), "color": str(background.get("color", ""))}
	if background is String:
		if (background as String).begins_with("res://"):
			return {"image": background, "color": ""}
		return {"image": "", "color": background}
	return {}


## Controlla il formato dello sfondo (l'esistenza del file la segnala find_missing_assets).
func _check_background(issues: PackedStringArray, node_id: String, background: Variant) -> void:
	if background == null:
		return
	var parts: Dictionary = _split_background(background)
	if parts.is_empty():
		issues.append("sfondo non valido nel nodo '%s'" % node_id)
		return
	var color: String = parts["color"]
	# Color.from_string usa il valore di ripiego solo se il testo non è un colore:
	# se con due ripieghi diversi il risultato cambia, il colore non è valido.
	if not color.is_empty() and Color.from_string(color, Color.BLACK) != Color.from_string(color, Color.WHITE):
		issues.append("colore di sfondo non valido nel nodo '%s': %s" % [node_id, color])


static func _append_prefixed(issues: PackedStringArray, found: PackedStringArray, where: String) -> void:
	for issue: String in found:
		issues.append("%s: %s" % [where, issue])


func _check_target(issues: PackedStringArray, from_id: String, target: String) -> void:
	if target == EXIT_END or target == EXIT_MAP:
		return
	if target.begins_with(EXIT_LOCATION_PREFIX):
		var location_id: String = target.trim_prefix(EXIT_LOCATION_PREFIX)
		var dialogue_path: String = GameRegistry.get_dialogue_path(location_id)
		if location_id.is_empty():
			issues.append("'%s' senza id di location (nodo '%s')" % [target, from_id])
		elif not GameRegistry.has_location(location_id):
			issues.append("il nodo '%s' porta alla location '%s', che non è in %s" % [from_id, location_id, GameRegistry.LOCATIONS_PATH])
		elif not FileAccess.file_exists(dialogue_path):
			issues.append("il nodo '%s' porta alla location '%s', che non ha un dialogo (%s)" % [from_id, location_id, dialogue_path])
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
