extends HBoxContainer
## Hud — barra in alto sulla mappa: karma e statistiche a sinistra, pulsanti
## "Zaino" e "Menu" a destra.
##
## Si aggiorna da solo a ogni modifica dello stato (GameState.state_changed) e fa
## lampeggiare il karma quando cambia. Non apre nulla da sé: emette
## inventory_requested / menu_requested e ci pensa la scena che lo contiene.


## Il giocatore ha toccato "Zaino".
signal inventory_requested
## Il giocatore ha toccato "Menu".
signal menu_requested


const TIER_COLORS: Dictionary[StringName, Color] = {
	&"cattivo": Color(0.95, 0.45, 0.4),
	&"neutro": Color(0.85, 0.82, 0.75),
	&"buono": Color(0.55, 0.85, 0.5),
}
const FLASH_COLOR: Color = Color(1.8, 1.7, 1.2)
const FLASH_TIME: float = 0.5

var _shown_karma: int = 0
var _flash_tween: Tween

@onready var _karma_label: Label = %KarmaLabel
@onready var _stats_label: Label = %StatsLabel
@onready var _inventory_button: Button = %InventoryButton
@onready var _menu_button: Button = %MenuButton


func _ready() -> void:
	_inventory_button.pressed.connect(inventory_requested.emit)
	_menu_button.pressed.connect(menu_requested.emit)
	GameState.state_changed.connect(refresh)
	_shown_karma = GameState.get_karma()
	refresh()


## Rilegge karma, statistiche e numero di oggetti da GameState.
func refresh() -> void:
	var karma: int = GameState.get_karma()
	var tier: StringName = GameState.get_karma_tier()
	_karma_label.text = "Karma %+d · %s" % [karma, tier]
	_karma_label.add_theme_color_override(&"font_color", TIER_COLORS.get(tier, Color.WHITE))
	if karma != _shown_karma:
		_shown_karma = karma
		_flash(_karma_label)

	var parts: PackedStringArray = []
	for stat_id: String in GameState.DEFAULT_STATS:
		parts.append("%s %d" % [GameState.get_stat_display_name(stat_id), GameState.get_stat(stat_id)])
	_stats_label.text = "   ".join(parts)

	var item_count: int = 0
	for quantity: int in GameState.get_inventory().values():
		item_count += quantity
	_inventory_button.text = "Zaino (%d)" % item_count if item_count > 0 else "Zaino"


func _flash(target: CanvasItem) -> void:
	if _flash_tween != null:
		_flash_tween.kill()
	target.modulate = FLASH_COLOR
	_flash_tween = create_tween()
	_flash_tween.tween_property(target, "modulate", Color.WHITE, FLASH_TIME)
