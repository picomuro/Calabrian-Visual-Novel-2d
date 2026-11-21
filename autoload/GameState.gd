extends Node
## GameState — autoload con lo stato di gioco globale.
##
## Contiene karma, statistiche del protagonista, inventario, flag narrativi e la
## posizione corrente. Il resto del gioco NON tocca direttamente i dizionari
## interni: usa i metodi pubblici, che validano i valori ed emettono i segnali.
## La UI si aggiorna ascoltando i segnali, senza interrogare lo stato a ogni frame.
##
## Serializzazione: [method to_dict] / [method from_dict] producono e leggono un
## Dictionary compatibile con JSON, usato da SaveManager.


#region Segnali

## Cambio di valore su un asse di karma ([param axis] = "main" finché ne esiste uno solo).
signal karma_changed(axis: String, new_value: int, delta: int)
## Un asse di karma è passato da una fascia all'altra (es. &"neutro" -> &"buono").
signal karma_tier_changed(axis: String, old_tier: StringName, new_tier: StringName)
## Cambio di valore di una statistica del protagonista.
signal stats_changed(stat_id: String, new_value: int, delta: int)
## Cambio di quantità di un oggetto (new_quantity = 0 se l'oggetto è stato rimosso del tutto).
signal inventory_changed(item_id: String, new_quantity: int, delta: int)
## Un flag narrativo è stato impostato o rimosso.
signal flag_changed(flag_id: String, value: bool)
## Il giocatore è entrato in una location ("" = mappa).
signal location_changed(location_id: String)
## Lo stato è stato sostituito in blocco (nuova partita o caricamento):
## chi mostra dati deve rileggere tutto.
signal state_replaced
## Emesso dopo QUALSIASI modifica (karma, stat, oggetti, flag, sostituzione in blocco).
## Comodo per chi dipende da requisiti misti, come le zone della mappa.
signal state_changed

#endregion


#region Configurazione

## Versione del formato dati prodotto da to_dict(). Quando cambia la struttura:
## incrementarla e aggiungere il passo corrispondente in migrate_save_data().
## Storia: 1 = prima versione; 2 = aggiunto "applied_effects" (effetti una volta sola).
const SAVE_FORMAT_VERSION: int = 2

## Asse di karma predefinito.
const KARMA_MAIN: String = "main"
## Assi di karma attivi. Per passare a più assi basta aggiungerli qui
## (es. ["compassione", "onesta"]) e indicare "axis" negli effetti dei dialoghi;
## tutta l'API accetta già un parametro axis opzionale.
const KARMA_AXES: Array[String] = [KARMA_MAIN]
const KARMA_MIN: int = -100
const KARMA_MAX: int = 100

## Soglie delle fasce: valore <= KARMA_EVIL_MAX -> cattivo, >= KARMA_GOOD_MIN -> buono.
const KARMA_EVIL_MAX: int = -10
const KARMA_GOOD_MIN: int = 10
const TIER_EVIL: StringName = &"cattivo"
const TIER_NEUTRAL: StringName = &"neutro"
const TIER_GOOD: StringName = &"buono"

## Statistiche iniziali del protagonista. Aggiungere qui nuove statistiche:
## i salvataggi vecchi riceveranno automaticamente il valore di default.
const DEFAULT_STATS: Dictionary[String, int] = {
	"forza": 1,
	"carisma": 1,
	"intelligenza": 1,
}
## Nomi visualizzati delle statistiche (per UI e descrizione dei requisiti).
const STAT_DISPLAY_NAMES: Dictionary[String, String] = {
	"forza": "Forza",
	"carisma": "Carisma",
	"intelligenza": "Intelligenza",
}
const STAT_MIN: int = 0
const STAT_MAX: int = 99

## Quantità massima per singolo oggetto.
const MAX_ITEM_QUANTITY: int = 999

#endregion


#region Stato interno (accedere solo tramite i metodi pubblici)

var _karma: Dictionary[String, int] = {}
var _stats: Dictionary[String, int] = {}
var _inventory: Dictionary[String, int] = {}
var _flags: Dictionary[String, bool] = {}
## Blocchi di effetti già applicati (chiave -> true): servono a non darli due volte.
var _applied_effects: Dictionary[String, bool] = {}

## Location corrente ("" quando si è sulla mappa).
var current_location_id: String = ""

#endregion


func _ready() -> void:
	_reset_values()


## Riporta lo stato ai valori di una nuova partita.
func reset() -> void:
	_reset_values()
	state_replaced.emit()
	state_changed.emit()


func _reset_values() -> void:
	_karma.clear()
	for axis: String in KARMA_AXES:
		_karma[axis] = 0
	_stats.assign(DEFAULT_STATS)
	_inventory.clear()
	_flags.clear()
	_applied_effects.clear()
	current_location_id = ""


#region Karma

func get_karma(axis: String = KARMA_MAIN) -> int:
	return _karma.get(axis, 0)


func add_karma(delta: int, axis: String = KARMA_MAIN) -> void:
	set_karma(get_karma(axis) + delta, axis)


func set_karma(value: int, axis: String = KARMA_MAIN) -> void:
	if not _karma.has(axis):
		push_warning("GameState: asse di karma sconosciuto '%s', lo creo." % axis)
	var old_value: int = get_karma(axis)
	var new_value: int = clampi(value, KARMA_MIN, KARMA_MAX)
	if _karma.has(axis) and new_value == old_value:
		return
	var old_tier: StringName = karma_tier_for(old_value)
	_karma[axis] = new_value
	karma_changed.emit(axis, new_value, new_value - old_value)
	state_changed.emit()
	var new_tier: StringName = karma_tier_for(new_value)
	if new_tier != old_tier:
		karma_tier_changed.emit(axis, old_tier, new_tier)


## Fascia di karma (&"cattivo" / &"neutro" / &"buono") per un asse.
func get_karma_tier(axis: String = KARMA_MAIN) -> StringName:
	return karma_tier_for(get_karma(axis))


## Converte un valore numerico nella fascia corrispondente.
static func karma_tier_for(value: int) -> StringName:
	if value <= KARMA_EVIL_MAX:
		return TIER_EVIL
	if value >= KARMA_GOOD_MIN:
		return TIER_GOOD
	return TIER_NEUTRAL


## Copia di tutti gli assi di karma (modificarla non altera lo stato).
func get_all_karma() -> Dictionary[String, int]:
	return _karma.duplicate()

#endregion


#region Statistiche

func get_stat(stat_id: String) -> int:
	if not _stats.has(stat_id):
		push_warning("GameState: statistica sconosciuta '%s'." % stat_id)
	return _stats.get(stat_id, 0)


func add_stat(stat_id: String, delta: int) -> void:
	set_stat(stat_id, get_stat(stat_id) + delta)


func set_stat(stat_id: String, value: int) -> void:
	var new_value: int = clampi(value, STAT_MIN, STAT_MAX)
	var old_value: int = _stats.get(stat_id, 0)
	if _stats.has(stat_id) and new_value == old_value:
		return
	_stats[stat_id] = new_value
	stats_changed.emit(stat_id, new_value, new_value - old_value)
	state_changed.emit()


## true se la statistica è almeno [param min_value] (usato dai requisiti delle scelte).
func has_stat_at_least(stat_id: String, min_value: int) -> bool:
	return _stats.get(stat_id, 0) >= min_value


func get_all_stats() -> Dictionary[String, int]:
	return _stats.duplicate()

#endregion


#region Inventario (id oggetto -> quantità; i dati descrittivi stanno negli ItemData .tres)

func get_item_quantity(item_id: String) -> int:
	return _inventory.get(item_id, 0)


func has_item(item_id: String, quantity: int = 1) -> bool:
	return get_item_quantity(item_id) >= quantity


func add_item(item_id: String, quantity: int = 1) -> void:
	if quantity <= 0:
		push_warning("GameState.add_item: quantità non valida (%d) per '%s'." % [quantity, item_id])
		return
	var old_quantity: int = get_item_quantity(item_id)
	var new_quantity: int = mini(old_quantity + quantity, MAX_ITEM_QUANTITY)
	if new_quantity == old_quantity:
		return
	_inventory[item_id] = new_quantity
	inventory_changed.emit(item_id, new_quantity, new_quantity - old_quantity)
	state_changed.emit()


## Rimuove [param quantity] pezzi. Ritorna false (senza modificare nulla) se non bastano.
func remove_item(item_id: String, quantity: int = 1) -> bool:
	if quantity <= 0:
		push_warning("GameState.remove_item: quantità non valida (%d) per '%s'." % [quantity, item_id])
		return false
	var old_quantity: int = get_item_quantity(item_id)
	if old_quantity < quantity:
		return false
	var new_quantity: int = old_quantity - quantity
	if new_quantity == 0:
		_inventory.erase(item_id)
	else:
		_inventory[item_id] = new_quantity
	inventory_changed.emit(item_id, new_quantity, -quantity)
	state_changed.emit()
	return true


func get_inventory() -> Dictionary[String, int]:
	return _inventory.duplicate()

#endregion


#region Flag narrativi

## true solo se il flag esiste ed è attivo.
func has_flag(flag_id: String) -> bool:
	return _flags.get(flag_id, false)


func set_flag(flag_id: String, value: bool = true) -> void:
	if has_flag(flag_id) == value:
		return
	if value:
		_flags[flag_id] = true
	else:
		_flags.erase(flag_id)
	flag_changed.emit(flag_id, value)
	state_changed.emit()


func clear_flag(flag_id: String) -> void:
	set_flag(flag_id, false)


func get_all_flags() -> Dictionary[String, bool]:
	return _flags.duplicate()

#endregion


#region Posizione

func set_current_location(location_id: String) -> void:
	if location_id == current_location_id:
		return
	current_location_id = location_id
	location_changed.emit(location_id)

#endregion


#region Effetti e requisiti (formato condiviso da dialoghi, zone della mappa, ecc.)

## Applica un blocco "effects" letto dai dati. Formato:
## [codeblock]
## {
##   "karma": 5,                          # oppure {"main": 5, "altro_asse": -2}
##   "stats": {"carisma": 1},             # delta
##   "items": {"chiave": 1, "moneta": -3},# >0 aggiunge, <0 rimuove
##   "flags": {"porta_aperta": true}      # oppure ["porta_aperta"]
## }
## [/codeblock]
func apply_effects(effects: Dictionary) -> void:
	for key: Variant in effects:
		var value: Variant = effects[key]
		match str(key):
			"karma":
				if value is Dictionary:
					for axis: Variant in value:
						add_karma(_to_int(value[axis], 0), str(axis))
				else:
					add_karma(_to_int(value, 0))
			"stats":
				if value is Dictionary:
					for stat_id: Variant in value:
						add_stat(str(stat_id), _to_int(value[stat_id], 0))
			"items":
				if value is Dictionary:
					for item_id: Variant in value:
						var quantity: int = _to_int(value[item_id], 0)
						if quantity > 0:
							add_item(str(item_id), quantity)
						elif quantity < 0 and not remove_item(str(item_id), -quantity):
							push_warning("GameState.apply_effects: non ci sono %d '%s' da rimuovere." % [-quantity, item_id])
			"flags":
				if value is Dictionary:
					for flag_id: Variant in value:
						set_flag(str(flag_id), value[flag_id] == true)
				elif value is Array:
					for flag_id: Variant in value:
						set_flag(str(flag_id), true)
			_:
				push_warning("GameState.apply_effects: effetto sconosciuto '%s'." % key)


## Applica [param effects] solo la prima volta che viene usata [param key] in questa
## partita; le volte successive non fa nulla. Ritorna true se gli effetti sono stati applicati.
## Evita di raccogliere più volte le stesse ricompense rigiocando un dialogo.
## La chiave la decide chi chiama (es. "spiaggia/mirta_racconto#scelta").
func apply_effects_once(key: String, effects: Dictionary) -> bool:
	if effects.is_empty() or _applied_effects.has(key):
		return false
	_applied_effects[key] = true
	apply_effects(effects)
	return true


## True se il blocco di effetti con questa chiave è già stato applicato.
func has_applied_effects(key: String) -> bool:
	return _applied_effects.has(key)


## Verifica un blocco "requires". Tutte le condizioni devono essere vere. Formato:
## [codeblock]
## {
##   "stats": {"forza": 3},               # valore minimo
##   "items": {"moneta": 3},              # quantità minima, oppure ["chiave"]
##   "flags": {"porta_aperta": true, "boss_sconfitto": false},  # oppure ["porta_aperta"]
##   "karma": {"min": 10, "max": 50, "axis": "main"},           # tutti opzionali
##   "karma_tier": "buono"                # oppure ["buono", "neutro"]
## }
## [/codeblock]
## Un requisito sconosciuto viene considerato NON soddisfatto (con warning).
func meets_requirements(requirements: Dictionary) -> bool:
	for key: Variant in requirements:
		var value: Variant = requirements[key]
		match str(key):
			"stats":
				if value is Dictionary:
					for stat_id: Variant in value:
						if not has_stat_at_least(str(stat_id), _to_int(value[stat_id], 0)):
							return false
			"items":
				if value is Dictionary:
					for item_id: Variant in value:
						if not has_item(str(item_id), _to_int(value[item_id], 1)):
							return false
				elif value is Array:
					for item_id: Variant in value:
						if not has_item(str(item_id)):
							return false
			"flags":
				if value is Dictionary:
					for flag_id: Variant in value:
						if has_flag(str(flag_id)) != (value[flag_id] == true):
							return false
				elif value is Array:
					for flag_id: Variant in value:
						if not has_flag(str(flag_id)):
							return false
			"karma":
				if value is Dictionary:
					var current: int = get_karma(str(value.get("axis", KARMA_MAIN)))
					if value.has("min") and current < _to_int(value["min"], 0):
						return false
					if value.has("max") and current > _to_int(value["max"], 0):
						return false
			"karma_tier":
				var tier: String = String(get_karma_tier())
				var allowed: Array = value if value is Array else [value]
				var found: bool = false
				for allowed_tier: Variant in allowed:
					if str(allowed_tier) == tier:
						found = true
				if not found:
					return false
			_:
				push_warning("GameState.meets_requirements: requisito sconosciuto '%s'." % key)
				return false
	return true


## Controlla un blocco "effects" scritto nei dati senza applicarlo.
## Ritorna l'elenco dei problemi (vuoto se è tutto valido). Usato dal validatore dei dialoghi.
func validate_effects(effects: Variant) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not effects is Dictionary:
		issues.append("'effects' deve essere un oggetto")
		return issues
	for key: Variant in effects:
		var value: Variant = effects[key]
		match str(key):
			"karma":
				if value is Dictionary:
					for axis: Variant in value:
						_check_karma_axis(issues, str(axis))
						_check_number(issues, value[axis], "karma.%s" % axis)
				else:
					_check_number(issues, value, "karma")
			"stats":
				_check_number_map(issues, value, "stats", _check_stat_id)
			"items":
				_check_number_map(issues, value, "items", _check_item_id)
			"flags":
				_check_flags(issues, value)
			_:
				issues.append("effetto sconosciuto '%s' (validi: karma, stats, items, flags)" % key)
	return issues


## Controlla un blocco "requires" scritto nei dati senza valutarlo.
## Ritorna l'elenco dei problemi (vuoto se è tutto valido).
func validate_requirements(requirements: Variant) -> PackedStringArray:
	var issues: PackedStringArray = []
	if not requirements is Dictionary:
		issues.append("'requires' deve essere un oggetto")
		return issues
	for key: Variant in requirements:
		var value: Variant = requirements[key]
		match str(key):
			"stats":
				_check_number_map(issues, value, "stats", _check_stat_id)
			"items":
				if value is Array:
					for item_id: Variant in value:
						_check_item_id(issues, str(item_id))
				else:
					_check_number_map(issues, value, "items", _check_item_id)
			"flags":
				_check_flags(issues, value)
			"karma":
				if not value is Dictionary:
					issues.append("'karma' nei requisiti deve essere un oggetto {min, max, axis}")
					continue
				for karma_key: Variant in value:
					match str(karma_key):
						"min", "max":
							_check_number(issues, value[karma_key], "karma.%s" % karma_key)
						"axis":
							_check_karma_axis(issues, str(value[karma_key]))
						_:
							issues.append("chiave '%s' non valida in 'karma' (valide: min, max, axis)" % karma_key)
			"karma_tier":
				var tiers: Array = value if value is Array else [value]
				for tier: Variant in tiers:
					if not StringName(str(tier)) in [TIER_EVIL, TIER_NEUTRAL, TIER_GOOD]:
						issues.append("fascia di karma '%s' sconosciuta (valide: cattivo, neutro, buono)" % tier)
			_:
				issues.append("requisito sconosciuto '%s' (validi: stats, items, flags, karma, karma_tier)" % key)
	return issues


func _check_number(issues: PackedStringArray, value: Variant, label: String) -> void:
	if not (value is int or value is float):
		issues.append("'%s' deve essere un numero" % label)


## {id: numero}: controlla ogni id con [param check_id] e che i valori siano numeri.
func _check_number_map(issues: PackedStringArray, value: Variant, label: String, check_id: Callable) -> void:
	if not value is Dictionary:
		issues.append("'%s' deve essere un oggetto {id: numero}" % label)
		return
	for id: Variant in value:
		check_id.call(issues, str(id))
		_check_number(issues, value[id], "%s.%s" % [label, id])


func _check_flags(issues: PackedStringArray, value: Variant) -> void:
	if value is Dictionary:
		for flag_id: Variant in value:
			if not value[flag_id] is bool:
				issues.append("il flag '%s' deve valere true o false" % flag_id)
	elif not value is Array:
		issues.append("'flags' deve essere un oggetto {flag: true/false} o un elenco")


func _check_stat_id(issues: PackedStringArray, stat_id: String) -> void:
	if not DEFAULT_STATS.has(stat_id):
		issues.append("statistica '%s' sconosciuta (valide: %s)" % [stat_id, ", ".join(DEFAULT_STATS.keys())])


func _check_item_id(issues: PackedStringArray, item_id: String) -> void:
	if not ResourceLoader.exists(ItemData.get_item_path(item_id)):
		issues.append("oggetto '%s' inesistente (manca %s)" % [item_id, ItemData.get_item_path(item_id)])


func _check_karma_axis(issues: PackedStringArray, axis: String) -> void:
	if not axis in KARMA_AXES:
		issues.append("asse di karma '%s' sconosciuto (validi: %s)" % [axis, ", ".join(KARMA_AXES)])


## Testo leggibile per i requisiti visibili al giocatore (es. "Carisma 3, Moneta x3").
## I flag non vengono descritti per non svelare la trama. Ritorna "" se non c'è nulla da mostrare.
func describe_requirements(requirements: Dictionary) -> String:
	var parts: PackedStringArray = []
	var stats_req: Variant = requirements.get("stats", {})
	if stats_req is Dictionary:
		for stat_id: Variant in stats_req:
			parts.append("%s %d" % [get_stat_display_name(str(stat_id)), _to_int(stats_req[stat_id], 0)])
	var items_req: Variant = requirements.get("items", {})
	if items_req is Array:
		for item_id: Variant in items_req:
			parts.append(ItemData.get_display_name(str(item_id)))
	elif items_req is Dictionary:
		for item_id: Variant in items_req:
			var quantity: int = _to_int(items_req[item_id], 1)
			var item_name: String = ItemData.get_display_name(str(item_id))
			parts.append(item_name if quantity <= 1 else "%s x%d" % [item_name, quantity])
	var karma_req: Variant = requirements.get("karma", {})
	if karma_req is Dictionary:
		if karma_req.has("min"):
			parts.append("Karma almeno %d" % _to_int(karma_req["min"], 0))
		if karma_req.has("max"):
			parts.append("Karma al massimo %d" % _to_int(karma_req["max"], 0))
	if requirements.has("karma_tier"):
		var tiers: Variant = requirements["karma_tier"]
		parts.append("Karma %s" % (" o ".join(PackedStringArray(tiers)) if tiers is Array else str(tiers)))
	return ", ".join(parts)


## Nome da mostrare per una statistica.
func get_stat_display_name(stat_id: String) -> String:
	return STAT_DISPLAY_NAMES.get(stat_id, stat_id.capitalize())

#endregion


#region Serializzazione

## Stato completo come Dictionary serializzabile in JSON.
func to_dict() -> Dictionary:
	return {
		"version": SAVE_FORMAT_VERSION,
		"karma": _karma.duplicate(),
		"stats": _stats.duplicate(),
		"inventory": _inventory.duplicate(),
		"flags": _flags.duplicate(),
		"applied_effects": _applied_effects.keys(),
		"location_id": current_location_id,
	}


## Versione di un salvataggio letto da file (quelli senza il campo sono della versione 1).
static func get_save_version(data: Dictionary) -> int:
	return maxi(_to_int(data.get("version", 1), 1), 1)


## Porta i dati di un salvataggio vecchio al formato attuale, un passo di versione
## alla volta. Non modifica [param data]: ritorna una copia aggiornata.
static func migrate_save_data(data: Dictionary) -> Dictionary:
	var migrated: Dictionary = data.duplicate(true)
	var version: int = get_save_version(migrated)
	while version < SAVE_FORMAT_VERSION:
		match version:
			1:
				# 1 -> 2: nessun effetto risulta ancora applicato.
				if not migrated.get("applied_effects", null) is Array:
					migrated["applied_effects"] = []
		version += 1
	migrated["version"] = maxi(version, SAVE_FORMAT_VERSION)
	return migrated


## Sostituisce lo stato con i dati di [param data] (tipicamente letti da JSON).
## I salvataggi vecchi vengono prima convertiti con migrate_save_data(). Parte dai valori
## di default, così i campi mancanti restano validi; i numeri JSON (float) diventano int.
## Ritorna false, senza toccare lo stato, se il salvataggio viene da una versione del
## gioco più recente: leggerlo perderebbe dati che questa versione non conosce.
func from_dict(source: Dictionary) -> bool:
	var version: int = get_save_version(source)
	if version > SAVE_FORMAT_VERSION:
		push_warning("GameState: salvataggio di una versione più recente (%d > %d), non caricato." % [version, SAVE_FORMAT_VERSION])
		return false
	var data: Dictionary = migrate_save_data(source)
	_reset_values()

	# Karma: accetta sia il formato a più assi {"main": 5} sia un singolo numero.
	var raw_karma: Variant = data.get("karma", {})
	if raw_karma is Dictionary:
		for axis: Variant in raw_karma:
			_karma[str(axis)] = clampi(_to_int(raw_karma[axis], 0), KARMA_MIN, KARMA_MAX)
	elif raw_karma is float or raw_karma is int:
		_karma[KARMA_MAIN] = clampi(_to_int(raw_karma, 0), KARMA_MIN, KARMA_MAX)

	var raw_stats: Variant = data.get("stats", {})
	if raw_stats is Dictionary:
		for stat_id: Variant in raw_stats:
			_stats[str(stat_id)] = clampi(_to_int(raw_stats[stat_id], 0), STAT_MIN, STAT_MAX)

	var raw_inventory: Variant = data.get("inventory", {})
	if raw_inventory is Dictionary:
		for item_id: Variant in raw_inventory:
			var quantity: int = clampi(_to_int(raw_inventory[item_id], 0), 0, MAX_ITEM_QUANTITY)
			if quantity > 0:
				_inventory[str(item_id)] = quantity

	var raw_flags: Variant = data.get("flags", {})
	if raw_flags is Dictionary:
		for flag_id: Variant in raw_flags:
			if raw_flags[flag_id] == true:
				_flags[str(flag_id)] = true

	var raw_applied: Variant = data.get("applied_effects", [])
	if raw_applied is Array:
		for key: Variant in raw_applied:
			_applied_effects[str(key)] = true

	current_location_id = str(data.get("location_id", ""))

	state_replaced.emit()
	state_changed.emit()
	return true


## Conversione difensiva Variant -> int (i valori JSON possono essere float o tipi errati).
static func _to_int(value: Variant, fallback: int) -> int:
	if value is int:
		return value
	if value is float:
		return roundi(value)
	return fallback

#endregion
