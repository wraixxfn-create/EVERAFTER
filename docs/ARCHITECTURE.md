# EVERAFTER — Architettura tecnica

Questo documento descrive le scelte architetturali della **Fase 0** e le regole che valgono per le
fasi successive. È il riferimento da leggere prima di scrivere codice: quando una decisione cambia,
cambia qui, non solo nel codice.

---

## 1. Principi

1. **La simulazione è la fonte di verità, il rendering è una conseguenza.**
   Il mondo evolve per tick logici; la scena 3D legge lo stato e lo mostra. Mai il contrario.
2. **Determinismo prima della comodità.** Due esecuzioni con la stessa sequenza di tick devono
   produrre lo stesso mondo. Questo rende la simulazione testabile, riproducibile nei bug report e
   serializzabile senza sorprese.
3. **Il tempo simulato è separato dal tempo reale e dal frame rate.** Nessun sistema legge `delta`
   del frame, `Time.get_ticks_*()` o il numero di FPS.
4. **Offline first.** Nessuna chiamata di rete nel percorso di gioco. L'IA generativa, quando
   arriverà, sarà un livello opzionale e degradabile, mai un requisito.
5. **Moduli piccoli e verificabili.** Meglio dieci script da 100 righe con un test ciascuno che uno
   script da 1000 righe "per ora funziona".
6. **Nessuna API morta.** Un segnale, una classe o un metodo pubblico entra nel progetto insieme al
   suo primo utilizzatore reale.
7. **Nessuna dipendenza non necessaria.** Motore + GDScript standard. `gdtoolkit` è solo uno
   strumento di sviluppo, non una dipendenza a runtime.

## 2. Mappa dei moduli

| Modulo | Stato | Responsabilità |
| --- | --- | --- |
| `src/core` | implementato | orologio simulato, configurazione, logging, singleton di coordinamento |
| `src/simulation` | implementato (1 sistema) | loop a passo fisso e sistemi della civiltà |
| `src/world` | implementato | terreno procedurale, villaggio provvisorio, esploratore, scena principale |
| `src/ui` | implementato | pannello diagnostico |
| `config/` | implementato | risorsa `GameConfig` modificabile dall'editor |
| `tests/` | implementato | suite headless + micro harness |
| `tools/` | implementato | verifiche statiche eseguibili senza motore |
| `src/npcs` | **non presente** | identità, bisogni, memoria, comportamenti individuali |
| `src/economy` | **non presente** | risorse, inventari, produzione, scambi, prezzi |
| `src/relationships` | **non presente** | fiducia, amicizie, rivalità, famiglie |
| `src/society` (o dentro `simulation/`) | **non presente** | leadership, leggi, fazioni, conflitti |
| `src/history` | **non presente** | cronache ed eventi memorabili |
| `src/persistence` | **non presente** | salvataggio, caricamento, versionamento e migrazioni |

Le cartelle non esistono ancora e **non sono state create vuote**: verranno aggiunte dalla fase che
le introduce, insieme al codice che le abita (vedi `docs/ROADMAP.md`).

## 3. Flusso di un tick

```
        tempo reale (delta del frame)
                     │
                     ▼
   Game (autoload) ── _process(delta) ──▶ SimulationLoop.update(delta)
                                              │
                                              │  accumulatore += delta * time_scale
                                              │  while accumulatore >= tick_seconds
                                              ▼
                                     SimulationLoop.step_once()
                                              │
                        ┌─────────────────────┼─────────────────────┐
                        ▼                     ▼                     ▼
              SimulationClock.advance   sistema 1.on_tick   sistema N.on_tick
                        │              (ordine di registrazione)
                        ▼
              segnali di basso livello: day_advanced, time_scale_changed
                        │
                        ▼
                   EventBus ─────────▶ UI (pannello diagnostico)
                        │
        stato letto a ogni frame (non via segnale)
                        ▼
        MainWorld ── sole, cielo, luce ──▶ rendering
```

Punti chiave:

* `SimulationLoop.update()` converte il tempo reale in un **numero intero di tick** e conserva il
  resto in un accumulatore: nessun tempo simulato perso o duplicato.
* `max_steps_per_frame` limita i tick eseguiti in un frame: se una finestra resta bloccata per dieci
  secondi, il backlog viene scartato invece di essere simulato in un unico scatto
  (protezione dalla *spiral of death*).
* `SimulationLoop.run_ticks(n)` esiste già ed è il punto d'ingresso del futuro "tempo trascorso
  mentre il giocatore era assente": nessun rendering coinvolto.
* Gli eventi ad alta frequenza **non** passano da `EventBus`: i sistemi ricevono `on_tick()`
  direttamente. Sul bus viaggiano solo eventi a bassa frequenza (cambio giorno, cambio velocità,
  pausa, mondo pronto).

## 4. Tempo simulato

* **1 tick logico = 1 minuto simulato.** Un giorno dura `SimulationClock.MINUTES_PER_DAY = 1440` tick.
* Alla velocità x1 un tick dura `GameConfig.logic_tick_seconds = 0.05` secondi reali
  (20 tick/secondo), quindi **un giorno simulato dura 72 secondi reali**.
* Il contatore `tick` è un intero a 64 bit. Tutte le derivate (giorno, ora, minuto, progresso del
  giorno) sono aritmetica intera su di esso: niente accumulo di errori in virgola mobile.
* Il giorno mostrato al giocatore parte da **1** (`get_display_day()`), mentre l'indice interno parte
  da 0 (`get_day_index()`). La convenzione è fissata qui e nei test.
* Il mondo parte da `GameConfig.start_minute_of_day` (default 420 = 07:00 del giorno 1) tramite
  `SimulationLoop.set_start_time()`, che posiziona l'orologio e inizializza i sistemi su quell'ora:
  il primo frame renderizzato è già coerente con l'orologio.
* Pausa e velocità sono concetti separati: `paused` è un booleano, `time_scale` è un moltiplicatore
  con preset `[1, 3, 10]` configurabili.

## 5. Determinismo

Regole valide per ogni sistema presente e futuro:

1. Dentro `on_tick()` non si leggono: `delta` del frame, input, scene tree, orologio di sistema,
   `randf()` globale.
2. Il caso, quando serve, passa da un `RandomNumberGenerator` con seme derivato da
   `GameConfig.terrain_seed` o da un seme di mondo versionato (stesso seme ⇒ stessa sequenza).
3. La generazione procedurale usa hash interi con maschera a 31 bit
   (`TerrainGenerator._hash()`), così nessun prodotto esce dall'intervallo dei 64 bit e il risultato
   non dipende dalla piattaforma.
4. L'ordine di esecuzione dei sistemi è l'ordine di registrazione ed è parte del contratto: va
   documentato quando conta.
5. Ogni sistema deve poter fare round trip con `to_dict()` / `from_dict()`.

Verifica: `tests/unit/test_simulation_loop.gd` contiene un controllo esplicito di determinismo
(due loop alimentati con la stessa sequenza di delta producono lo stesso tick e la stessa ora).

## 6. Singleton (autoload)

Registrati in `project.godot`, **in questo ordine**:

1. `EventBus` (`src/core/autoload/event_bus.gd`) — solo segnali, nessuna logica.
2. `Game` (`src/core/autoload/game_root.gd`) — possiede `GameConfig` e `SimulationLoop`, registra i
   sistemi, gestisce pausa e velocità, espone una facciata di lettura per UI e mondo.

Motivazione: la simulazione deve esistere anche quando nessuna scena 3D è caricata (test headless,
caricamenti, futuro menu principale), e deve essercene esattamente una.

Regola: gli script di autoload **non dichiarano `class_name`** (evita ambiguità tra nome globale e
singleton); `tools/check_project.py` lo verifica automaticamente.

## 7. Regole di dipendenza

```
ui ──────▶ core (Game, EventBus)
world ───▶ core + simulation (lettura di stato)
simulation ─▶ core (SimulationClock, GameConfig, GameLog)
core ────▶ (nessun altro modulo di gioco)
```

Vietato:

* `simulation/*` che importa o istanzia nodi, scene o classi di `world/` o `ui/`;
* `core/*` che conosce `world/`, `ui/` o un sistema concreto (fa eccezione `Game`, che è il punto di
  composizione radice e registra i sistemi);
* `ui/*` che modifica lo stato della simulazione: la UI legge e invia comandi a `Game`.

Un sistema che ha bisogno di mostrare qualcosa **pubblica stato**, e il mondo lo legge
(esempio reale: `DayCycleSystem.sun_elevation_deg` → `MainWorld._apply_day_cycle()`).

## 8. Mondo 3D

* **Terreno**: un unico height field generato da `TerrainGenerator`. La mesh visibile e la
  `HeightMapShape3D` di collisione derivano dalla *stessa* griglia, con lo stesso passo (1 unità),
  lo stesso centraggio sull'origine e la stessa diagonale di triangolazione, quindi ciò che si vede
  è ciò su cui si cammina. `height_at()` interpola sugli stessi due triangoli della shape fisica,
  così gli oggetti appoggiati al terreno non restano sospesi.
* **Oggetti**: `PropBuilder` compone case, monumento e alberi con primitive del motore e materiali
  condivisi per colore. La collisione è una scatola o un cilindro: sufficiente per la Fase 0.
* **Esploratore**: `CharacterBody3D` + capsula, movimento in `_physics_process` con `move_and_slide`,
  gravità letta da `physics/3d/default_gravity`. Scelto perché è l'opzione più semplice e robusta
  per verificare terreno, collisione e camera senza introdurre un sistema di personaggi.
* **Rendering**: `forward_plus`, MSAA 2x, tonemapping filmico, cielo procedurale, nebbia leggera.
  Su macchine con driver Vulkan problematici si può passare a `mobile` o `gl_compatibility` in
  *Project Settings → Rendering → Renderer → Rendering Method*; nessuna riga di codice dipende dal
  renderer scelto.

## 9. Configurazione

Un'unica risorsa `GameConfig` (`config/game_config.tres`) contiene i valori di tuning: titolo,
durata del tick, preset di velocità, dimensione e seme del terreno, parametri del giocatore,
versione del formato di salvataggio.

`GameConfig.load_or_default()` carica la risorsa e, se manca o è corrotta, restituisce i default del
codice: **il gioco parte comunque**. `validate()` restituisce un elenco di problemi leggibili che
`Game` scrive nel log all'avvio senza bloccare nulla.

`save_format_version` è già riservato: quando arriverà `persistence`, i salvataggi saranno
versionati dal primo giorno invece di essere adattati dopo.

## 10. Persistenza (progettata, non implementata)

Oggi esistono soltanto i punti di aggancio:

* `SimulationClock.to_dict()` / `from_dict()`;
* `SimulationLoop.to_dict()` / `from_dict()` (include i sistemi, indicizzati per nome);
* `SimulationSystem.to_dict()` / `from_dict()` come contratto per i sistemi futuri;
* `GameConfig.save_format_version`.

Il modulo `persistence` dovrà: scrivere su `user://` in formato testo leggibile (JSON), includere
versione e checksum, caricare in modo tollerante ai campi mancanti e avere test di round trip per
ogni sistema. Decisione rinviata di proposito: progettare il formato prima che esistano NPC ed
economia produrrebbe uno schema da buttare.

## 11. Prestazioni

Budget di riferimento: PC Windows con 16 GB di RAM e GPU classe GTX 1060, 1080p, 60 FPS.

Scelte già in atto:

* terreno unico da ~16k vertici / ~32k triangoli, un solo draw call con materiale a vertici colorati;
* materiali condivisi tra gli oggetti dello stesso colore;
* collisione del terreno con `HeightMapShape3D` (più veloce di una trimesh concava);
* la UI aggiorna sette `Label` a frame: costo trascurabile;
* nessun post-processing pesante (niente SSAO, SSR, SDFGI, glow).

Quando arriveranno centinaia di NPC, la strada indicata è: stato simulato separato dai nodi,
rappresentazione visiva con `MultiMesh`, aggiornamento delle transform a lotti e sistemi che
lavorano su array invece che su oggetti. Nessuna di queste ottimizzazioni è presente oggi.

## 12. Convenzioni di codice

* GDScript **tipizzato**: tipi su variabili, parametri e valori di ritorno.
* `class_name` per le classi riutilizzabili; niente `class_name` sugli autoload.
* Prefisso `_` per membri e metodi privati.
* Docstring `##` su ogni classe e su ogni metodo pubblico: la documentazione vive nel codice.
* Costanti in `MAIUSCOLO_SNAKE`, segnali al passato (`day_advanced`, non `on_day`).
* Niente `print()` sparsi: si usa `GameLog` con un tag di modulo.
* Lunghezza riga ≤ 100 caratteri (verificata da `gdlint`).
* Un file = un concetto. Se un file supera qualche centinaio di righe, va spezzato.

## 13. Verifiche

| Livello | Strumento | Che cosa copre | Richiede |
| --- | --- | --- | --- |
| Sintassi | `gdparse` | errori di grammatica in ogni `.gd` | `pip install gdtoolkit` |
| Stile | `gdlint` | convenzioni, lunghezza righe, ordine delle definizioni | `pip install gdtoolkit` |
| Coerenza progetto | `tools/check_project.py` | scena principale, autoload, riferimenti `res://`, ext/sub resource, alberi di nodi vs percorsi `$Nodo` negli script, azioni di input, `.gitignore` | Python 3 |
| Unità | `tests/run_tests.gd` | orologio, loop, day cycle, terreno, configurazione | Godot 4 (`--headless`) |
| Integrazione | da aggiungere | caricamento della scena principale in `--headless` | Godot 4 |

`bash tools/run_checks.sh` esegue ciò che è disponibile e **dichiara esplicitamente** ciò che salta.
Un controllo saltato non è un controllo superato.

## 14. Decisioni valutate e scartate (o rinviate)

| Decisione | Esito | Motivazione |
| --- | --- | --- |
| C# o GDExtension invece di GDScript | scartata | richiede toolchain .NET, complica build e verifiche; GDScript è sufficiente per la simulazione prevista |
| Plugin di terze parti (es. framework di test) | rinviata | la suite attuale è una decina di funzioni; se cresce si valuta GUT, cambiando un solo file |
| Terreno importato da un tool 3D | scartata per ora | introdurrebbe asset binari e romperebbe la riproducibilità dal solo testo |
| Heightmap da immagine (`update_map_data_from_image`) | scartata | richiede un asset e un formato; la generazione procedurale è più leggera e deterministica |
| Tutto costruito a codice senza `.tscn` | scartata | le scene restano ispezionabili e modificabili dall'editor, che resta lo strumento principale |
| Renderer `mobile` o `gl_compatibility` come default | rinviata | `forward_plus` dà più strumenti di debug su desktop; il cambio è una sola impostazione |
| Preset di export Windows | rinviata | utile quando ci saranno contenuti da impacchettare |
| Salvataggi su file | rinviata | vedi sezione 10: prima servono i dati da salvare |
