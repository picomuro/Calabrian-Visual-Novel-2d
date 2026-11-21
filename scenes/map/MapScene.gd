extends Control
## MapScene — mappa del gioco con zone cliccabili.
##
## Il riquadro mappa è dentro un AspectRatioContainer (16:9, modalità "fit"):
## l'immagine non viene mai tagliata e le zone, ancorate in frazioni del
## riquadro, restano allineate su qualsiasi formato di schermo. Lo spazio in
## più sugli schermi più larghi del 16:9 (es. 20:9) è riempito dal colore di sfondo.
##
## Le zone sono figlie di %MapFrame: per aggiungerne una basta istanziare
## MapZone.tscn lì dentro e impostare location_id (vedi README).


const TOAST_VISIBLE_TIME: float = 2.5
const TOAST_FADE_TIME: float = 0.25
const GAME_MENU_PATH: String = "res://scenes/ui/GameMenuOverlay.tscn"

var _toast_tween: Tween

@onready var _map_frame: Control = %MapFrame
@onready var _toast_panel: PanelContainer = %ToastPanel
@onready var _toast_label: Label = %ToastLabel
@onready var _open_menu_button: Button = %OpenMenuButton


func _ready() -> void:
	_toast_panel.modulate.a = 0.0
	_open_menu_button.pressed.connect(open_game_menu)
	for zone: MapZone in get_zones():
		zone.zone_selected.connect(_on_zone_selected)
		zone.locked_zone_selected.connect(_on_locked_zone_selected)


## Apre il menu (salva, carica, nuova partita) mettendo il gioco in pausa.
func open_game_menu() -> Node:
	var menu: Node = SceneManager.open_overlay(GAME_MENU_PATH, {}, true)
	if menu != null and menu.has_signal(&"notice") and not menu.is_connected(&"notice", show_toast):
		menu.connect(&"notice", show_toast)
	return menu


## Tutte le zone presenti nella mappa.
func get_zones() -> Array[MapZone]:
	var zones: Array[MapZone] = []
	for child: Node in _map_frame.get_children():
		if child is MapZone:
			zones.append(child)
	return zones


## Mostra un breve messaggio in basso che scompare da solo.
func show_toast(message: String) -> void:
	_toast_label.text = message
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast_panel, "modulate:a", 1.0, TOAST_FADE_TIME)
	_toast_tween.tween_interval(TOAST_VISIBLE_TIME)
	_toast_tween.tween_property(_toast_panel, "modulate:a", 0.0, TOAST_FADE_TIME)


func _on_zone_selected(location_id: String) -> void:
	SceneManager.go_to_location(location_id)


func _on_locked_zone_selected(_location_id: String, hint: String) -> void:
	show_toast(hint)
