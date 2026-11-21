# CLAUDE.md — contesto del progetto

Visual novel 2D in **Godot 4.7.2 (build mono, ma il codice è solo GDScript)**, destinata ad **Android e iOS**, in orientamento orizzontale.
Repo privata: https://github.com/picomuro/Calabrian-Visual-Novel-2d (branch `main`).
L'utente scrive in italiano: rispondi in italiano.

## Regole di lavoro (richieste dall'utente)
- Procedi **un passo alla volta** e fermati dopo ogni step con un riassunto. Se l'utente chiede un'analisi o una review, **non modificare i file** finché non approva.
- Codice tipizzato, **commenti in italiano**, comunicazione tramite **segnali** e non con riferimenti diretti ai nodi. Layout fatti con Control/Container e anchor.
- Crea i file come testo (.gd/.tscn/.tres/.json). **Niente binari scaricati**; gli asset mancanti si sostituiscono con placeholder (gradienti, ColorRect).
- **Non aggiungere plugin** senza chiedere. Al momento il progetto non ne usa nessuno (Dialogic è stato rimosso: i dialoghi sono solo JSON).
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
- Autoload: `GameState`, `SaveManager`, `SceneManager`.

## Architettura
| File | Ruolo |
|---|---|
| `autoload/GameState.gd` | Stato di gioco: karma per assi (`main`, da -100 a 100; fasce cattivo/neutro/buono con soglie ±10), stats (forza/carisma/intelligenza), inventario, flag, location corrente. Segnali `*_changed` più `state_changed`. Contiene `apply_effects(dict)`, `meets_requirements(dict)` (una chiave sconosciuta dà false e un warning), `describe_requirements`, `to_dict`/`from_dict` (versione 1). |
| `autoload/SaveManager.gd` | Salvataggi JSON (scrive un file tmp e poi lo rinomina). Due slot: `auto` (`user://save.json`) e `manuale` (`user://save_manuale.json`); le funzioni save/load/peek/delete/has prendono lo slot (default `auto`). Salvataggio automatico a ogni ritorno sulla mappa (`SceneManager.scene_changed`) e quando l'app va in background sulla mappa; all'avvio riprende dallo slot `auto`. Si salva solo sulla mappa, mai a metà dialogo. `autosave_enabled = false` disattiva salvataggio automatico e ripresa (usato dai test). |
| `autoload/SceneManager.gd` | Cambio scena con fade e caricamento threaded. `go_to_location(id)` apre `data/dialogues/<id>.json` nella DialogueScene. Le navigazioni chieste durante una transizione vengono accodate. Se la navigazione fallisce emette `navigation_failed` e torna alla mappa. Overlay: `open_overlay(path, params, pause_game)` / `close_overlay`, `ask_confirmation(...)`. Il tasto indietro chiude l'overlay in cima; altrimenti chiede conferma per uscire (sulla mappa) o per tornare alla mappa (nel dialogo). |
| `scenes/map/MapScene` + `MapZone` | Mappa in AspectRatioContainer 16:9. Zone (TextureButton): Spiaggia, Giardinetti, GiardinoBotanico, Loft (bloccata finché non c'è il flag `loft_aperto`), ViaggioSoverato. Ogni zona ha `location_id`, `requires` e `locked_hint`. |
| `scenes/dialogue/DialogueRunner.gd` | Logica (senza UI) dei dialoghi JSON: macchina a stati, `validate()`, gli effetti di un nodo si applicano ogni volta che ci si entra. |
| `scenes/dialogue/DialogueScene` + `CharacterSlot` | UI dei dialoghi JSON: effetto macchina da scrivere, scelte a destra, slot sinistra/centro/destra con ritratti ridimensionati a contenimento. Se il dialogo ha un errore compare il pulsante "Torna alla mappa". |
| `scenes/ui/GameMenuOverlay` | Menu aperto dal pulsante "Menu" in alto a destra della mappa (in pausa): Salva (slot manuale), Carica e Nuova partita (con conferma; entrambe aggiornano subito lo slot `auto`). Comunica l'esito col segnale `notice`, che la mappa mostra nel toast. |
| `scenes/ui/ConfirmOverlay`, `SafeAreaMargin.gd` | Finestra modale di conferma (segnali `confirmed` e `close_requested`); margini per la safe area dei telefoni. |
| `data/ItemData.gd`, `data/items/*.tres` | Oggetti: chiave_antica, moneta, medaglione. |
| `tests/smoke_test.*` | Usa file di salvataggio propri e disattiva il salvataggio automatico, quindi non tocca i salvataggi veri. Copre stato, salvataggio (slot, menu, salvataggio automatico al ritorno sulla mappa), effetti, validità di tutti i dialoghi, scene e navigazione (inclusi i casi di soft-lock). |

Le scene ricevono i parametri con `receive_params(params)`, che SceneManager chiama prima di `_ready`. Gli overlay si chiudono emettendo `close_requested`.

## Formati dati
**Effetti / requisiti** (stesso formato per i dialoghi JSON e per le zone della mappa):
- `effects`: `{karma:{main:5}, stats:{forza:1}, items:{moneta:2}, flags:{loft_aperto:true}}`
- `requires`: `{stats, items, flags, karma:{min,max,axis}, karma_tier}`

**Dialogo JSON** (`data/dialogues/*.json`):
- Campi principali: `{id, start, characters:{id:{name,color,default_expression,expressions}}, nodes:{...}}`.
- Ogni nodo ha: `background` (`"#rrggbb"`, percorso immagine o `{image, color}`), `characters:{left|center|right: {id, expression} | "id" | null}`, `clear_characters`, `speaker`, `text`, `effects`, `choices:[{text,next,effects,requires,hidden_if_locked}]`, `branches`, `next`.
- Uscite possibili: `@end`, `@map`, `@location:<id>`.

**Note sul formato JSON:**
- Gli slot dei personaggi sono tre: `left`, `center`, `right`. Con più di tre personaggi in scena se ne nasconde uno (in `viaggio_soverato` Irina prende il posto di Madre nello slot destro, e Madre torna quando parla).
- Ogni personaggio ha le sue espressioni in `characters`; il ritratto di base si chiama `default`. Colori e immagini sono quelli dei vecchi `.dch`: Tu → spirito.webp, Padre → padre.webp, Madre → lia.webp, Irina → irina.webp.
- Il runner ignora i campi sconosciuti: per le note di lavoro usa un campo con prefisso `_` (es. `"_todo"`).
- Lo sfondo cambia di colpo, senza dissolvenza.
- I rami che riconvergono puntano allo stesso nodo (vedi `intro_silenzio` e `casa_nonna_01` in `viaggio_soverato.json`).

## Contenuti
- Location JSON: spiaggia, giardinetti, loft, giardino_botanico (quest'ultima ha una sola riga placeholder). I testi sono ancora quelli vecchi (taverna/cripta/piazza): l'utente ha chiesto di lasciarli così per ora.
- `viaggio_soverato.json` (copione dell'utente: intro in auto e casa della nonna), convertito dalla vecchia timeline Dialogic. Contiene un `_todo` sul nodo `valigie_chiedi_02` per una riga tagliata nella foto.
- **Immagini protette da copyright** (fan art e foto di un attore): spirito, irina, padre. La repo deve **restare privata**; se diventa pubblica vanno rimosse dalla storia git.

## Da fare
Stato verificato sul codice il 2026-11-21.

**Step originali mancanti:**
- 4. Inventario e HUD (karma, stats) come overlay. Non esiste ancora nessuna scena; `SceneManager.open_overlay` è già pronto per ospitarle.
- ~~5. UI e flusso di salvataggio/caricamento~~: fatto (salvataggio automatico + menu della mappa, vedi SaveManager e GameMenuOverlay).
- 6. README con: come aggiungere un dialogo, un oggetto, una zona; export Android (JDK, Android SDK, export templates); export iOS (Mac con Xcode). Il commento in testa a `DialogueRunner.gd` rimanda già al README, che non esiste.

**Refactoring proposto (non ancora approvato, chiedi prima):**
- 4. Validatore più completo. Oggi `validate()` controlla nodo iniziale, destinazioni, slot e id dei personaggi. Non controlla chiavi di `effects`/`requires`, espressioni, file di sfondo e ritratti, né se le `@location:<id>` esistono.
- ~~5. Salvataggio solo dalla mappa~~: fatto insieme allo step 5.
- 6. Salvataggi più robusti: versioning e migrazione. Oggi `from_dict` dà solo un warning se la versione è più recente e non migra; un file di salvataggio illeggibile all'avvio viene ignorato (errore nel log) e si parte da zero.
- 7. Effetti "una volta sola": oggi gli effetti si riapplicano rivisitando un nodo e le ricompense si possono ripetere (farming).
- 8. Più test.
- ~~9. Un solo sistema di dialoghi~~: fatto, Dialogic è stato rimosso.
- 10. Registro condiviso di personaggi e location (oggi ogni file JSON ridefinisce i propri personaggi).
- 11. Pulizia (es. i `.gitkeep` rimasti in cartelle non più vuote, `project/assembly_name="Madonna-s Quest"` nella sezione dotnet).
