# Calabrian Visual Novel 2D

Visual novel 2D in **Godot 4.7.2**, scritta solo in **GDScript**, per **Android e iOS** in orientamento orizzontale.

Il giocatore si muove su una **mappa** a zone. Ogni zona apre un **dialogo** scritto in JSON, con scelte che cambiano karma, statistiche, inventario e flag della storia. La partita si salva da sola ogni volta che si torna sulla mappa.

---

## Indice
1. [Avvio rapido](#avvio-rapido)
2. [Struttura del progetto](#struttura-del-progetto)
3. [Test](#test)
4. [Come aggiungere un dialogo](#come-aggiungere-un-dialogo)
5. [Come aggiungere un personaggio](#come-aggiungere-un-personaggio)
6. [Come aggiungere un oggetto](#come-aggiungere-un-oggetto)
7. [Come aggiungere una zona (location)](#come-aggiungere-una-zona-location)
8. [Salvataggi](#salvataggi)
9. [Export per Android](#export-per-android)
10. [Export per iOS](#export-per-ios)

---

## Avvio rapido

1. Scarica **Godot 4.7.2** da <https://godotengine.org/download>. Va bene sia la versione standard sia la .NET, perché il progetto non usa C#. Per l'export conviene la standard (vedi [Export per Android](#export-per-android)).
2. Apri Godot, poi **Importa** e seleziona `project.godot`.
3. Premi **F5**: parte dalla mappa (`scenes/map/MapScene.tscn`).

Per provare un dialogo da solo, apri `scenes/dialogue/DialogueScene.tscn`, scegli il file nella proprietà **Dialogue Path** e premi **F6**.

## Struttura del progetto

```
autoload/              servizi sempre attivi
  GameState.gd         karma, statistiche, inventario, flag, effetti e requisiti
  SaveManager.gd       salvataggi (automatico + manuale, copie di sicurezza)
  SceneManager.gd      cambi di scena con dissolvenza, finestre sopra il gioco, tasto indietro
data/
  characters.json      tutti i personaggi (nome, colore, ritratti)
  locations.json       tutte le location (nome)
  dialogues/<id>.json  un dialogo per location
  items/<id>.tres      un file per oggetto
  GameRegistry.gd      legge characters.json e locations.json
  ItemData.gd          definizione di un oggetto
scenes/
  map/                 mappa e zone cliccabili
  dialogue/            scena del dialogo, motore dei dialoghi (DialogueRunner), ritratti
  ui/                  menu di gioco, finestra di conferma, margini per notch e bordi
assets/                sfondi, personaggi, tema grafico
tests/                 smoke test
```

## Test

Lo smoke test controlla in pochi secondi stato, salvataggi, dialoghi, mappa e navigazione. Inoltre gioca ogni dialogo 40 volte con scelte casuali. Da PowerShell, nella cartella del progetto (sostituisci il percorso di Godot con il tuo):

```powershell
& "C:\percorso\Godot_v4.7.2-stable_win64_console.exe" --headless --path . res://tests/smoke_test.tscn
```

Deve finire con `SMOKE TEST: OK (0 fallimenti)`. Alcune righe `ERROR`/`WARNING` sono normali, perché vengono da test che provocano errori apposta. Le righe `[info]` elencano le immagini citate dai dialoghi che non ci sono ancora.

**Lancialo dopo ogni modifica ai dialoghi**: il validatore trova da solo nodi sbagliati, personaggi o oggetti inesistenti, effetti scritti male, nodi irraggiungibili e scelte che possono bloccare il giocatore.

---

## Come aggiungere un dialogo

Ogni location ha un dialogo in `data/dialogues/<id>.json`, dove `<id>` è l'id della location (vedi [Come aggiungere una zona](#come-aggiungere-una-zona-location)). Un dialogo è un insieme di **nodi**: ognuno mostra una battuta e porta al successivo, oppure propone delle scelte.

### Esempio minimo

```json
{
	"id": "porto",
	"start": "inizio",
	"nodes": {
		"inizio": {
			"background": {"image": "res://assets/backgrounds/porto.webp", "color": "#20304a"},
			"characters": {"left": "tu", "right": "padre"},
			"speaker": "padre",
			"text": "Siamo arrivati. Senti che odore di mare?",
			"next": "scelta"
		},
		"scelta": {
			"speaker": "tu",
			"text": "Cosa rispondi?",
			"choices": [
				{"text": "Bellissimo!", "effects": {"karma": 5}, "next": "fine"},
				{"text": "Puzza di pesce.", "effects": {"karma": -5}, "next": "fine"},
				{"text": "[Carisma 3] Fai una battuta", "requires": {"stats": {"carisma": 3}}, "effects": {"stats": {"carisma": 1}}, "next": "fine"}
			]
		},
		"fine": {
			"speaker": "padre",
			"text": "Andiamo, che la nonna ci aspetta.",
			"next": "@map"
		}
	}
}
```

### Campi di un nodo

| Campo | Cosa fa |
|---|---|
| `text` | La battuta. Ammette BBCode, per esempio `[b]grassetto[/b]` o `[i]corsivo[/i]`. |
| `speaker` | Chi parla: l'id di un personaggio (es. `"padre"`), un nome libero (es. `"Voce lontana"`) oppure niente per il narratore. |
| `characters` | Chi è in scena negli slot `left`, `center` e `right`. Si scrive `"tu"`, oppure `{"id": "tu", "expression": "default"}`, oppure `null` per togliere il personaggio. |
| `clear_characters` | `true` toglie tutti i personaggi prima di mostrare quelli del nodo. |
| `background` | Colore (`"#20304a"` o `"black"`), immagine (`"res://..."`) oppure `{"image": ..., "color": ...}`. Se l'immagine non esiste ancora, si vede il colore. |
| `next` | Nodo successivo, oppure un'uscita: `@map` (torna alla mappa), `@end` (fine) o `@location:<id>` (va a un'altra location). |
| `choices` | Elenco di scelte, ognuna con `text` e `next`, più facoltativi `effects`, `requires`, `hidden_if_locked` e `repeat`. |
| `effects` | Cambiamenti allo stato applicati all'ingresso nel nodo (vedi sotto). |
| `branches` | Deviazioni automatiche: `[{"requires": {...}, "next": "..."}]`. Vince il primo branch con i requisiti soddisfatti; se nessuno lo è, si segue `next`. |
| `repeat` | `true` = gli effetti si applicano a ogni passaggio (vedi sotto). |
| `_qualcosa` | I campi che iniziano con `_` (es. `"_todo"`) sono note per chi scrive e vengono ignorati. |

### Effetti e requisiti

Effetti e requisiti usano lo stesso formato nei dialoghi e nelle zone della mappa.

```json
"effects": {
	"karma": 5,
	"stats": {"forza": 1},
	"items": {"moneta": 3, "chiave_antica": -1},
	"flags": {"loft_aperto": true}
}

"requires": {
	"stats": {"carisma": 3},
	"items": ["chiave_antica"],
	"flags": {"loft_aperto": true, "spirito_adirato": false},
	"karma": {"min": 10},
	"karma_tier": "buono"
}
```

- **Effetti:**
  - `items` con un numero positivo aggiunge pezzi, con un numero negativo li toglie;
  - `flags` con `false` toglie il flag.
- **Statistiche** (`stats`): `forza`, `carisma`, `intelligenza`. All'inizio della partita valgono 1.
- **Fasce di karma** (`karma_tier`): `cattivo` (karma −10 o meno), `neutro` e `buono` (karma +10 o più). Il karma va da −100 a +100.
- **Scelte con requisiti:** una scelta con `requires` non soddisfatti appare disattivata con la scritta "Richiede: …". Con `"hidden_if_locked": true` invece non compare proprio.
- **Scelte sempre disponibili:** ogni nodo con scelte deve averne almeno una senza `requires`, altrimenti il giocatore potrebbe restare bloccato. Il validatore lo segnala.

### Effetti una volta sola

Gli effetti valgono **una volta per partita**, così rigiocando un dialogo non si raccolgono di nuovo monete e karma. Per le scelte conta la **prima decisione** presa in quel nodo. Per effetti che devono ripetersi, come un negozio, aggiungi `"repeat": true` al nodo o alla scelta.

### Personaggi in un dialogo

I personaggi si prendono da `data/characters.json` usando il loro id: `tu`, `padre`, `madre`, `irina`, `spirito`, `lia`, `capitano`, `oste`, `mirta`. Un dialogo può definire un personaggio che compare solo lì, oppure ridefinirne uno solo per sé, nel campo `"characters"` in cima al file (stesso formato di `characters.json`).

## Come aggiungere un personaggio

1. Metti le immagini in `assets/characters/<id>/`. Vanno bene PNG o WebP con sfondo trasparente, ritagliate attorno alla figura.
2. Aggiungi il personaggio in `data/characters.json`:

```json
"nonna": {
	"name": "Nonna Teresa",
	"color": "#c98a5a",
	"default_expression": "default",
	"expressions": {
		"default": "res://assets/characters/nonna/nonna.webp",
		"arrabbiata": "res://assets/characters/nonna/arrabbiata.webp"
	}
}
```

- `color` è il colore del nome nel riquadro del testo.
- Si possono indicare immagini che ancora non esistono: al loro posto si vede un riquadro con il nome, e lo smoke test le elenca come "immagini ancora da fornire".

## Come aggiungere un oggetto

1. In Godot, nel pannello FileSystem, fai clic destro su `data/items/` e scegli **Nuovo → Risorsa…** di tipo **ItemData**. Salvala come `data/items/<id>.tres`. In alternativa duplica `moneta.tres` e modificala.
2. Compila i campi:
   - `id`: uguale al nome del file, es. `ciambella`;
   - `display_name`: il nome mostrato, es. `Ciambella della nonna`;
   - `description`: la descrizione per l'inventario;
   - `icon`: l'immagine dell'oggetto; per ora va bene un segnaposto.
3. Da quel momento l'oggetto si può usare in effetti e requisiti: `"items": {"ciambella": 1}`. Il validatore segnala gli id che non hanno il loro file.

## Come aggiungere una zona (location)

Una location richiede tre cose, tutte con lo **stesso id** (es. `porto`):

1. **Una riga** in `data/locations.json`:

```json
"porto": {"name": "Porto"}
```

2. **Il dialogo** `data/dialogues/porto.json` (vedi [Come aggiungere un dialogo](#come-aggiungere-un-dialogo)).
3. **La zona sulla mappa.** Apri `scenes/map/MapScene.tscn`, trascina `scenes/map/MapZone.tscn` dentro il nodo `MapFrame` e nell'Inspector imposta:
   - **Location Id**: `porto`;
   - **posizione e dimensione con le ancore** (Layout → Anchors Preset → Custom), in frazioni della mappa da 0 a 1. Per esempio left 0.4, top 0.6, right 0.64, bottom 0.8; guarda le zone esistenti come riferimento;
   - **Requires** (facoltativo): requisiti per aprire la zona, es. `{"flags": {"porto_scoperto": true}}`;
   - **Locked Hint**: il messaggio mostrato toccando la zona chiusa;
   - **Placeholder Color**: il colore della zona finché non c'è un'immagine;
   - **Display Name**: lascialo vuoto per usare il nome di `locations.json`.

Lo smoke test controlla che ogni zona sia nel registro e che ogni location abbia il suo dialogo.

## Salvataggi

- **Automatico:** a ogni ritorno sulla mappa e quando l'app va in background sulla mappa. All'avvio il gioco riprende da lì. Non si salva mai a metà dialogo.
- **Manuale:** pulsante **Menu** sulla mappa, poi **Salva**. Dallo stesso menu ci sono anche **Carica** (torna al salvataggio manuale) e **Nuova partita**.
- **File:** `user://save.json` e `user://save_manuale.json`, più le copie di sicurezza `.bak`. Su Windows `user://` è `%APPDATA%\Godot\app_userdata\Madonna's Quest\`.
- **Se un file si rovina,** il gioco carica la copia `.bak` e conserva quello rotto come `.illeggibile`.

---

## Export per Android

Si può esportare da Windows, macOS o Linux.

### 1. Programmi da installare (una volta sola)

- **Godot 4.7.2 standard**, non .NET. Il progetto è solo GDScript, e con la versione .NET l'export Android di C# è ancora sperimentale. Il progetto si apre allo stesso modo in tutte e due le versioni.
- **Export templates 4.7.2**, della stessa versione dell'editor: in Godot apri **Editor → Gestisci modelli di esportazione… (Manage Export Templates)** e scegli **Download and Install**.
- **OpenJDK 17**, per esempio [Adoptium Temurin 17](https://adoptium.net/temurin/releases/?version=17).
- **Android SDK.** Il modo più semplice è installare [Android Studio](https://developer.android.com/studio), aprire **SDK Manager** e installare:
  - Android SDK Platform-Tools 35.0.0 o successivo;
  - Android SDK Build-Tools 35.0.1;
  - Android SDK Platform 35;
  - Android SDK Command-line Tools (ultima versione);
  - CMake 3.10.2.4988404;
  - NDK 28.1.13356709.

  In alternativa, da riga di comando:
  ```powershell
  sdkmanager --sdk_root=<percorso_sdk> "platform-tools" "build-tools;35.0.1" "platforms;android-35" "cmdline-tools;latest" "cmake;3.10.2.4988404" "ndk;28.1.13356709"
  ```

### 2. Configurare Godot (una volta sola)

In **Editor → Impostazioni dell'editor → Export → Android** imposta:
- **Java SDK Path**: la cartella di OpenJDK 17, es. `C:\Program Files\Eclipse Adoptium\jdk-17...`;
- **Android SDK Path**: la cartella dell'SDK, es. `%LOCALAPPDATA%\Android\Sdk`. Deve contenere `platform-tools\adb.exe`.

### 3. Creare il preset di export

1. Apri **Progetto → Esporta… → Aggiungi… → Android**.
2. Imposta **Package → Unique Name** con un identificativo univoco, es. `com.tuonome.calabrianvn`. Una volta pubblicato non va più cambiato.
3. L'orientamento è già impostato nel progetto: orizzontale, con rotazione automatica.
4. Il file dei preset (`export_presets.cfg`) si può committare. Le password finiscono in `.godot/export_credentials.cfg`, che resta fuori da git.

### 4. Provare sul telefono

1. Sul telefono attiva le **Opzioni sviluppatore** e il **Debug USB**, poi collegalo con il cavo.
2. Nel preset Android spunta **Runnable**.
3. In alto a destra nell'editor compare l'icona del dispositivo Android: cliccala per installare e avviare il gioco con un clic.

In alternativa, **Esporta progetto** con estensione `.apk` e copia il file sul telefono.

### 5. Versione da pubblicare (Google Play)

1. Crea una chiave di firma (**da conservare con cura**: senza non potrai più aggiornare l'app):
   ```powershell
   keytool -v -genkey -keystore calabrianvn.keystore -alias calabrianvn -keyalg RSA -validity 10000
   ```
   Usa solo lettere e numeri nella password, e la stessa password per keystore e chiave.
2. Nel preset compila **Keystore → Release** (percorso del file), **Release User** (l'alias) e **Release Password**. Togli la spunta da **Export With Debug** al momento dell'export.
3. Google Play vuole il formato **AAB**, che richiede la build Gradle: **Progetto → Installa modello di build Android**, poi nel preset attiva **Gradle Build → Use Gradle Build** e scegli **Export Format: AAB**. La cartella `android/` creata dal modello è già esclusa da git.
4. Prepara un'icona vera, perché oggi c'è quella di Godot: almeno 192×192, e 432×432 per le icone adattive.

## Export per iOS

### Requisiti

- Un **Mac con Xcode**: l'export per iOS si può fare solo da macOS.
- Un **account Apple Developer**. Con un Apple ID gratuito puoi provare sul tuo iPhone; per pubblicare sull'App Store serve l'abbonamento a pagamento.
- **Godot 4.7.2 standard** con gli **export templates 4.7.2** installati (come per Android).

### Passi

1. Copia il progetto sul Mac (es. `git clone` della repository) e aprilo con Godot.
2. Apri **Progetto → Esporta… → Aggiungi… → iOS** e compila:
   - **Application → App Store Team ID**: il codice di 10 caratteri del tuo team (es. `ABCDE12XYZ`), visibile su [developer.apple.com](https://developer.apple.com) in alto a destra, accanto al nome. Non è il nome del team mostrato da Xcode;
   - **Application → Bundle Identifier**: identificativo univoco in stile `com.tuonome.calabrianvn`, solo lettere, numeri, trattini e punti.

   Se uno dei due resta vuoto, l'export dà errore.
3. Premi **Esporta progetto**, scegli una **cartella vuota** e un nome file **senza spazi**. Godot crea un progetto Xcode (`<nome>.xcodeproj`).
4. Apri il `.xcodeproj` con Xcode, collega l'iPhone, selezionalo come destinazione e premi **Run**. Per l'App Store si usa **Product → Archive**.
5. Dopo ogni modifica al gioco va rifatto l'export dal punto 3.

Il **simulatore iOS** supporta solo il renderer **Compatibility**, mentre il progetto usa **Mobile**. Per questo è meglio provare su un iPhone vero.
