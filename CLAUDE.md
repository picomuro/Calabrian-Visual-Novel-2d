# CLAUDE.md — contesto del progetto

Visual novel 2D in **Godot 4.7.2 (build mono, ma il codice è solo GDScript)**, destinata ad **Android e iOS**, in orientamento orizzontale.
Repo privata: https://github.com/picomuro/Calabrian-Visual-Novel-2d (branch `main`).
L'utente scrive in italiano: rispondi in italiano. Guida per chi scrive contenuti ed export: `README.md`.

## Regole di lavoro (richieste dall'utente)
- Procedi **un passo alla volta** e fermati dopo ogni step con un riassunto. Se l'utente chiede un'analisi o una review, **non modificare i file** finché non approva.
- Codice tipizzato, **commenti in italiano**, comunicazione tramite **segnali** e non con riferimenti diretti ai nodi. Layout fatti con Control/Container e anchor.
- Crea i file come testo (.gd/.tscn/.tres/.json). **Niente binari scaricati**; gli asset mancanti si sostituiscono con placeholder (gradienti, ColorRect).
- **Non aggiungere plugin** senza chiedere. Al momento il progetto non ne usa nessuno (Dialogic è stato rimosso: i dialoghi sono solo JSON).
- Godot **non è nel PATH**. Eseguibile: `C:\Users\picon\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`.

## Verifica
- Smoke test (scena, non `--script`, altrimenti gli autoload non esistono):
  `"<godot>" --headless --path . res://tests/smoke_test.tscn`. Deve finire con esito OK. Cinque righe ERROR sono attese, tutte da test di fallimento voluti: due "SaveManager: caricamento fallito", una "troppi nodi consecutivi senza testo" (ciclo), una "location:inesistente" e una "user://non_esiste.json". Sono attese anche le righe WARNING del dialogo `[rotto]` (test del validatore). Le righe `[info]` elencano le immagini citate dai dialoghi ma non ancora presenti: non sono errori.
- `--check-only` segnala falsi positivi "Identifier not found" sugli autoload: ignorali e verifica caricando a runtime.
- I lambda GDScript catturano le variabili locali per valore: per i contatori nei test usa un Array.
- Valori letti da JSON: non scrivere `valore == true` (con una stringa è un errore di runtime): usa `GameState.is_true(valore)`.
- Lo smoke test gioca anche ogni dialogo vero 40 volte con scelte casuali (seme fisso) e controlla che finisca sempre: se aggiungi un dialogo, viene incluso da solo.

## Impostazioni (project.godot)
- Scena principale: `res://scenes/map/MapScene.tscn`.
- Viewport 1920x1080, finestra di prova 960x540, stretch `canvas_items`/`expand`, `orientation=4` (landscape con sensore).
- Renderer Mobile, `quit_on_go_back=false` (il tasto indietro lo gestisce SceneManager), tema `assets/ui/main_theme.tres` (font 44).
- Autoload: `GameState`, `SaveManager`, `SceneManager`.
- Nessuna sezione `[dotnet]`: il codice è solo GDScript. Se l'editor mono la aggiunge di nuovo, si può togliere.

## Architettura
| File | Ruolo |
|---|---|
| `autoload/GameState.gd` | Stato di gioco: karma per assi (`main`, da -100 a 100; fasce cattivo/neutro/buono con soglie ±10), stats (forza/carisma/intelligenza), inventario, flag, location corrente. Segnali `*_changed` più `state_changed`. Contiene `apply_effects(dict)`, `apply_effects_once(key, dict)` (ricorda le chiavi già applicate in `applied_effects`, salvato e azzerato da `reset`), `meets_requirements(dict)` (una chiave sconosciuta dà false e un warning), `describe_requirements`, `to_dict`/`from_dict`. Formato del salvataggio alla versione 2: `migrate_save_data` converte i salvataggi vecchi un passo alla volta, e `from_dict` rifiuta (ritorna false) quelli di una versione più recente. Se cambi il formato, incrementa `SAVE_FORMAT_VERSION` e aggiungi il passo di conversione. |
| `autoload/SaveManager.gd` | Salvataggi JSON (scrive un file tmp e poi lo rinomina). Due slot: `auto` (`user://save.json`) e `manuale` (`user://save_manuale.json`); le funzioni save/load/peek/delete/has prendono lo slot (default `auto`). Salvataggio automatico a ogni ritorno sulla mappa (`SceneManager.scene_changed`) e quando l'app va in background sulla mappa; all'avvio riprende dallo slot `auto`. Si salva solo sulla mappa, mai a metà dialogo. `autosave_enabled = false` disattiva salvataggio automatico e ripresa (usato dai test). Prima di sovrascrivere copia il vecchio file in `<file>.bak`. Se il file non si legge (danneggiato o di versione più recente) carica la `.bak`; se nemmeno quella si legge, conserva il file in `<file>.illeggibile` e non lo sovrascrive. All'avvio l'esito (ripresa dalla copia o ripartenza da zero) è mostrato nel toast della mappa (`take_startup_notice`). |
| `autoload/SceneManager.gd` | Cambio scena con fade e caricamento threaded. `go_to_location(id)` apre `data/dialogues/<id>.json` nella DialogueScene. Le navigazioni chieste durante una transizione vengono accodate. Se la navigazione fallisce emette `navigation_failed` e torna alla mappa. Overlay: `open_overlay(path, params, pause_game)` / `close_overlay`, `ask_confirmation(...)`. Il tasto indietro chiude l'overlay in cima; altrimenti chiede conferma per uscire (sulla mappa) o per tornare alla mappa (nel dialogo). |
| `scenes/map/MapScene` + `MapZone` | Mappa in AspectRatioContainer 16:9. Zone (TextureButton): Spiaggia, Giardinetti, GiardinoBotanico, Loft (bloccata finché non c'è il flag `loft_aperto`), ViaggioSoverato. Ogni zona ha `location_id`, `requires` e `locked_hint`; il nome mostrato viene da `locations.json` (`display_name` solo per sostituirlo). |
| `scenes/dialogue/DialogueRunner.gd` | Logica (senza UI) dei dialoghi JSON: macchina a stati. Effetti di nodi e scelte una volta sola per partita (chiave `<id dialogo>/<nodo>` e `<id dialogo>/<nodo>#scelta`): rigiocando un dialogo non si raccolgono di nuovo ricompense e karma, e per le scelte conta la prima decisione presa in quel nodo. `"repeat": true` su nodo o scelta li fa applicare a ogni passaggio. `validate()` controlla destinazioni dei nodi, nodi irraggiungibili, nodi in cui ogni scelta ha requisiti (rischio di blocco), location di `@location:<id>`, slot, personaggi ed espressioni, formato degli sfondi, e `effects`/`requires` tramite `GameState.validate_effects`/`validate_requirements` (chiavi, stats, assi e fasce di karma, oggetti esistenti in `data/items`). `find_missing_assets()` elenca ritratti e sfondi citati ma assenti, che non sono errori: al loro posto si vede un segnaposto. |
| `scenes/dialogue/DialogueScene` + `CharacterSlot` | UI dei dialoghi JSON: effetto macchina da scrivere, scelte a destra, slot sinistra/centro/destra con ritratti ridimensionati a contenimento. Se il dialogo ha un errore compare il pulsante "Torna alla mappa". |
| `scenes/ui/Hud` | Barra in alto sulla mappa (istanziata in `MapScene`, nodo `%Hud`): karma con fascia colorata (lampeggia quando cambia) e statistiche a sinistra, pulsanti "Zaino (n)" e "Menu" a destra. Si aggiorna da `GameState.state_changed`; emette `inventory_requested` / `menu_requested`. Non c'è durante i dialoghi. Non è un overlay, perché il tasto indietro chiuderebbe anche lei. |
| `scenes/ui/InventoryOverlay` | Zaino (overlay in pausa): oggetti in ordine alfabetico con icona, nome, descrizione (da `ItemData`) e quantità; messaggio "Lo zaino è vuoto.". Un oggetto senza `.tres` viene mostrato con il suo id. |
| `scenes/ui/GameMenuOverlay` | Menu aperto dal pulsante "Menu" dell'HUD (in pausa): Salva (slot manuale), Carica e Nuova partita (con conferma; entrambe aggiornano subito lo slot `auto`). Comunica l'esito col segnale `notice`, che la mappa mostra nel toast. |
| `scenes/ui/ConfirmOverlay`, `SafeAreaMargin.gd` | Finestra modale di conferma (segnali `confirmed` e `close_requested`); margini per la safe area dei telefoni. |
| `data/GameRegistry.gd`, `data/characters.json`, `data/locations.json` | Registro condiviso (classe statica, legge i JSON una volta). `characters.json` contiene tutti i personaggi (`{"characters": {id: {name, color, default_expression, expressions}}}`), usabili da qualsiasi dialogo per id. `locations.json` contiene le location (`{"locations": {id: {name}}}`); ognuna deve avere `data/dialogues/<id>.json`. Le zone della mappa prendono il nome da qui. Le chiavi che iniziano con `_` sono note. |
| `data/ItemData.gd`, `data/items/*.tres` | Oggetti: chiave_antica, moneta, medaglione. |
| `tests/smoke_test.*` | Usa file di salvataggio propri e disattiva il salvataggio automatico, quindi non tocca i salvataggi veri. Copre stato, salvataggio (slot, menu, salvataggio automatico al ritorno sulla mappa), effetti, validità di tutti i dialoghi, scene e navigazione (inclusi i casi di soft-lock). |

Le scene ricevono i parametri con `receive_params(params)`, che SceneManager chiama prima di `_ready`. Gli overlay si chiudono emettendo `close_requested`.

## Formati dati
**Effetti / requisiti** (stesso formato per i dialoghi JSON e per le zone della mappa):
- `effects`: `{karma:{main:5}, stats:{forza:1}, items:{moneta:2}, flags:{loft_aperto:true}}`
- `requires`: `{stats, items, flags, karma:{min,max,axis}, karma_tier}`

**Dialogo JSON** (`data/dialogues/*.json`):
- Campi principali: `{id, start, characters?, nodes:{...}}`. `characters` è facoltativo: i personaggi stanno in `data/characters.json`. Qui si mettono solo quelli da aggiungere o ridefinire per questo dialogo, e la definizione locale vince.
- Ogni nodo ha: `background` (`"#rrggbb"`, percorso immagine o `{image, color}`), `characters:{left|center|right: {id, expression} | "id" | null}`, `clear_characters`, `speaker`, `text`, `effects`, `repeat`, `choices:[{text,next,effects,requires,hidden_if_locked,repeat}]`, `branches`, `next`.
- Uscite possibili: `@end`, `@map`, `@location:<id>`.

**Note sul formato JSON:**
- Gli slot dei personaggi sono tre: `left`, `center`, `right`. Con più di tre personaggi in scena se ne nasconde uno (in `viaggio_soverato` Irina prende il posto di Madre nello slot destro, e Madre torna quando parla).
- Ogni personaggio ha le sue espressioni in `data/characters.json`; per Tu, Padre, Madre e Irina il ritratto di base si chiama `default` (Tu → spirito.webp, Padre → padre.webp, Madre → lia.webp, Irina → irina.webp). Personaggi del registro: tu, padre, madre, irina, spirito, lia, capitano, oste, mirta.
- Nuova location: aggiungila a `data/locations.json`, crea `data/dialogues/<id>.json` e istanzia una `MapZone` nella mappa con lo stesso `location_id`.
- Il runner ignora i campi sconosciuti: per le note di lavoro usa un campo con prefisso `_` (es. `"_todo"`).
- Lo sfondo cambia di colpo, senza dissolvenza.
- I rami che riconvergono puntano allo stesso nodo (vedi `intro_silenzio` e `casa_nonna_01` in `viaggio_soverato.json`).

## Contenuti
- Location JSON: spiaggia, giardinetti, loft, giardino_botanico (quest'ultima ha una sola riga placeholder). Spiaggia, giardinetti, loft e giardino_botanico citano immagini non ancora presenti (oste, mirta, capitano e tre sfondi): lo smoke test le elenca nelle righe `[info]`. I testi sono ancora quelli vecchi (taverna/cripta/piazza): l'utente ha chiesto di lasciarli così per ora.
- `viaggio_soverato.json` (copione dell'utente: intro in auto e casa della nonna), convertito dalla vecchia timeline Dialogic. Contiene un `_todo` sul nodo `valigie_chiedi_02` per una riga tagliata nella foto.
- **Immagini protette da copyright** (fan art e foto di un attore): spirito, irina, padre. La repo deve **restare privata**; se diventa pubblica vanno rimosse dalla storia git.

## Da fare
Stato verificato sul codice il 2026-11-21.

**Step originali (tutti fatti):**
- ~~4. Inventario e HUD~~: fatto (`Hud` sulla mappa, `InventoryOverlay`). Possibile seguito: un avviso breve durante i dialoghi quando cambiano karma o oggetti, dato che lì l'HUD non c'è.
- ~~5. UI e flusso di salvataggio/caricamento~~: fatto (salvataggio automatico + menu della mappa, vedi SaveManager e GameMenuOverlay).
- ~~6. README~~: fatto (`README.md`: avvio, struttura, test, come aggiungere dialogo/personaggio/oggetto/zona, salvataggi, export Android e iOS secondo la documentazione di Godot 4.7). Se cambi un formato dati o un flusso, aggiorna anche il README.

**Refactoring proposto (tutti fatti):**
- ~~4. Validatore più completo~~: fatto. Controlla anche i `requires` delle zone della mappa (nello smoke test).
- ~~5. Salvataggio solo dalla mappa~~: fatto insieme allo step 5.
- ~~6. Salvataggi più robusti~~: fatto (versione 2, conversione, copia .bak, file illeggibili conservati).
- ~~7. Effetti "una volta sola"~~: fatto. I salvataggi della versione 1, senza `applied_effects`, si caricano come se nessun effetto fosse già stato dato.
- ~~8. Più test~~: fatto (limiti di GameState, casi limite del runner, partite simulate di tutti i dialoghi, overlay sovrapposti, uscita `@location`, sfondo della scena). Ha scovato un bug, ora corretto: un flag non booleano nei dati mandava in errore il caricamento.
- ~~9. Un solo sistema di dialoghi~~: fatto, Dialogic è stato rimosso.
- ~~10. Registro condiviso di personaggi e location~~: fatto (`GameRegistry`).
- ~~11. Pulizia~~: fatta. Tolti i `.gitkeep` dalle cartelle non vuote, la sezione `[dotnet]` di project.godot (niente C#) e `current_dialogue_node`, che non era mai letto. Il nome del progetto resta "Madonna's Quest": cambiarlo sposta la cartella `user://` e quindi i salvataggi, decide l'utente.
