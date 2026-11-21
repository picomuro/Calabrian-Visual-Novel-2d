class_name MapZone
extends TextureButton
## MapZone — zona cliccabile della mappa associata a una location.
##
## Si posiziona con le ancore (frazioni del riquadro mappa), quindi resta
## allineata all'immagine su qualsiasi schermo. Se non ha texture mostra un
## pannello segnaposto colorato con il nome.
##
## Non conosce SceneManager: quando viene toccata emette un segnale e la
## MapScene decide cosa fare. Lo stato bloccato/sbloccato si aggiorna da solo
## ascoltando GameState.state_changed.


## Toccata una zona accessibile.
signal zone_selected(location_id: String)
## Toccata una zona bloccata; [param hint] è il messaggio da mostrare al giocatore.
signal locked_zone_selected(location_id: String, hint: String)


const LOCKED_TINT: Color = Color(0.55, 0.55, 0.6)
const PRESS_SCALE: Vector2 = Vector2(0.95, 0.95)

## Id della location: il dialogo caricato sarà res://data/dialogues/<location_id>.json.
@export var location_id: String = ""
## Nome mostrato sulla zona (vuoto = il nome in data/locations.json).
@export var display_name: String = ""
## Requisiti per accedere, stesso formato dei dialoghi (es. {"flags": {"loft_aperto": true}}).
@export var requires: Dictionary = {}
## Messaggio mostrato se la zona è bloccata (vuoto = descrizione automatica dei requisiti).
@export_multiline var locked_hint: String = ""
## Colore del pannello segnaposto.
@export var placeholder_color: Color = Color(0.45, 0.33, 0.2)

## true se i requisiti sono soddisfatti.
var is_unlocked: bool = true

@onready var _placeholder: PanelContainer = %Placeholder
@onready var _name_label: Label = %NameLabel
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_name_label.text = display_name if not display_name.is_empty() else GameRegistry.get_location_name(location_id)
	# Copia dello stile per poter colorare ogni zona in modo diverso.
	var style: StyleBoxFlat = _placeholder.get_theme_stylebox(&"panel").duplicate() as StyleBoxFlat
	if style != null:
		style.bg_color = placeholder_color
		_placeholder.add_theme_stylebox_override(&"panel", style)
	_placeholder.visible = texture_normal == null

	pressed.connect(_on_pressed)
	button_down.connect(_set_pressed_scale.bind(true))
	button_up.connect(_set_pressed_scale.bind(false))
	resized.connect(func() -> void: pivot_offset = size / 2.0)
	GameState.state_changed.connect(refresh)
	refresh()


## Ricalcola lo stato bloccato/sbloccato e l'aspetto.
func refresh() -> void:
	is_unlocked = GameState.meets_requirements(requires)
	modulate = Color.WHITE if is_unlocked else LOCKED_TINT
	_status_label.visible = not is_unlocked


func _on_pressed() -> void:
	if is_unlocked:
		zone_selected.emit(location_id)
		return
	var hint: String = locked_hint
	if hint.is_empty():
		var description: String = GameState.describe_requirements(requires)
		hint = "Serve: %s" % description if not description.is_empty() else "Non ancora accessibile."
	locked_zone_selected.emit(location_id, hint)


func _set_pressed_scale(is_down: bool) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", PRESS_SCALE if is_down else Vector2.ONE, 0.08)
