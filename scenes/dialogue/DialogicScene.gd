extends Control
## DialogicScene — ospita una timeline Dialogic come se fosse una location.
##
## SceneManager.go_to_location(id) apre questa scena quando esiste
## res://data/dialogic/timelines/<id>.dtl (altrimenti usa la DialogueScene con il JSON).
## L'interfaccia (riquadro testo, ritratti, scelte) è creata da Dialogic stesso;
## questa scena si limita ad avviare la timeline e a tornare alla mappa alla fine.
## Gli effetti sul gioco si scrivono nella timeline con "do GameState.metodo(...)".
## Il tasto indietro è gestito da SceneManager (conferma + ritorno alla mappa).


## Timeline da avviare se la scena viene aperta senza parametri (F6 nell'editor).
@export_file("*.dtl") var timeline_path: String = "res://data/dialogic/timelines/viaggio_soverato.dtl"


## Chiamato da SceneManager prima di _ready().
func receive_params(params: Dictionary) -> void:
	timeline_path = str(params.get("timeline_path", timeline_path))


func _ready() -> void:
	# I tocchi devono arrivare a Dialogic, non a questa scena.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ResourceLoader.exists(timeline_path):
		push_error("DialogicScene: timeline inesistente '%s', torno alla mappa." % timeline_path)
		SceneManager.go_to_map()
		return
	DialogicBootstrap.ensure_directories()
	Dialogic.timeline_ended.connect(_on_timeline_ended, CONNECT_ONE_SHOT)
	Dialogic.start(timeline_path)


func _exit_tree() -> void:
	# Se si esce dalla scena a dialogo in corso (es. tasto indietro), chiude la timeline.
	# skip_ending = true: chiude subito e rimuove l'interfaccia di Dialogic; senza, Dialogic
	# avvierebbe una timeline di chiusura e sfondo/ritratti resterebbero sopra la mappa.
	if Dialogic.timeline_ended.is_connected(_on_timeline_ended):
		Dialogic.timeline_ended.disconnect(_on_timeline_ended)
		if Dialogic.current_timeline != null:
			Dialogic.end_timeline(true)


func _on_timeline_ended() -> void:
	SceneManager.go_to_map()
