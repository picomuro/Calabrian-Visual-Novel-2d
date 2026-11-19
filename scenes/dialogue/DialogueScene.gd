extends Control
## DialogueScene — scena prototipo riutilizzabile per tutti i dialoghi.
##
## La logica sta in DialogueRunner (nodo figlio): questa scena si limita a
## mostrare ciò che il runner annuncia con i segnali (collegati nel .tscn) e a
## inoltrargli tocchi e scelte. Regola seguita: "chiama in giù, segnala in su" —
## la scena chiama metodi dei propri figli, i figli comunicano solo con segnali.
##
## Avvio: SceneManager.go_to_location() passa i parametri con receive_params().
## Avviata da sola (F6 nell'editor) usa il file indicato in [member dialogue_path].


## Caratteri al secondo dell'effetto macchina da scrivere.
const CHARS_PER_SECOND: float = 45.0
const CHOICE_MIN_HEIGHT: float = 96.0
const EXIT_BUTTON_TEXT: String = "Torna alla mappa"

## Dialogo da caricare se la scena viene avviata senza parametri.
@export_file("*.json") var dialogue_path: String = "res://data/dialogues/spiaggia.json"
## Nodo da cui partire ("" = nodo "start" del file). Usato per riprendere un salvataggio.
@export var start_node: String = ""

var _typing_tween: Tween
var _pending_choices: Array[Dictionary] = []
var _waiting_for_advance: bool = false
var _input_locked: bool = false

@onready var _runner: DialogueRunner = $DialogueRunner
@onready var _background_color: ColorRect = %BackgroundColor
@onready var _background_texture: TextureRect = %BackgroundTexture
@onready var _slots: Dictionary[String, CharacterSlot] = {
	"left": %LeftSlot,
	"center": %CenterSlot,
	"right": %RightSlot,
}
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _text_label: RichTextLabel = %TextLabel
@onready var _continue_indicator: Label = %ContinueIndicator
@onready var _choices_box: VBoxContainer = %ChoicesBox


## Chiamato da SceneManager prima di _ready().
func receive_params(params: Dictionary) -> void:
	dialogue_path = str(params.get("dialogue_path", dialogue_path))
	start_node = str(params.get("start_node", start_node))


func _ready() -> void:
	_speaker_label.text = ""
	_text_label.text = ""
	_continue_indicator.visible = false
	_clear_choices()
	if not _runner.load_dialogue(dialogue_path):
		_show_error("Impossibile caricare il dialogo:\n%s" % dialogue_path)
		return
	_runner.start(start_node)


#region Input

func _gui_input(event: InputEvent) -> void:
	# Con "emula mouse da touch" un tocco arriva come click sinistro.
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_on_tap()


func _unhandled_input(event: InputEvent) -> void:
	# Spazio/Invio su desktop, solo quando non ci sono scelte a schermo.
	if event.is_action_pressed(&"ui_accept") and not _choices_box.visible:
		get_viewport().set_input_as_handled()
		_on_tap()


func _on_tap() -> void:
	if _input_locked:
		return
	if _is_typing():
		_complete_typing()
	elif _waiting_for_advance:
		_waiting_for_advance = false
		_continue_indicator.visible = false
		_runner.advance()


func _on_choice_pressed(choice_index: int) -> void:
	if _input_locked:
		return
	_clear_choices()
	_runner.choose(choice_index)

#endregion


#region Segnali del DialogueRunner (collegati nel .tscn)

func _on_runner_background_changed(background: Variant) -> void:
	var image_path: String = ""
	var color_text: String = ""
	if background is Dictionary:
		image_path = str(background.get("image", ""))
		color_text = str(background.get("color", ""))
	elif str(background).begins_with("res://"):
		image_path = str(background)
	else:
		color_text = str(background)

	if not color_text.is_empty():
		_background_color.color = Color.from_string(color_text, _background_color.color)
	var texture: Texture2D = null
	if not image_path.is_empty() and ResourceLoader.exists(image_path):
		texture = load(image_path) as Texture2D
	# Se l'immagine non esiste ancora resta visibile il colore di riserva.
	_background_texture.texture = texture
	_background_texture.visible = texture != null


func _on_runner_character_shown(slot: String, character: Dictionary) -> void:
	if _slots.has(slot):
		_slots[slot].show_character(character)


func _on_runner_character_hidden(slot: String) -> void:
	if _slots.has(slot):
		_slots[slot].hide_character()


func _on_runner_line_ready(speaker_id: String, speaker_name: String, speaker_color: Color, text: String) -> void:
	_pending_choices.clear()
	_waiting_for_advance = false
	_continue_indicator.visible = false
	_speaker_label.text = speaker_name
	_speaker_label.visible = not speaker_name.is_empty()
	_speaker_label.add_theme_color_override(&"font_color", speaker_color)
	_highlight_speaker(speaker_id)
	_start_typing(text)


func _on_runner_choices_ready(choices: Array[Dictionary]) -> void:
	_pending_choices = choices
	# Se il testo sta ancora comparendo, le scelte aspettano la fine della battuta.
	if not _is_typing():
		_show_pending_choices()


func _on_runner_dialogue_finished(exit_target: String) -> void:
	# Le richieste fatte durante una transizione vengono messe in coda da SceneManager,
	# e una location inesistente riporta alla mappa: bloccare l'input qui è sicuro.
	_input_locked = true
	if exit_target.begins_with(DialogueRunner.EXIT_LOCATION_PREFIX):
		SceneManager.go_to_location(exit_target.trim_prefix(DialogueRunner.EXIT_LOCATION_PREFIX))
	else:
		SceneManager.go_to_map()

#endregion


#region Testo con effetto macchina da scrivere

func _start_typing(text: String) -> void:
	if _typing_tween != null:
		_typing_tween.kill()
	_text_label.text = text
	_text_label.visible_ratio = 0.0
	var duration: float = maxf(float(_text_label.get_total_character_count()) / CHARS_PER_SECOND, 0.05)
	_typing_tween = create_tween()
	_typing_tween.tween_property(_text_label, "visible_ratio", 1.0, duration)
	_typing_tween.finished.connect(_on_typing_finished)


func _is_typing() -> bool:
	return _typing_tween != null and _typing_tween.is_running()


## Mostra subito tutto il testo (primo tocco durante la scrittura).
func _complete_typing() -> void:
	_typing_tween.kill()
	_text_label.visible_ratio = 1.0
	_on_typing_finished()


func _on_typing_finished() -> void:
	if not _pending_choices.is_empty():
		_show_pending_choices()
	elif _runner.state == DialogueRunner.State.WAITING_ADVANCE:
		_waiting_for_advance = true
		_continue_indicator.visible = true

#endregion


#region Scelte

func _show_pending_choices() -> void:
	_clear_choices()
	for choice: Dictionary in _pending_choices:
		var button: Button = Button.new()
		var label: String = str(choice.get("text", ""))
		var available: bool = choice.get("available", true)
		if not available:
			label += "\n(Richiede: %s)" % choice.get("locked_reason", "")
		button.text = label
		button.disabled = not available
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.custom_minimum_size.y = CHOICE_MIN_HEIGHT
		button.pressed.connect(_on_choice_pressed.bind(int(choice.get("index", 0))))
		_choices_box.add_child(button)
	_choices_box.visible = _choices_box.get_child_count() > 0
	_pending_choices.clear()


func _clear_choices() -> void:
	for child: Node in _choices_box.get_children():
		_choices_box.remove_child(child)
		child.queue_free()
	_choices_box.visible = false

#endregion


func _highlight_speaker(speaker_id: String) -> void:
	var speaker_on_screen: bool = false
	for slot: CharacterSlot in _slots.values():
		if not speaker_id.is_empty() and slot.character_id == speaker_id:
			speaker_on_screen = true
	for slot: CharacterSlot in _slots.values():
		slot.set_speaking(not speaker_on_screen or slot.character_id == speaker_id)


## Mostra un errore con un'uscita sempre disponibile: il giocatore non resta mai bloccato.
func _show_error(message: String) -> void:
	_input_locked = true
	_speaker_label.text = "Errore"
	_speaker_label.visible = true
	_text_label.text = "[color=#ff7070]%s[/color]" % message
	_text_label.visible_ratio = 1.0
	_clear_choices()
	var exit_button: Button = Button.new()
	exit_button.text = EXIT_BUTTON_TEXT
	exit_button.custom_minimum_size.y = CHOICE_MIN_HEIGHT
	exit_button.pressed.connect(SceneManager.go_to_map)
	_choices_box.add_child(exit_button)
	_choices_box.visible = true
