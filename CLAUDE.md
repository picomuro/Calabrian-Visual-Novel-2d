# CLAUDE.md — contesto del progetto

Visual novel 2D in **Godot 4.7.2 (build mono, ma il codice è solo GDScript)**, destinata ad **Android e iOS**, in orientamento orizzontale.
Repo privata: https://github.com/picomuro/Calabrian-Visual-Novel-2d (branch `main`).
L'utente scrive in italiano: rispondi in italiano.

## Regole di lavoro (richieste dall'utente)
- Procedi **un passo alla volta** e fermati dopo ogni step con un riassunto. Se l'utente chiede un'analisi o una review, **non modificare i file** finché non approva.
- Codice tipizzato, **commenti in italiano**, comunicazione tramite **segnali** e non con riferimenti diretti ai nodi. Layout fatti con Control/Container e anchor.
- Crea i file come testo (.gd/.tscn/.tres/.json/.dch/.dtl). **Niente binari scaricati**; gli asset mancanti si sostituiscono con placeholder (gradienti, ColorRect).
- **Non aggiungere plugin** senza chiedere. Dialogic è già stato approvato.
- Godot **non è nel PATH**. Eseguibile: `C:\Users\picon\Downloads\Godot_v4.7.2-stable_mono_win64\Godot_v4.7.2-stable_mono_win64_console.exe`.

## Verifica
- Smoke test (scena, non `--script`, altrimenti gli autoload non esistono):
  `"<godot>" --headless --path . res://tests/smoke_test.tscn`. Deve finire con esito OK. Due righe ERROR sono attese: vengono dai test di fallimento voluti.
- `--check-only` segnala falsi positivi "Identifier not found" sugli autoload: ignorali e verifica caricando a runtime.
- I lambda GDScript catturano le variabili locali per valore: per i contatori nei test usa un Array.

## Impostazioni (project.godot)
- Scena principale: `res://scenes/map/MapScene.tscn`.
- Viewport 1920x1080, finestra di prova 960x540, stretch `canvas_items`/`expand`, `orientation=4` (landscape con sensore).
- Renderer Mobile, `quit_on_go_back=false` (il tasto indietro lo gestisce SceneManager), tema `assets/ui/main_theme.tres` (font 44).
- Autoload: `GameState`, `SaveManager`, `SceneManager`, `Dialogic`.

## Architettura
| File | Ruolo |
|---|---|
| `autoload/GameState.gd` | Stato di gioco: karma per assi (`main`, da -100 a 100; fasce cattivo/neutro/buono con soglie ±10), stats (forza/carisma/intelligenza), inventario, flag, location corrente. Segnali `*_changed` più `state_changed`. Contiene `apply_effects(dict)`, `meets_requirements(dict)` (una chiave sconosciuta dà false e un warning), `describe_requirements`, `to_dict`/`from_dict` (versione 1). |
| `autoload/SaveManager.gd` | Salvataggio in `user://save.json` (scrive un file tmp e poi lo rinomina). Funzioni save/load/peek/delete/has. **Non c'è ancora una UI di salvataggio.** |
| `autoload/SceneManager.gd` | Cambio scena con fade e caricamento threaded. `go_to_location(id)` apre `data/dialogic/timelines/<id>.dtl` se esiste, altrimenti `data/dialogues/<id>.json`. Le navigazioni chieste durante una transizione vengono accodate. Se la navigazione fallisce emette `navigation_failed` e torna alla mappa. Overlay: `open_overlay(path, params, pause_game)` / `close_overlay`, `ask_confirmation(...)`. Il tasto indietro chiude l'overlay in cima; altrimenti chiede conferma per uscire (sulla mappa) o per tornare alla mappa (nel dialogo). |
| `scenes/map/MapScene` + `MapZone` | Mappa in AspectRatioContainer 16:9. Zone (TextureButton): Spiaggia, Giardinetti, GiardinoBotanico, Loft (bloccata finché non c'è il flag `loft_aperto`), ViaggioSoverato. Ogni zona ha `location_id`, `requires` e `locked_hint`. |
| `scenes/dialogue/DialogueRunner.gd` | Logica (senza UI) dei dialoghi JSON: macchina a stati, `validate()`, gli effetti di un nodo si applicano ogni volta che ci si entra. |
| `scenes/dialogue/DialogueScene` + `CharacterSlot` | UI dei dialoghi JSON: effetto macchina da scrivere, scelte a destra, slot sinistra/centro/destra con ritratti ridimensionati a contenimento. Se il dialogo ha un errore compare il pulsante "Torna alla mappa". |
| `scenes/dialogue/DialogicScene.gd` | Avvia una timeline Dialogic e alla fine torna alla mappa. In `_exit_tree` chiama `end_timeline(true)`: con `skip_ending` attivo non restano sfondi o ritratti sopra la mappa. |
| `scenes/dialogue/DialogicBootstrap.gd` | Ricostruisce a runtime gli elenchi di personaggi e timeline di Dialogic. Al primo import di un clone pulito l'editor li svuota; aprire il progetto due volte prima di esportare li ripristina anche in project.godot. |
| `scenes/ui/ConfirmOverlay`, `SafeAreaMargin.gd` | Finestra modale di conferma (segnali `confirmed` e `close_requested`); margini per la safe area dei telefoni. |
| `data/ItemData.gd`, `data/items/*.tres` | Oggetti: chiave_antica, moneta, medaglione. |
| `tests/smoke_test.*` | Copre stato, salvataggio, effetti, validità di tutti i dialoghi, scene e navigazione (inclusi i casi di soft-lock). |

Le scene ricevono i parametri con `receive_params(params)`, che SceneManager chiama prima di `_ready`. Gli overlay si chiudono emettendo `close_requested`.

## Formati dati
**Effetti / requisiti** (stesso formato per i dialoghi JSON e per le zone della mappa):
- `effects`: `{karma:{main:5}, stats:{forza:1}, items:{moneta:2}, flags:{loft_aperto:true}}`
- `requires`: `{stats, items, flags, karma:{min,max,axis}, karma_tier}`

**Dialogo JSON** (`data/dialogues/*.json`):
- Campi principali: `{id, start, characters:{id:{name,color,default_expression,expressions}}, nodes:{...}}`.
- Ogni nodo ha: `background`, `characters:{left|center|right: id o null}`, `clear_characters`, `speaker`, `text`, `effects`, `choices:[{text,next,effects,requires,hidden_if_locked}]`, `branches`, `next`.
- Uscite possibili: `@end`, `@map`, `@location:<id>`.

**Dialogic 2.0-alpha-20** (`addons/dialogic`, licenza MIT):
- Personaggi in `data/dialogic/characters/*.dch`: Tu → spirito.webp, Padre → padre.webp, Madre → lia.webp, Irina → irina.webp; scala 0.6.
- Timeline in `data/dialogic/timelines/*.dtl`.
- Stile `data/dialogic/styles/stile_gioco.tres`: font 36, textbox 1500x230, scelte spostate a destra.
- Sintassi delle timeline: `join Tu left`, `Padre: testo`, `- scelta` con i rami indentati con tab, `do GameState.add_karma(5)`, `[background arg="res://..." fade="1"]`, `leave --All--`.
- **Non usare `{}` nei testi**: in Dialogic le graffe indicano variabili.
- Per avanzare nel dialogo si usa l'azione `input/dialogic_default_action`.

## Contenuti
- Location JSON: spiaggia, giardinetti, loft, giardino_botanico (quest'ultima ha una sola riga placeholder). I testi sono ancora quelli vecchi (taverna/cripta/piazza): l'utente ha chiesto di lasciarli così per ora.
- Timeline Dialogic: `viaggio_soverato` (copione dell'utente: intro in auto e casa della nonna). Contiene un TODO per una riga tagliata nella foto.
- **Immagini protette da copyright** (fan art e foto di un attore): spirito, irina, padre. La repo deve **restare privata**; se diventa pubblica vanno rimosse dalla storia git.

## Da fare
**Step originali mancanti:**
- 4. Inventario e HUD (karma, stats) come overlay.
- 5. UI e flusso di salvataggio/caricamento.
- 6. README con: come aggiungere un dialogo, un oggetto, una zona; export Android (JDK, Android SDK, export templates); export iOS (Mac con Xcode); nota sul doppio import.

**Refactoring proposto (non ancora approvato, chiedi prima):**
- 4. Validatore più completo.
- 5. Salvataggio solo dalla mappa.
- 6. Salvataggi più robusti: versioning e migrazione.
- 7. Effetti "una volta sola": oggi gli effetti si riapplicano rivisitando un nodo e le ricompense si possono ripetere (farming).
- 8. Più test.
- 9. Scegliere un solo sistema di dialoghi (JSON o Dialogic).
- 10. Registro condiviso di personaggi e location (oggi i personaggi sono definiti due volte).
- 11. Pulizia.
