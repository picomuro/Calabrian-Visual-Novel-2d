extends Control
## GameMenuOverlay — menu di gioco aperto dal pulsante "Menu" della mappa.
##
## Salva:          scrive lo slot manuale.
## Carica:         riporta allo slot manuale (con conferma).
## Nuova partita:  riparte da zero (con conferma); lo slot manuale resta.
## Dopo Carica e Nuova partita aggiorna subito anche lo slot automatico, così
## alla prossima apertura dell'app si riprende da lì.
## Va aperto in pausa (SceneManager.open_overlay(..., true)); il tasto indietro
## e il tocco sullo sfondo lo chiudono.


## Esito di un'azione da mostrare al giocatore (es. nel toast della mappa).
signal notice(message: String)
## Chiede a SceneManager di chiudere il menu.
signal close_requested


const LOAD_CONFIRM_MESSAGE: String = "Tornare al salvataggio manuale? I progressi fatti dopo andranno persi."
const NEW_GAME_CONFIRM_MESSAGE: String = "Iniziare una nuova partita? I progressi attuali andranno persi; il salvataggio manuale resta."

@onready var _info_label: Label = %InfoLabel
@onready var _save_button: Button = %SaveButton
@onready var _load_button: Button = %LoadButton
@onready var _new_game_button: Button = %NewGameButton
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_close_button.pressed.connect(close_requested.emit)
	_refresh_info()


func _gui_input(event: InputEvent) -> void:
	# Tocco sullo sfondo (fuori dal pannello) = chiudi.
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close_requested.emit()


func _refresh_info() -> void:
	var info: Dictionary = SaveManager.peek_save_info(SaveManager.SLOT_MANUAL)
	var saved_at: String = SaveManager.format_saved_at(str(info.get("saved_at", "")))
	if info.is_empty():
		_info_label.text = "Nessun salvataggio manuale."
	elif saved_at.is_empty():
		_info_label.text = "Salvataggio manuale presente."
	else:
		_info_label.text = "Salvataggio manuale: %s" % saved_at
	_load_button.disabled = info.is_empty()


func _on_save_pressed() -> void:
	if SaveManager.save_game(SaveManager.SLOT_MANUAL):
		_finish("Partita salvata.")
	else:
		_finish("Salvataggio non riuscito.")


func _on_load_pressed() -> void:
	SceneManager.ask_confirmation(LOAD_CONFIRM_MESSAGE, "Carica", "Annulla", _load_manual)


func _on_new_game_pressed() -> void:
	SceneManager.ask_confirmation(NEW_GAME_CONFIRM_MESSAGE, "Nuova partita", "Annulla", _start_new_game)


func _load_manual() -> void:
	if SaveManager.load_game(SaveManager.SLOT_MANUAL):
		SaveManager.autosave()
		_finish("Salvataggio caricato.")
	else:
		_finish("Caricamento non riuscito.")


func _start_new_game() -> void:
	GameState.reset()
	SaveManager.autosave()
	_finish("Nuova partita iniziata.")


func _finish(message: String) -> void:
	notice.emit(message)
	close_requested.emit()
