class_name ItemData
extends Resource
## ItemData — definizione di un oggetto dell'inventario.
##
## Ogni oggetto è un file .tres in res://data/items/ chiamato come il suo id
## (es. res://data/items/chiave_antica.tres con id = "chiave_antica").
## GameState memorizza solo id -> quantità; nome, descrizione e icona stanno qui.


const ITEMS_DIR: String = "res://data/items/"

## Identificatore usato nei dialoghi e nei salvataggi (deve coincidere col nome del file).
@export var id: String = ""
## Nome mostrato al giocatore.
@export var display_name: String = ""
## Descrizione mostrata nell'inventario.
@export_multiline var description: String = ""
## Icona dell'oggetto (per ora una GradientTexture2D generata come segnaposto).
@export var icon: Texture2D


## Percorso convenzionale del file di un oggetto.
static func get_item_path(item_id: String) -> String:
	return ITEMS_DIR.path_join(item_id + ".tres")


## Carica la definizione di un oggetto. Ritorna null se il file non esiste.
## (load() usa la cache di Godot, quindi chiamate ripetute sono economiche.)
static func load_by_id(item_id: String) -> ItemData:
	var path: String = get_item_path(item_id)
	if not ResourceLoader.exists(path):
		push_warning("ItemData: nessuna definizione per l'oggetto '%s' (%s)." % [item_id, path])
		return null
	return load(path) as ItemData


## Nome visualizzato dell'oggetto, o l'id stesso se la definizione manca.
static func get_display_name(item_id: String) -> String:
	var item: ItemData = load_by_id(item_id)
	if item == null or item.display_name.is_empty():
		return item_id
	return item.display_name
