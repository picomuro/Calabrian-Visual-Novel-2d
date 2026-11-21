extends Node
## SceneManager — cambio scena con dissolvenza, navigazione tra location, overlay e tasto indietro.
##
## - change_scene(path, params): dissolvenza al nero, caricamento in background,
##   sostituzione della scena corrente, dissolvenza di ritorno.
## - go_to_location(id): apre la DialogueScene con res://data/dialogues/<id>.json.
## - open_overlay(path): istanzia una scena (inventario, HUD, conferme...) sopra il gioco.
## - ask_confirmation(...): finestra modale "Sei sicuro?" che mette in pausa il gioco.
##
## Robustezza della navigazione:
## - una richiesta che arriva durante una transizione NON viene scartata: viene
##   eseguita appena la transizione finisce (se ne arrivano più, vince l'ultima);
## - se una destinazione non esiste o non si carica, si torna alla mappa invece di
##   lasciare il giocatore bloccato (e viene emesso navigation_failed).
##
## Passaggio parametri: se la scena istanziata definisce
## `func receive_params(params: Dictionary) -> void`, viene chiamata PRIMA che il
## nodo entri nell'albero (quindi i dati sono già disponibili in _ready()).
## Chiusura overlay: se l'overlay definisce `signal close_requested`, emetterlo
## basta a farlo chiudere, senza che l'overlay conosca SceneManager.


signal transition_started(target_path: String)
signal scene_changed(new_scene: Node)
signal overlay_opened(overlay: Node)
signal overlay_closed(overlay_path: String)
## Una navigazione non è riuscita ([param target] è il percorso della scena o "location:<id>").
signal navigation_failed(target: String, reason: String)


const MAP_SCENE_PATH: String = "res://scenes/map/MapScene.tscn"
const DIALOGUE_SCENE_PATH: String = "res://scenes/dialogue/DialogueScene.tscn"
const DIALOGUES_DIR: String = "res://data/dialogues/"
const CONFIRM_OVERLAY_PATH: String = "res://scenes/ui/ConfirmOverlay.tscn"

const FADE_DURATION: float = 0.35
const FADE_COLOR: Color = Color.BLACK
## Layer dei CanvasLayer: gli overlay stanno sopra al gioco, la dissolvenza sopra a tutto.
const OVERLAY_LAYER: int = 50
const FADE_LAYER: int = 100

## Testi delle conferme del tasto indietro.
const EXIT_GAME_MESSAGE: String = "Vuoi uscire dal gioco?"
const EXIT_GAME_CONFIRM: String = "Esci"
const LEAVE_DIALOGUE_MESSAGE: String = "Tornare alla mappa?\nIl dialogo in corso verrà interrotto."
const LEAVE_DIALOGUE_CONFIRM: String = "Torna alla mappa"
const CANCEL_TEXT: String = "Annulla"


## true durante una transizione: le nuove richieste vengono messe in attesa.
var is_transitioning: bool = false

var _overlay_layer: CanvasLayer
var _fade_layer: CanvasLayer
var _fade_rect: ColorRect
var _overlay_stack: Array[Node] = []
## Overlay modali che tengono il gioco in pausa finché sono aperti.
var _pausing_overlays: Array[Node] = []
## Navigazione richiesta durante una transizione, da eseguire appena finisce.
var _pending_navigation: Callable = Callable()


func _ready() -> void:
	# Continua a funzionare anche se il gioco viene messo in pausa (overlay modali).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_layers()


func _build_layers() -> void:
	_overlay_layer = CanvasLayer.new()
	_overlay_layer.name = "OverlayLayer"
	_overlay_layer.layer = OVERLAY_LAYER
	add_child(_overlay_layer)

	_fade_layer = CanvasLayer.new()
	_fade_layer.name = "FadeLayer"
	_fade_layer.layer = FADE_LAYER
	add_child(_fade_layer)

	# Rettangolo a tutto schermo tramite ancore: si adatta a qualsiasi risoluzione.
	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = FADE_COLOR
	_fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_rect.visible = false
	_fade_layer.add_child(_fade_rect)


#region Cambio scena

## Cambia scena con dissolvenza. Può essere chiamata con o senza `await`.
## Se c'è già una transizione in corso, la richiesta viene eseguita alla sua fine.
func change_scene(scene_path: String, params: Dictionary = {}) -> void:
	if is_transitioning:
		_defer_navigation(change_scene.bind(scene_path, params))
		return
	if not ResourceLoader.exists(scene_path):
		_fail_navigation(scene_path, "scena inesistente")
		return

	is_transitioning = true
	transition_started.emit(scene_path)
	close_all_overlays()

	# Il caricamento parte subito e procede in parallelo alla dissolvenza.
	ResourceLoader.load_threaded_request(scene_path, "PackedScene")
	await _fade_to(1.0)
	while ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await get_tree().process_frame

	var packed: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed != null:
		var new_scene: Node = packed.instantiate()
		_pass_params(new_scene, params)
		_replace_current_scene(new_scene)
		scene_changed.emit(new_scene)

	await _fade_to(0.0)
	is_transitioning = false

	if packed == null:
		_fail_navigation(scene_path, "impossibile caricare la scena")
	_run_pending_navigation()


## Entra in una location aprendo la DialogueScene con il file JSON associato.
## Se la location non ha un dialogo, torna alla mappa (mai bloccare il giocatore).
func go_to_location(location_id: String) -> void:
	if is_transitioning:
		_defer_navigation(go_to_location.bind(location_id))
		return
	var dialogue_path: String = get_dialogue_path(location_id)
	if not FileAccess.file_exists(dialogue_path):
		_fail_navigation("location:" + location_id, "nessun dialogo (%s)" % dialogue_path)
		return
	GameState.set_current_location(location_id)
	change_scene(DIALOGUE_SCENE_PATH, {"location_id": location_id, "dialogue_path": dialogue_path})


## Torna alla mappa.
func go_to_map() -> void:
	if is_transitioning:
		_defer_navigation(go_to_map)
		return
	GameState.set_current_location("")
	change_scene(MAP_SCENE_PATH)


## true se la scena corrente è la mappa.
func is_on_map() -> bool:
	var current: Node = get_tree().current_scene
	return current != null and current.scene_file_path == MAP_SCENE_PATH


## Convenzione: un file JSON per location, con lo stesso nome dell'id.
static func get_dialogue_path(location_id: String) -> String:
	return DIALOGUES_DIR.path_join(location_id + ".json")


## Memorizza una navigazione arrivata durante una transizione (vince l'ultima).
func _defer_navigation(navigation: Callable) -> void:
	_pending_navigation = navigation


func _run_pending_navigation() -> void:
	if not _pending_navigation.is_valid():
		return
	var navigation: Callable = _pending_navigation
	_pending_navigation = Callable()
	navigation.call()


## Registra l'errore e, se non si è già sulla mappa, ci riporta il giocatore.
func _fail_navigation(target: String, reason: String) -> void:
	push_error("SceneManager: navigazione verso '%s' fallita: %s." % [target, reason])
	navigation_failed.emit(target, reason)
	if target != MAP_SCENE_PATH and not is_on_map():
		go_to_map()


func _replace_current_scene(new_scene: Node) -> void:
	var tree: SceneTree = get_tree()
	var old_scene: Node = tree.current_scene
	tree.root.add_child(new_scene)
	tree.current_scene = new_scene
	if old_scene != null:
		old_scene.queue_free()


func _fade_to(target_alpha: float) -> void:
	# Durante la dissolvenza il rettangolo blocca i tocchi sulla scena sottostante.
	_fade_rect.visible = true
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target_alpha, FADE_DURATION)
	await tween.finished
	if is_zero_approx(target_alpha):
		_fade_rect.visible = false
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

#endregion


#region Overlay

## Apre un overlay sopra la scena corrente. Se lo stesso overlay è già aperto
## lo restituisce senza duplicarlo. Ritorna null in caso di errore.
## Con [param pause_game] il gioco sottostante resta in pausa finché l'overlay è aperto
## (gli overlay funzionano comunque, perché figli di SceneManager).
func open_overlay(scene_path: String, params: Dictionary = {}, pause_game: bool = false) -> Node:
	var existing: Node = get_overlay(scene_path)
	if existing != null:
		return existing
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("SceneManager: overlay inesistente '%s'." % scene_path)
		return null

	var overlay: Node = packed.instantiate()
	_pass_params(overlay, params)
	if overlay.has_signal(&"close_requested"):
		overlay.connect(&"close_requested", close_overlay.bind(overlay))
	_overlay_layer.add_child(overlay)
	_overlay_stack.append(overlay)
	if pause_game:
		_pausing_overlays.append(overlay)
		get_tree().paused = true
	overlay_opened.emit(overlay)
	return overlay


func close_overlay(overlay: Node) -> void:
	if not _overlay_stack.has(overlay):
		return
	_overlay_stack.erase(overlay)
	if _pausing_overlays.has(overlay):
		_pausing_overlays.erase(overlay)
		if _pausing_overlays.is_empty():
			get_tree().paused = false
	var path: String = overlay.scene_file_path
	overlay.queue_free()
	overlay_closed.emit(path)


## Chiude l'overlay più in alto. Ritorna false se non ce n'erano.
func close_top_overlay() -> bool:
	if _overlay_stack.is_empty():
		return false
	close_overlay(_overlay_stack.back())
	return true


func close_all_overlays() -> void:
	while close_top_overlay():
		pass


func has_open_overlay() -> bool:
	return not _overlay_stack.is_empty()


## Overlay aperto a partire da [param scene_path], oppure null.
func get_overlay(scene_path: String) -> Node:
	for overlay: Node in _overlay_stack:
		if overlay.scene_file_path == scene_path:
			return overlay
	return null


## Mostra una conferma modale (gioco in pausa). Se il giocatore conferma, la
## finestra si chiude e viene chiamato [param on_confirm]; altrimenti si chiude e basta.
func ask_confirmation(message: String, confirm_text: String, cancel_text: String, on_confirm: Callable) -> Node:
	var overlay: Node = open_overlay(CONFIRM_OVERLAY_PATH, {
		"message": message,
		"confirm_text": confirm_text,
		"cancel_text": cancel_text,
	}, true)
	if overlay != null and overlay.has_signal(&"confirmed"):
		overlay.connect(&"confirmed", _on_confirmation_accepted.bind(overlay, on_confirm), CONNECT_ONE_SHOT)
	return overlay


func _on_confirmation_accepted(overlay: Node, on_confirm: Callable) -> void:
	# Prima chiude (e toglie la pausa), poi esegue l'azione.
	close_overlay(overlay)
	if on_confirm.is_valid():
		on_confirm.call()

#endregion


#region Tasto indietro

func _notification(what: int) -> void:
	# Richiede application/config/quit_on_go_back=false in project.godot.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_handle_back()


func _unhandled_input(event: InputEvent) -> void:
	# Su desktop Esc (ui_cancel) si comporta come il tasto indietro di Android.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_handle_back()


## Indietro: chiude l'overlay in cima; altrimenti chiede conferma per uscire dal
## gioco (sulla mappa) o per tornare alla mappa (in un dialogo).
func _handle_back() -> void:
	if is_transitioning:
		return
	if close_top_overlay():
		return
	if is_on_map():
		ask_confirmation(EXIT_GAME_MESSAGE, EXIT_GAME_CONFIRM, CANCEL_TEXT, get_tree().quit)
	else:
		ask_confirmation(LEAVE_DIALOGUE_MESSAGE, LEAVE_DIALOGUE_CONFIRM, CANCEL_TEXT, go_to_map)

#endregion


func _pass_params(node: Node, params: Dictionary) -> void:
	if node.has_method(&"receive_params"):
		node.call(&"receive_params", params)
