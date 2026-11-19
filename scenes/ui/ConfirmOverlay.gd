extends Control
## ConfirmOverlay — finestra modale "Sei sicuro?" con due pulsanti.
##
## Si apre con SceneManager.ask_confirmation(...), che passa i testi con
## receive_params() e mette il gioco in pausa finché la finestra è aperta.
## Non conosce SceneManager: comunica solo con i segnali.
## Toccare lo sfondo scuro equivale ad "Annulla".


## Il giocatore ha confermato.
signal confirmed
## Il giocatore ha annullato (pulsante, tocco sullo sfondo o tasto indietro).
signal close_requested


var _message: String = ""
var _confirm_text: String = "Conferma"
var _cancel_text: String = "Annulla"

@onready var _message_label: Label = %MessageLabel
@onready var _confirm_button: Button = %ConfirmButton
@onready var _cancel_button: Button = %CancelButton


## Chiamato da SceneManager prima di _ready().
func receive_params(params: Dictionary) -> void:
	_message = str(params.get("message", _message))
	_confirm_text = str(params.get("confirm_text", _confirm_text))
	_cancel_text = str(params.get("cancel_text", _cancel_text))


func _ready() -> void:
	_message_label.text = _message
	_confirm_button.text = _confirm_text
	_cancel_button.text = _cancel_text
	_confirm_button.pressed.connect(confirmed.emit)
	_cancel_button.pressed.connect(close_requested.emit)


func _gui_input(event: InputEvent) -> void:
	# Tocco sullo sfondo (fuori dal pannello) = annulla.
	var mouse_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_event != null and mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		close_requested.emit()
