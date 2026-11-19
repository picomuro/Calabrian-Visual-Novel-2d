class_name SafeAreaMargin
extends MarginContainer
## MarginContainer che somma ai margini base l'area sicura del dispositivo
## (notch, fori della fotocamera, barre di sistema). Su desktop usa solo i margini base.


## Margine minimo su ogni lato, in unità della risoluzione base (1080x1920).
@export var base_margin: int = 32


func _ready() -> void:
	get_viewport().size_changed.connect(_update_margins)
	_update_margins()


func _update_margins() -> void:
	var left: float = 0.0
	var top: float = 0.0
	var right: float = 0.0
	var bottom: float = 0.0
	if OS.has_feature("mobile"):
		var window_size: Vector2 = Vector2(DisplayServer.window_get_size())
		var safe_area: Rect2 = Rect2(DisplayServer.get_display_safe_area())
		if window_size.x > 0.0 and window_size.y > 0.0:
			# L'area sicura è in pixel dello schermo: la convertiamo nelle unità del viewport.
			var scale: Vector2 = get_viewport_rect().size / window_size
			left = safe_area.position.x * scale.x
			top = safe_area.position.y * scale.y
			right = maxf(window_size.x - safe_area.end.x, 0.0) * scale.x
			bottom = maxf(window_size.y - safe_area.end.y, 0.0) * scale.y
	add_theme_constant_override(&"margin_left", base_margin + roundi(left))
	add_theme_constant_override(&"margin_top", base_margin + roundi(top))
	add_theme_constant_override(&"margin_right", base_margin + roundi(right))
	add_theme_constant_override(&"margin_bottom", base_margin + roundi(bottom))
