class_name CharacterSlot
extends Control
## CharacterSlot — una delle tre posizioni personaggio (sinistra/centro/destra).
##
## Mostra la texture dell'espressione se il file esiste; altrimenti un pannello
## segnaposto colorato con nome ed espressione, così si può scrivere la storia
## prima di avere la grafica. Per nascondere usa la trasparenza (non visible),
## così l'HBoxContainer non ridistribuisce le altre posizioni.


const FADE_TIME: float = 0.2
const SPEAKING_TINT: Color = Color.WHITE
const IDLE_TINT: Color = Color(0.62, 0.62, 0.68)

## Altezza massima del ritratto rispetto all'altezza della posizione:
## è il valore da cambiare per rendere i personaggi più grandi o più piccoli.
@export_range(0.1, 1.0, 0.05) var max_height_ratio: float = 0.65
## Larghezza massima del ritratto rispetto alla larghezza della posizione.
## Oltre 1.0 il personaggio può sbordare sulle posizioni vicine (tipico delle visual novel).
@export var max_width_ratio: float = 1.0

## Id del personaggio mostrato ("" se la posizione è vuota).
var character_id: String = ""

var _tween: Tween

@onready var _portrait: TextureRect = %Portrait
@onready var _placeholder: PanelContainer = %Placeholder
@onready var _placeholder_label: Label = %PlaceholderLabel


func _ready() -> void:
	modulate.a = 0.0
	# Ogni istanza usa una copia dello stile, così il colore resta per-personaggio.
	var style: StyleBox = _placeholder.get_theme_stylebox(&"panel")
	if style != null:
		_placeholder.add_theme_stylebox_override(&"panel", style.duplicate())
	# item_rect_changed copre sia il ridimensionamento sia lo spostamento della posizione.
	item_rect_changed.connect(_layout_portrait)


## [param character]: {id, name, color, expression, texture} come prodotto da DialogueRunner.
func show_character(character: Dictionary) -> void:
	var was_empty: bool = character_id.is_empty()
	character_id = str(character.get("id", ""))

	var texture_path: String = str(character.get("texture", ""))
	var texture: Texture2D = null
	if not texture_path.is_empty() and ResourceLoader.exists(texture_path):
		texture = load(texture_path) as Texture2D
	_portrait.texture = texture
	_portrait.visible = texture != null
	_placeholder.visible = texture == null
	_layout_portrait()

	var expression: String = str(character.get("expression", ""))
	_placeholder_label.text = str(character.get("name", character_id)) + ("\n(%s)" % expression if not expression.is_empty() else "")
	var style: StyleBoxFlat = _placeholder.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style != null:
		style.bg_color = character.get("color", Color.GRAY)

	if was_empty:
		_fade_to(1.0)


func hide_character() -> void:
	if character_id.is_empty():
		return
	character_id = ""
	_fade_to(0.0)


## Evidenzia chi parla e scurisce gli altri.
func set_speaking(is_speaking: bool) -> void:
	var tint: Color = SPEAKING_TINT if is_speaking else IDLE_TINT
	_portrait.self_modulate = tint
	_placeholder.self_modulate = tint


## Scala il ritratto mantenendo le proporzioni: alto quanto la posizione (salvo il
## limite di larghezza), centrato in orizzontale e appoggiato al bordo inferiore.
func _layout_portrait() -> void:
	if _portrait == null or _portrait.texture == null:
		return
	var texture_size: Vector2 = _portrait.texture.get_size()
	if texture_size.x <= 0.0 or texture_size.y <= 0.0:
		return
	var scale_factor: float = minf(size.y * max_height_ratio / texture_size.y, size.x * max_width_ratio / texture_size.x)
	var draw_size: Vector2 = texture_size * scale_factor
	var x: float = (size.x - draw_size.x) / 2.0
	# Se sborda, lo sposta quanto basta per restare dentro il contenitore delle posizioni.
	var container: Control = get_parent_control()
	if container != null and draw_size.x <= container.size.x:
		x = clampf(x, -position.x, container.size.x - position.x - draw_size.x)
	_portrait.size = draw_size
	_portrait.position = Vector2(x, size.y - draw_size.y)


func _fade_to(alpha: float) -> void:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", alpha, FADE_TIME)
