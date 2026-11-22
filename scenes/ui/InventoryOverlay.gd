extends Control
## InventoryOverlay — zaino: elenco degli oggetti posseduti con icona, nome,
## descrizione e quantità.
##
## Va aperto in pausa (SceneManager.open_overlay(..., true)). Nomi, descrizioni e
## icone vengono dagli ItemData in data/items/; un oggetto senza file .tres viene
## mostrato con il suo id. Il tasto indietro, "Chiudi" e il tocco sullo sfondo lo chiudono.


## Chiede a SceneManager di chiudere lo zaino.
signal close_requested


const ICON_SIZE: Vector2 = Vector2(112, 112)
const NAME_COLOR: Color = Color(0.95, 0.82, 0.5)
const DESCRIPTION_COLOR: Color = Color(0.85, 0.82, 0.75)

@onready var _scroll: ScrollContainer = %Scroll
@onready var _items_box: VBoxContainer = %Items
@onready var _empty_label: Label = %EmptyLabel
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close_requested.emit)
	refresh()


func _gui_input(event: InputEvent) -> void:
	# Tocco sullo sfondo (fuori dal pannello) = chiudi.
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close_requested.emit()


## Ricostruisce l'elenco dall'inventario di GameState, in ordine alfabetico di nome.
func refresh() -> void:
	for child: Node in _items_box.get_children():
		_items_box.remove_child(child)
		child.queue_free()
	var inventory: Dictionary[String, int] = GameState.get_inventory()
	var entries: Array[Dictionary] = []
	for item_id: String in inventory:
		var item: ItemData = ItemData.load_by_id(item_id) if ResourceLoader.exists(ItemData.get_item_path(item_id)) else null
		entries.append({
			"name": item.display_name if item != null and not item.display_name.is_empty() else item_id,
			"description": item.description if item != null else "",
			"icon": item.icon if item != null else null,
			"quantity": inventory[item_id],
		})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0)
	for entry: Dictionary in entries:
		_items_box.add_child(_build_row(entry))
	_empty_label.visible = entries.is_empty()
	_scroll.visible = not entries.is_empty()


## Nomi degli oggetti mostrati, nell'ordine dell'elenco (usato dai test).
func get_shown_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for row: Node in _items_box.get_children():
		names.append((row.get_node(^"Text/Name") as Label).text)
	return names


func _build_row(entry: Dictionary) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override(&"separation", 28)

	var icon: TextureRect = TextureRect.new()
	icon.custom_minimum_size = ICON_SIZE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = entry["icon"]
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)

	var text_box: VBoxContainer = VBoxContainer.new()
	text_box.name = "Text"
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.alignment = BoxContainer.ALIGNMENT_CENTER
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label: Label = Label.new()
	name_label.name = "Name"
	name_label.text = entry["name"]
	name_label.add_theme_color_override(&"font_color", NAME_COLOR)
	name_label.add_theme_font_size_override(&"font_size", 40)
	text_box.add_child(name_label)
	if not str(entry["description"]).is_empty():
		var description_label: Label = Label.new()
		description_label.text = entry["description"]
		description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description_label.add_theme_color_override(&"font_color", DESCRIPTION_COLOR)
		description_label.add_theme_font_size_override(&"font_size", 30)
		text_box.add_child(description_label)
	row.add_child(text_box)

	var quantity_label: Label = Label.new()
	quantity_label.text = "×%d" % entry["quantity"]
	quantity_label.custom_minimum_size = Vector2(110, 0)
	quantity_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	quantity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(quantity_label)
	return row
