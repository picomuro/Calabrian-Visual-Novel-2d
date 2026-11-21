extends Node
## Test di fumo del progetto (stato, salvataggi, dialoghi, mappa, navigazione), da riga di comando:
##   godot --headless --path . res://tests/smoke_test.tscn
## (è una scena e non uno script --script: così gli autoload sono già registrati
## quando vengono compilati gli script che li usano, esattamente come nel gioco.)
## Codice di uscita 0 = tutto ok, 1 = almeno un controllo fallito.

const TEST_SAVE_PATH: String = "user://smoke_test_save.json"

var _failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Attende un frame: gli autoload sono pronti.
	await get_tree().process_frame
	var game_state: Node = get_tree().root.get_node(^"/root/GameState")
	var save_manager: Node = get_tree().root.get_node(^"/root/SaveManager")
	var scene_manager: Node = get_tree().root.get_node(^"/root/SceneManager")
	_check(game_state != null and save_manager != null and scene_manager != null, "autoload presenti")
	# Il test non deve mai toccare i salvataggi veri: niente salvataggio automatico,
	# file di prova separati e stato di partenza pulito (all'avvio SaveManager
	# potrebbe aver ripreso il salvataggio automatico del gioco).
	save_manager.autosave_enabled = false
	save_manager.save_path = TEST_SAVE_PATH
	game_state.reset()

	# --- Karma e fasce ---
	var karma_events: Array[int] = []
	var tier_events: Array[StringName] = []
	game_state.karma_changed.connect(func(_axis: String, value: int, _delta: int) -> void: karma_events.append(value))
	game_state.karma_tier_changed.connect(func(_axis: String, _old: StringName, new_tier: StringName) -> void: tier_events.append(new_tier))
	game_state.add_karma(12)
	_check(game_state.get_karma() == 12, "karma = 12")
	_check(game_state.get_karma_tier() == &"buono", "fascia buono")
	_check(karma_events == [12] and tier_events == [&"buono"], "segnali karma emessi")
	game_state.add_karma(-1000)
	_check(game_state.get_karma() == game_state.KARMA_MIN, "karma limitato al minimo")

	# --- Statistiche ---
	# Nota: le lambda catturano le variabili locali per valore, quindi per contare
	# gli eventi si usa un Array (passato per riferimento) invece di un int.
	var stat_events: Array[String] = []
	game_state.stats_changed.connect(func(id: String, _value: int, _delta: int) -> void: stat_events.append(id))
	game_state.add_stat("carisma", 2)
	_check(game_state.get_stat("carisma") == 3, "carisma = 3")
	_check(game_state.has_stat_at_least("carisma", 3), "requisito carisma >= 3")
	_check(stat_events == ["carisma"], "segnale stats_changed emesso")

	# --- Inventario ---
	game_state.add_item("chiave_antica")
	game_state.add_item("moneta", 5)
	_check(game_state.has_item("moneta", 5), "5 monete")
	_check(not game_state.remove_item("moneta", 10), "rimozione oltre la quantità rifiutata")
	_check(game_state.remove_item("moneta", 2) and game_state.get_item_quantity("moneta") == 3, "3 monete dopo rimozione")

	# --- Flag e posizione ---
	game_state.set_flag("incontrato_oste")
	_check(game_state.has_flag("incontrato_oste"), "flag impostato")
	game_state.set_current_location("spiaggia")

	# --- Salvataggio / caricamento ---
	_check(save_manager.save_game(), "salvataggio scritto")
	game_state.reset()
	_check(game_state.get_item_quantity("moneta") == 0, "reset svuota l'inventario")
	_check(save_manager.load_game(), "salvataggio caricato")
	_check(game_state.get_karma() == game_state.KARMA_MIN, "karma ripristinato")
	_check(game_state.get_stat("carisma") == 3, "statistiche ripristinate")
	_check(game_state.get_item_quantity("moneta") == 3 and game_state.has_item("chiave_antica"), "inventario ripristinato")
	_check(game_state.has_flag("incontrato_oste"), "flag ripristinati")
	_check(game_state.current_location_id == "spiaggia", "posizione ripristinata")
	_check(save_manager.peek_save_info().get("location_id", "") == "spiaggia", "peek_save_info")
	save_manager.delete_save()
	_check(not save_manager.has_save(), "salvataggio di test eliminato")

	# --- SceneManager: percorsi e overlay ---
	_check(scene_manager.get_dialogue_path("spiaggia") == "res://data/dialogues/spiaggia.json", "percorso dialogo per location")
	_check(not scene_manager.has_open_overlay(), "nessun overlay aperto")

	game_state.reset()
	_test_effects_and_requirements(game_state)
	game_state.reset()
	_test_all_dialogues_valid()
	_test_validator()
	_test_dialogue_runner(game_state)
	game_state.reset()
	_test_effects_once(game_state)
	game_state.reset()
	await _test_dialogue_scene(game_state)
	game_state.reset()
	await _test_map_scene(game_state)
	game_state.reset()
	await _test_save_slots_and_menu(game_state, save_manager)
	game_state.reset()
	await _test_save_robustness(game_state, save_manager)
	game_state.reset()
	await _test_navigation(game_state)
	game_state.reset()
	save_manager.save_path = save_manager.DEFAULT_SAVE_PATH

	print("SMOKE TEST: %s (%d fallimenti)" % ["OK" if _failures == 0 else "FALLITO", _failures])
	get_tree().quit(1 if _failures > 0 else 0)


func _test_effects_and_requirements(game_state: Node) -> void:
	game_state.apply_effects({"karma": 4, "stats": {"forza": 2}, "items": {"moneta": 3}, "flags": ["porta"]})
	_check(game_state.get_karma() == 4 and game_state.get_stat("forza") == 3, "apply_effects: karma e stat")
	_check(game_state.get_item_quantity("moneta") == 3 and game_state.has_flag("porta"), "apply_effects: oggetti e flag")
	game_state.apply_effects({"items": {"moneta": -2}, "flags": {"porta": false}})
	_check(game_state.get_item_quantity("moneta") == 1 and not game_state.has_flag("porta"), "apply_effects: rimozioni")
	_check(game_state.meets_requirements({"stats": {"forza": 3}, "items": {"moneta": 1}}), "requisiti soddisfatti")
	_check(not game_state.meets_requirements({"stats": {"forza": 4}}), "requisito stat non soddisfatto")
	_check(game_state.meets_requirements({"flags": {"porta": false}, "karma_tier": "neutro"}), "requisiti flag negato e fascia")
	_check(not game_state.meets_requirements({"karma": {"min": 5}}), "requisito karma minimo")
	var description: String = game_state.describe_requirements({"stats": {"carisma": 3}, "items": {"moneta": 3}})
	_check(description == "Carisma 3, Moneta x3", "descrizione requisiti ('%s')" % description)


func _test_all_dialogues_valid() -> void:
	var dir: DirAccess = DirAccess.open("res://data/dialogues")
	_check(dir != null, "cartella dialoghi presente")
	if dir == null:
		return
	for file_name: String in dir.get_files():
		if file_name.get_extension() != "json":
			continue
		var runner: DialogueRunner = DialogueRunner.new()
		var loaded: bool = runner.load_dialogue("res://data/dialogues/".path_join(file_name))
		var issues: PackedStringArray = runner.validate() if loaded else PackedStringArray(["non caricato"])
		_check(issues.is_empty(), "dialogo %s valido %s" % [file_name, issues])
		var missing: PackedStringArray = runner.find_missing_assets() if loaded else PackedStringArray()
		if not missing.is_empty():
			print("  [info] %s: immagini ancora da fornire (per ora segnaposto): %s" % [file_name, ", ".join(missing)])
		runner.free()


## Validatore: un dialogo corretto non dà problemi, uno pieno di errori li segnala tutti.
## (Il dialogo sbagliato stampa i suoi problemi come WARNING: è voluto.)
func _test_validator() -> void:
	var valid: Dictionary = {
		"id": "valido", "start": "a",
		"characters": {"lia": {"name": "Lia", "default_expression": "default", "expressions": {"default": "res://assets/characters/lia/lia.webp"}}},
		"nodes": {
			"a": {"background": "#202020", "characters": {"left": {"id": "lia", "expression": "default"}, "right": "lia", "center": null},
				"effects": {"karma": 2, "stats": {"forza": 1}, "items": {"moneta": 1}, "flags": ["visto"]}, "text": "Ciao.", "next": "b"},
			"b": {"background": {"image": "res://assets/backgrounds/spiaggia.webp", "color": "black"}, "text": "Scegli.",
				"choices": [{"text": "Vai", "next": "@location:spiaggia", "requires": {"karma": {"min": 1, "axis": "main"}, "karma_tier": ["neutro", "buono"], "items": ["moneta"], "flags": {"visto": true}}}],
				"branches": [{"requires": {"stats": {"forza": 2}}, "next": "@map"}]},
		},
	}
	var runner: DialogueRunner = DialogueRunner.new()
	runner.load_from_dict(valid, "valido")
	var issues: PackedStringArray = runner.validate()
	_check(issues.is_empty(), "validatore: dialogo corretto senza problemi %s" % [issues])
	_check(runner.find_missing_assets().is_empty(), "validatore: nessuna immagine mancante nel dialogo corretto")
	runner.free()

	var broken: Dictionary = {
		"id": "rotto", "start": "a",
		"characters": {"lia": {"name": "Lia", "default_expression": "triste", "expressions": {"default": "res://non/esiste.webp"}}},
		"nodes": {
			"a": {"background": "res://non/esiste_sfondo.webp", "characters": {"left": {"id": "lia", "expression": "arrabbiata"}},
				"effects": {"karma": {"altro_asse": 1}, "stats": {"magia": 1}, "items": {"spada": 1}, "flags": {"x": "si"}, "soldi": 3},
				"text": "...", "next": "@location:inesistente"},
			"b": {"background": "verdastro", "text": "...", "next": "a",
				"choices": [{"text": "C", "next": "a", "requires": {"karma": {"minimo": 1}, "karma_tier": "santo", "livello": 2}, "effects": {"stats": {"forza": "tanto"}}}],
				"branches": [{"requires": {"items": ["spada"]}, "next": "a"}]},
		},
	}
	runner = DialogueRunner.new()
	runner.load_from_dict(broken, "rotto")
	issues = runner.validate()
	var expected: Dictionary[String, String] = {
		"espressione di default 'triste'": "espressione di default mancante",
		"colore di sfondo non valido": "colore non valido",
		"espressione 'arrabbiata' non definita": "espressione del nodo mancante",
		"asse di karma 'altro_asse'": "asse di karma sconosciuto",
		"statistica 'magia'": "statistica sconosciuta",
		"oggetto 'spada' inesistente": "oggetto inesistente",
		"il flag 'x' deve valere true o false": "flag non booleano",
		"effetto sconosciuto 'soldi'": "effetto sconosciuto",
		"location 'inesistente'": "location di uscita inesistente",
		"chiave 'minimo' non valida in 'karma'": "chiave karma sbagliata",
		"fascia di karma 'santo'": "fascia sconosciuta",
		"requisito sconosciuto 'livello'": "requisito sconosciuto",
		"'stats.forza' deve essere un numero": "valore non numerico",
		"branch del nodo 'b': oggetto 'spada'": "requisiti dei branch controllati",
	}
	for fragment: String in expected:
		var found: bool = false
		for issue: String in issues:
			if issue.contains(fragment):
				found = true
				break
		_check(found, "validatore: segnala %s" % expected[fragment])
	var missing: PackedStringArray = runner.find_missing_assets()
	_check(missing.size() == 2 and missing.has("res://non/esiste.webp") and missing.has("res://non/esiste_sfondo.webp"), "validatore: elenca ritratti e sfondi mancanti come segnaposto %s" % [missing])
	_check(not ", ".join(issues).contains("non/esiste"), "validatore: le immagini mancanti non sono errori")
	runner.free()


## Effetti una volta sola: rigiocando un dialogo non si raccolgono di nuovo ricompense,
## una scelta diversa nello stesso nodo non dà altri effetti, "repeat" li ripete sempre,
## e la memoria degli effetti applicati passa dal salvataggio.
func _test_effects_once(game_state: Node) -> void:
	var data: Dictionary = {
		"id": "prova_once", "start": "dono",
		"nodes": {
			"dono": {"text": "Tieni.", "effects": {"items": {"moneta": 2}}, "next": "pozzo"},
			"pozzo": {"text": "Un pozzo.", "repeat": true, "effects": {"stats": {"forza": 1}}, "next": "scelta"},
			"scelta": {"text": "Allora?", "choices": [
				{"text": "Grazie", "effects": {"karma": 5}, "next": "@end"},
				{"text": "Dammene ancora", "effects": {"karma": -5, "items": {"moneta": 10}}, "next": "@end"},
			]},
		},
	}
	var forza_iniziale: int = game_state.get_stat("forza")
	for round: int in 2:
		var runner: DialogueRunner = DialogueRunner.new()
		runner.load_from_dict(data, "prova_once")
		_check(runner.validate().is_empty(), "una volta sola: dialogo di prova valido (giro %d)" % (round + 1))
		runner.start()
		runner.advance()
		runner.advance()
		runner.choose(round)  # primo giro "Grazie", secondo giro l'altra scelta
		runner.free()
	_check(game_state.get_item_quantity("moneta") == 2, "una volta sola: ricompensa del nodo data una volta (%d monete)" % game_state.get_item_quantity("moneta"))
	_check(game_state.get_karma() == 5, "una volta sola: conta solo la prima scelta del nodo (karma %d)" % game_state.get_karma())
	_check(game_state.get_stat("forza") == forza_iniziale + 2, "una volta sola: con repeat gli effetti si ripetono")
	_check(game_state.has_applied_effects("prova_once/dono") and game_state.has_applied_effects("prova_once/scelta#scelta"), "una volta sola: chiavi dialogo/nodo registrate")

	var saved: Dictionary = game_state.to_dict()
	game_state.reset()
	_check(not game_state.has_applied_effects("prova_once/dono"), "una volta sola: nuova partita azzera gli effetti applicati")
	game_state.from_dict(JSON.parse_string(JSON.stringify(saved)))
	_check(game_state.has_applied_effects("prova_once/dono"), "una volta sola: effetti applicati ripristinati dal salvataggio")
	var old_save: Dictionary = saved.duplicate()
	old_save.erase("applied_effects")
	game_state.from_dict(old_save)
	_check(not game_state.has_applied_effects("prova_once/dono") and game_state.get_item_quantity("moneta") == 2, "una volta sola: salvataggio senza il campo ancora caricabile")
	_check(not game_state.apply_effects_once("vuoto", {}) and not game_state.has_applied_effects("vuoto"), "una volta sola: un blocco vuoto non viene registrato")


## Percorre il dialogo della spiaggia scegliendo la strada "gentile" e controlla gli effetti.
func _test_dialogue_runner(game_state: Node) -> void:
	var runner: DialogueRunner = DialogueRunner.new()
	get_tree().root.add_child(runner)
	var events: Dictionary = {"lines": [], "choices": [], "finished": ""}
	runner.line_ready.connect(func(_id: String, _speaker: String, _color: Color, text: String) -> void: events["lines"].append(text))
	runner.choices_ready.connect(func(choices: Array[Dictionary]) -> void: events["choices"] = choices)
	runner.dialogue_finished.connect(func(exit_target: String) -> void: events["finished"] = exit_target)

	_check(runner.load_dialogue("res://data/dialogues/spiaggia.json"), "spiaggia caricata")
	runner.start()
	_check(runner.get_current_node_id() == "inizio" and runner.state == DialogueRunner.State.WAITING_ADVANCE, "runner: inizio in attesa")
	_check(game_state.has_flag("visitato_spiaggia"), "runner: effetti del nodo applicati")
	runner.advance()
	_check(runner.state == DialogueRunner.State.WAITING_CHOICE and events["choices"].size() == 4, "runner: 4 scelte dall'oste")
	_check(events["choices"][2]["available"] == false and events["choices"][2]["locked_reason"] == "Carisma 3", "runner: scelta carisma bloccata")
	runner.choose(2)
	_check(runner.get_current_node_id() == "oste_saluto", "runner: scelta bloccata ignorata")
	runner.choose(0)
	runner.advance()
	_check(runner.get_current_node_id() == "mirta_racconto", "runner: arrivo da Mirta")
	_check(events["choices"].size() == 3, "runner: scelta intelligenza nascosta (3 visibili)")
	runner.choose(0)
	_check(game_state.has_item("chiave_antica") and game_state.has_flag("loft_aperto"), "runner: chiave e flag ottenuti")
	_check(game_state.get_karma() == 10 and game_state.get_karma_tier() == &"buono", "runner: karma 10 (buono)")
	runner.advance()
	_check(runner.get_current_node_id() == "commiato_buono", "runner: branch per fascia di karma")
	runner.advance()
	runner.advance()
	_check(events["finished"] == "@map" and runner.state == DialogueRunner.State.FINISHED, "runner: fine con ritorno alla mappa")
	_check(game_state.current_dialogue_node == "", "runner: nodo corrente azzerato a fine dialogo")
	runner.queue_free()


## Istanzia la scena vera e simula due tocchi.
func _test_dialogue_scene(game_state: Node) -> void:
	var packed: PackedScene = load("res://scenes/dialogue/DialogueScene.tscn")
	_check(packed != null, "DialogueScene caricabile")
	if packed == null:
		return
	var scene: Control = packed.instantiate()
	scene.receive_params({"dialogue_path": "res://data/dialogues/spiaggia.json"})
	get_tree().root.add_child(scene)
	await get_tree().process_frame
	var text_label: RichTextLabel = scene.get_node(^"%TextLabel")
	var choices_box: VBoxContainer = scene.get_node(^"%ChoicesBox")
	var center_slot: CharacterSlot = scene.get_node(^"%CenterSlot")
	_check(not text_label.text.is_empty(), "scena: prima battuta mostrata")
	_check(center_slot.character_id == "oste", "scena: oste al centro")
	scene.call(&"_on_tap")  # completa la scrittura
	_check(is_equal_approx(text_label.visible_ratio, 1.0), "scena: tocco completa il testo")
	scene.call(&"_on_tap")  # avanza
	scene.call(&"_on_tap")  # completa la battuta dell'oste -> compaiono le scelte
	_check(choices_box.visible and choices_box.get_child_count() == 4, "scena: 4 pulsanti di scelta")
	var locked: Button = choices_box.get_child(2)
	_check(locked.disabled and locked.text.contains("Richiede: Carisma 3"), "scena: scelta bloccata disabilitata")
	(choices_box.get_child(0) as Button).pressed.emit()
	_check(game_state.get_karma() == 5, "scena: la scelta applica il karma")
	scene.queue_free()
	await get_tree().process_frame


func _check(condition: bool, label: String) -> void:
	if condition:
		print("  [ok] ", label)
	else:
		_failures += 1
		printerr("  [FALLITO] ", label)


## Mappa: zone presenti, ognuna con il suo dialogo, loft bloccato finché manca il flag.
func _test_map_scene(game_state: Node) -> void:
	var packed: PackedScene = load("res://scenes/map/MapScene.tscn")
	_check(packed != null, "MapScene caricabile")
	if packed == null:
		return
	var scene: Control = packed.instantiate()
	get_tree().root.add_child(scene)
	await get_tree().process_frame

	var zones: Dictionary = {}
	for zone: MapZone in scene.call(&"get_zones"):
		zones[zone.location_id] = zone
		_check(FileAccess.file_exists("res://data/dialogues/%s.json" % zone.location_id), "mappa: dialogo per la zona '%s'" % zone.location_id)
		var zone_issues: PackedStringArray = game_state.validate_requirements(zone.requires)
		_check(zone_issues.is_empty(), "mappa: requisiti validi per la zona '%s' %s" % [zone.location_id, zone_issues])
		# Nel test la MapScene non deve cambiare scena davvero: scollego il suo gestore.
		zone.zone_selected.disconnect(Callable(scene, &"_on_zone_selected"))
	_check(zones.size() == 5 and zones.has("viaggio_soverato") and zones.has("spiaggia") and zones.has("giardinetti") and zones.has("giardino_botanico") and zones.has("loft"), "mappa: 5 zone")
	if not zones.has("loft"):
		scene.queue_free()
		return

	var selected: Array[String] = []
	for zone: MapZone in zones.values():
		zone.zone_selected.connect(func(id: String) -> void: selected.append(id))

	var loft: MapZone = zones["loft"]
	_check(zones["spiaggia"].is_unlocked and not loft.is_unlocked, "mappa: spiaggia aperta, loft chiuso")
	loft.pressed.emit()
	var toast: Label = scene.get_node(^"%ToastLabel")
	_check(selected.is_empty() and toast.text.contains("chiuso a chiave"), "mappa: zona bloccata mostra il messaggio")

	game_state.set_flag("loft_aperto")
	_check(loft.is_unlocked, "mappa: il loft si sblocca col flag (senza ricaricare)")
	loft.pressed.emit()
	_check(selected == ["loft"], "mappa: zona sbloccata emette zone_selected")

	scene.queue_free()
	await get_tree().process_frame


## Slot "auto"/"manuale" e menu di gioco della mappa (Salva, Carica, Nuova partita).
func _test_save_slots_and_menu(game_state: Node, save_manager: Node) -> void:
	var auto: String = save_manager.SLOT_AUTO
	var manual: String = save_manager.SLOT_MANUAL
	_check(save_manager.get_slot_path(manual) == "user://smoke_test_save_manuale.json", "slot: percorso dello slot manuale")
	_check(not save_manager.autosave() and not save_manager.has_save(auto), "slot: salvataggio automatico disattivato non scrive")
	_check(not str(save_manager.format_saved_at("2026-11-21T09:31:00")).is_empty(), "slot: data del salvataggio leggibile")

	save_manager.autosave_enabled = true
	game_state.add_karma(5)
	_check(save_manager.save_game(manual), "slot: salvataggio manuale scritto")
	game_state.add_karma(20)
	_check(save_manager.autosave() and save_manager.has_save(auto), "slot: salvataggio automatico scritto")
	_check(save_manager.load_game(manual) and game_state.get_karma() == 5, "slot: caricamento manuale indipendente dall'automatico")

	var packed: PackedScene = load("res://scenes/map/MapScene.tscn")
	var map: Control = packed.instantiate()
	get_tree().root.add_child(map)
	await get_tree().process_frame
	var sm: Node = get_tree().root.get_node(^"/root/SceneManager")
	var toast: Label = map.get_node(^"%ToastLabel")

	# Salva: scrive lo slot manuale, chiude il menu e mostra il messaggio.
	var menu: Node = map.call(&"open_game_menu")
	_check(menu != null and get_tree().paused, "menu: aperto con il gioco in pausa")
	if menu == null:
		map.queue_free()
		return
	var info: Label = menu.get_node(^"%InfoLabel")
	_check(info.text.begins_with("Salvataggio manuale:") and not (menu.get_node(^"%LoadButton") as Button).disabled, "menu: mostra la data del salvataggio manuale")
	game_state.set_flag("prima_del_salva")
	(menu.get_node(^"%SaveButton") as Button).pressed.emit()
	_check(not sm.has_open_overlay() and not get_tree().paused and toast.text == "Partita salvata.", "menu: Salva chiude il menu e avvisa")

	# Nuova partita: con conferma, azzera lo stato e aggiorna lo slot automatico.
	menu = map.call(&"open_game_menu")
	(menu.get_node(^"%NewGameButton") as Button).pressed.emit()
	var confirm: Node = sm.get_overlay(sm.CONFIRM_OVERLAY_PATH)
	_check(confirm != null and game_state.has_flag("prima_del_salva"), "menu: Nuova partita chiede conferma e non azzera subito")
	if confirm != null:
		confirm.emit_signal(&"confirmed")
	_check(not game_state.has_flag("prima_del_salva") and game_state.get_karma() == 0 and not sm.has_open_overlay() and not get_tree().paused, "menu: Nuova partita azzera lo stato")
	game_state.set_flag("dopo_nuova_partita")
	save_manager.load_game(auto)
	_check(not game_state.has_flag("dopo_nuova_partita") and game_state.get_karma() == 0, "menu: Nuova partita aggiorna lo slot automatico")

	# Carica: con conferma, torna allo slot manuale e aggiorna lo slot automatico.
	menu = map.call(&"open_game_menu")
	(menu.get_node(^"%LoadButton") as Button).pressed.emit()
	confirm = sm.get_overlay(sm.CONFIRM_OVERLAY_PATH)
	if confirm != null:
		confirm.emit_signal(&"confirmed")
	_check(game_state.has_flag("prima_del_salva") and game_state.get_karma() == 5 and not sm.has_open_overlay() and toast.text == "Salvataggio caricato.", "menu: Carica ripristina il salvataggio manuale")
	game_state.reset()
	save_manager.load_game(auto)
	_check(game_state.has_flag("prima_del_salva"), "menu: Carica aggiorna lo slot automatico")

	save_manager.autosave_enabled = false
	save_manager.delete_save(auto)
	save_manager.delete_save(manual)
	map.queue_free()
	await get_tree().process_frame


## Salvataggi robusti: conversione dei formati vecchi, rifiuto delle versioni più recenti,
## copia di sicurezza .bak, file illeggibili conservati e avviso sulla mappa.
## (Produce due righe ERROR "caricamento fallito" e alcuni WARNING: sono voluti.)
func _test_save_robustness(game_state: Node, save_manager: Node) -> void:
	var path: String = save_manager.get_slot_path(save_manager.SLOT_AUTO)
	var backup: String = path + save_manager.BACKUP_SUFFIX
	var unreadable: String = path + save_manager.UNREADABLE_SUFFIX

	# Versioni e conversione.
	var old_data: Dictionary = {"version": 1, "karma": {"main": 3}, "flags": {"vecchio": true}}
	var migrated: Dictionary = game_state.migrate_save_data(old_data)
	_check(migrated.get("version") == game_state.SAVE_FORMAT_VERSION and migrated.get("applied_effects") == [] and not old_data.has("applied_effects"), "salvataggi: conversione dalla versione 1 (senza toccare l'originale)")
	_check(game_state.get_save_version({}) == 1, "salvataggi: senza 'version' vale come versione 1")
	_check(game_state.from_dict(old_data) and game_state.get_karma() == 3 and game_state.has_flag("vecchio"), "salvataggi: un salvataggio della versione 1 si carica")
	_check(not game_state.from_dict({"version": 99, "karma": {"main": 50}}) and game_state.get_karma() == 3, "salvataggi: versione più recente rifiutata, stato invariato")

	# Copia di sicurezza: il secondo salvataggio conserva il primo in .bak.
	save_manager.delete_save()
	DirAccess.remove_absolute(unreadable)
	game_state.reset()
	game_state.add_karma(1)
	save_manager.save_game()
	_check(not FileAccess.file_exists(backup), "salvataggi: nessuna copia al primo salvataggio")
	game_state.add_karma(1)
	save_manager.save_game()
	_check(FileAccess.file_exists(backup), "salvataggi: copia .bak creata al salvataggio successivo")

	# File principale danneggiato: si carica la copia, il file rotto viene conservato.
	_write_text(path, "{ rotto")
	var loads: Array[bool] = []
	var on_loaded: Callable = func(_p: String, from_backup: bool) -> void: loads.append(from_backup)
	save_manager.game_loaded.connect(on_loaded)
	game_state.reset()
	_check(save_manager.load_game() and game_state.get_karma() == 1 and loads == [true], "salvataggi: file danneggiato, caricata la copia .bak")
	_check(FileAccess.get_file_as_string(unreadable) == "{ rotto", "salvataggi: file danneggiato conservato in .illeggibile")
	_check(save_manager.peek_save_info().has("saved_at"), "salvataggi: peek usa la copia se il file è danneggiato")
	save_manager.game_loaded.disconnect(on_loaded)

	# Salvare sopra un file danneggiato non rovina la copia buona.
	game_state.add_karma(5)
	save_manager.save_game()
	_write_text(path, "{ rotto di nuovo")
	game_state.reset()
	_check(save_manager.load_game() and game_state.get_karma() == 1, "salvataggi: la copia buona non viene sostituita da un file danneggiato")

	# Tutto illeggibile: caricamento rifiutato, stato invariato.
	_write_text(backup, "nemmeno questo")
	game_state.set_flag("in_corso")
	_check(not save_manager.load_game() and game_state.has_flag("in_corso"), "salvataggi: file e copia illeggibili, stato invariato")

	# Salvataggio di una versione più recente del gioco: non caricato e conservato.
	DirAccess.remove_absolute(backup)
	_write_text(path, JSON.stringify({"version": 99, "karma": {"main": 50}}))
	_check(not save_manager.load_game() and game_state.get_karma() == 1, "salvataggi: versione più recente non caricata")
	_check(FileAccess.get_file_as_string(unreadable).contains("99"), "salvataggi: versione più recente conservata in .illeggibile")
	_check(save_manager.peek_save_info().is_empty(), "salvataggi: il menu non propone un salvataggio non caricabile")

	# Avviso sulla mappa e cancellazione completa.
	save_manager.set(&"_startup_notice", save_manager.NOTICE_RESTORED)
	var map: Control = (load("res://scenes/map/MapScene.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(map)
	await get_tree().process_frame
	_check((map.get_node(^"%ToastLabel") as Label).text == save_manager.NOTICE_RESTORED and save_manager.take_startup_notice().is_empty(), "salvataggi: avviso di ripresa mostrato una volta sulla mappa")
	map.queue_free()
	await get_tree().process_frame

	game_state.add_karma(1)
	save_manager.save_game()
	save_manager.save_game()
	save_manager.delete_save()
	_check(not FileAccess.file_exists(path) and not FileAccess.file_exists(backup) and not save_manager.has_save(), "salvataggi: delete_save elimina anche la copia .bak")
	DirAccess.remove_absolute(unreadable)


func _write_text(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Navigazione: richieste in coda, ripiego sulla mappa, errore con uscita, tasto indietro.
## Gira per ultima perché sostituisce davvero la scena corrente.
func _test_navigation(game_state: Node) -> void:
	var sm: Node = get_tree().root.get_node(^"/root/SceneManager")
	# Questo nodo di test non deve essere la "scena corrente", altrimenti verrebbe liberato.
	get_tree().current_scene = null

	# 1. Richiesta durante una transizione: messa in coda, non scartata.
	sm.go_to_map()
	sm.go_to_location("giardino_botanico")
	_check(await _wait_for_scene(sm, sm.DIALOGUE_SCENE_PATH), "navigazione: richiesta in coda eseguita dopo la transizione")
	_check(game_state.current_location_id == "giardino_botanico", "navigazione: location aggiornata")

	# 2. Dialogo che finisce subito (durante la dissolvenza): si arriva comunque alla mappa.
	var immediate: String = _write_temp_dialogue("fine_immediata", {"id": "t", "start": "a", "nodes": {"a": {"next": "@map"}}})
	sm.change_scene(sm.DIALOGUE_SCENE_PATH, {"dialogue_path": immediate})
	_check(await _wait_for_scene(sm, sm.MAP_SCENE_PATH), "navigazione: dialogo che finisce subito riporta alla mappa")

	# 3. Uscita verso una location inesistente: ripiego sulla mappa.
	var broken: String = _write_temp_dialogue("location_rotta", {"id": "t", "start": "a", "nodes": {"a": {"text": "Vado.", "next": "@location:inesistente"}}})
	sm.change_scene(sm.DIALOGUE_SCENE_PATH, {"dialogue_path": broken})
	await _wait_for_scene(sm, sm.DIALOGUE_SCENE_PATH)
	get_tree().current_scene.call(&"_on_tap")
	get_tree().current_scene.call(&"_on_tap")
	_check(await _wait_for_scene(sm, sm.MAP_SCENE_PATH), "navigazione: location inesistente riporta alla mappa")

	# 4. Dialogo che non si carica: schermata d'errore con pulsante di uscita.
	sm.change_scene(sm.DIALOGUE_SCENE_PATH, {"dialogue_path": "user://non_esiste.json"})
	await _wait_for_scene(sm, sm.DIALOGUE_SCENE_PATH)
	var choices: VBoxContainer = get_tree().current_scene.get_node(^"%ChoicesBox")
	var exit_button: Button = choices.get_child(0) as Button if choices.get_child_count() == 1 else null
	_check(exit_button != null and exit_button.text == "Torna alla mappa", "errore di caricamento: pulsante di uscita presente")
	if exit_button != null:
		exit_button.pressed.emit()
	_check(await _wait_for_scene(sm, sm.MAP_SCENE_PATH), "errore di caricamento: il pulsante riporta alla mappa")

	# 5. Indietro sulla mappa: conferma modale con gioco in pausa; un secondo indietro la chiude.
	sm.call(&"_handle_back")
	_check(sm.get_overlay(sm.CONFIRM_OVERLAY_PATH) != null and get_tree().paused, "indietro sulla mappa: conferma aperta e gioco in pausa")
	sm.call(&"_handle_back")
	_check(not sm.has_open_overlay() and not get_tree().paused, "indietro di nuovo: conferma chiusa e pausa tolta")

	# 6. Indietro in un dialogo: confermando si torna alla mappa.
	sm.go_to_location("giardino_botanico")
	await _wait_for_scene(sm, sm.DIALOGUE_SCENE_PATH)
	sm.call(&"_handle_back")
	var confirm: Node = sm.get_overlay(sm.CONFIRM_OVERLAY_PATH)
	_check(confirm != null and get_tree().paused, "indietro nel dialogo: conferma aperta")
	if confirm != null:
		confirm.emit_signal(&"confirmed")
	_check(await _wait_for_scene(sm, sm.MAP_SCENE_PATH) and not get_tree().paused, "conferma: ritorno alla mappa senza pausa residua")

	# 7. Ritorno sulla mappa = salvataggio automatico (slot "auto").
	var save_manager: Node = get_tree().root.get_node(^"/root/SaveManager")
	save_manager.delete_save(save_manager.SLOT_AUTO)
	save_manager.autosave_enabled = true
	game_state.set_flag("prova_autosave")
	sm.go_to_location("giardino_botanico")
	await _wait_for_scene(sm, sm.DIALOGUE_SCENE_PATH)
	_check(not save_manager.has_save(save_manager.SLOT_AUTO), "salvataggio automatico: nessun salvataggio durante il dialogo")
	sm.go_to_map()
	_check(await _wait_for_scene(sm, sm.MAP_SCENE_PATH) and save_manager.has_save(save_manager.SLOT_AUTO), "salvataggio automatico: scritto al ritorno sulla mappa")
	save_manager.autosave_enabled = false
	save_manager.delete_save(save_manager.SLOT_AUTO)

	DirAccess.remove_absolute(immediate)
	DirAccess.remove_absolute(broken)
	if get_tree().current_scene != null:
		get_tree().current_scene.queue_free()
	await get_tree().process_frame


## Attende che la scena corrente sia [param scene_path] e che non ci siano transizioni in corso.
func _wait_for_scene(sm: Node, scene_path: String, timeout: float = 5.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var current: Node = get_tree().current_scene
		if current != null and current.scene_file_path == scene_path and not sm.is_transitioning:
			return true
		await get_tree().process_frame
	return false


## Scrive un dialogo di prova in user:// (fuori dal progetto) e ne restituisce il percorso.
func _write_temp_dialogue(file_name: String, data: Dictionary) -> String:
	var path: String = "user://test_%s.json" % file_name
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	return path
