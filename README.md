# EVERAFTER

Simulazione 3D di una civiltà persistente e autonoma, realizzata con **Godot 4** e **GDScript tipizzato**.

Il mondo è abitato da personaggi con identità, bisogni, professioni, obiettivi, relazioni e memoria.
Gli abitanti agiranno autonomamente, la società evolverà e gli eventi lasceranno conseguenze nel tempo.
Il gioco deve funzionare **offline**, senza servizi a pagamento e senza server obbligatori.

Questo repository contiene oggi la **Fase 1 — primo ambiente esplorabile**: un villaggio fantasy
medievale costruito a codice, camminabile in prima persona, con terreno procedurale, collisioni
verificate, ciclo giorno/notte guidato dall'orologio di simulazione e un'interfaccia minima.

> Stato onesto del progetto: **non esistono ancora NPC, economia, relazioni, politica, cronache o
> salvataggi.** Sono progettati in [`docs/ROADMAP.md`](docs/ROADMAP.md), non implementati.
> Questa fase riguarda la solidità del mondo fisico, come richiesto.

---

## 1. Requisiti

| Voce | Valore |
| --- | --- |
| Motore | **Godot 4.5 o superiore, build stabile** (verificata qui: `4.7.2-stable`) |
| Sistema operativo | Windows 10/11 64-bit (target iniziale del progetto) |
| GPU | Classe NVIDIA GTX 1060 o superiore, con driver Vulkan aggiornati |
| RAM | 16 GB consigliati |
| Dipendenze esterne | Nessuna. Niente plugin, niente pacchetti, niente rete a runtime, nessun asset binario |
| Strumenti di sviluppo (opzionali) | Python 3 e `gdtoolkit` per i controlli statici |

Il progetto è **solo testo**: script, scene, una risorsa di configurazione, documentazione. Ogni
mesh, materiale e colore è generato dal codice. Una volta clonato, funziona senza connessione.

## 2. Aprire ed eseguire il progetto su Windows

1. Scarica Godot 4 stabile da <https://godotengine.org/download/windows/>
   (file `Godot_v4.x-stable_win64.exe.zip`; la versione `_console` è comoda per vedere i log).
2. Estrai l'archivio dove preferisci. Non serve installare nulla.
3. Avvia l'editor, premi **Import**, seleziona il file `project.godot` di questa repository
   e premi **Import & Edit**.
4. Al primo avvio Godot genera la cartella `.godot/` (cache locale, ignorata da git). **È un passo
   obbligatorio**: contiene anche `global_script_class_cache.cfg`, senza il quale i `class_name`
   non vengono risolti e gli script non compilano.
5. Premi **F5** (oppure ▶ in alto a destra): il progetto parte dalla scena principale
   `res://src/world/scenes/main_world.tscn` e il giocatore compare sulla strada sud-ovest,
   rivolto verso la piazza.

### Da riga di comando (senza aprire l'editor)

Apri un terminale nella cartella del progetto. La prima volta genera la cache:

```bat
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

Poi:

```bat
:: esegue il gioco
Godot_v4.7.2-stable_win64.exe --path .

:: finestra più piccola, utile per i test rapidi
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900

:: suite di test headless di unità (nessuna finestra, nessuna GPU)
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd

:: suite di integrazione: avvia davvero la scena e interroga la fisica
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_world_tests.gd

:: interrompe il gioco dopo N frame (smoke test senza giocatore)
Godot_v4.7.2-stable_win64_console.exe --path . --quit-after 30
```

Su Windows l'output su console è visibile solo con l'eseguibile `_console.exe`.

## 3. Controlli

| Input | Azione |
| --- | --- |
| `W` `A` `S` `D` o frecce | Muoversi |
| `Shift` | Correre |
| `Spazio` | Saltare |
| Mouse | Guardarsi attorno |
| `Esc` | **Libera il mouse** (per raggiungere la finestra, l'editor, un secondo monitor) |
| Clic sinistro **oppure** `F` | **Riprende il controllo del mouse** |
| `P` | Pausa / ripresa della simulazione |
| `+` / `-` | Velocità della simulazione (x1, x3, x10) |
| `F1` | Mostra / nasconde il pannello diagnostico (nascosto all'avvio) |

Quando il mouse è libero, in basso allo schermo compare la scritta
*"Clic sinistro o F per riprendere il controllo"*: nessuno deve dover indovinare come si torna a
giocare. Perdendo il fuoco della finestra il mouse viene liberato automaticamente.

Tutti gli input sono mappati come **azioni** in `project.godot` (sezione `[input]`), quindi sono
rimappabili dall'editor senza toccare il codice.

## 4. Che cosa si vede avviando il gioco

Un villaggio di confine, al mattino del giorno 1 (ore 07:00 simulate):

* **Terreno** 159 × 159 unità (160 × 160 celle) con colline dolci generate da value noise
  deterministico. Le strade e le aree edificate perdono solo le ottave di dettaglio, non le
  colline: i percorsi sono camminabili senza che il paesaggio diventi una trincea piatta.
* **Piazza del Pozzo** lastricata al centro, con pozzo in pietra, tettoia e secchio, e una
  coroncina di blocchi di pietra che ne marca il bordo.
* **13 case** con sagome diverse: cottage a un piano, case a due piani con tetto ripido, case
  lunghe con portico; intonaco chiaro o ocra, travi a vista, plinti in pietra, comignoli,
  finestre che si illuminano di notte.
* **Locanda del Cervo Bianco**: due piani, ala a L, portico su colonne, insegna appesa.
* **Sala del Consiglio** con campanile: l'edificio più alto del villaggio.
* **2 banchi del mercato** con tenda in tessuto e merci sul banco.
* **Tre strade** che escono dalla piazza verso il nord, il mercato e lo stagno, con 12 lampioni,
  11 tratti di steccato, carri, casse, barili, cataste di legna e un cartello indicatore.
* **250 alberi** di tre specie (quercia, pino, betulla) con sagome diverse, 39 cespugli,
  9 massi, e uno **stagno** con acqua traslucida a nord-est.
* **2600 ciuffi d'erba** in un unico `MultiMesh`, quindi una sola draw call.
* **Cielo e luce** che seguono l'ora simulata, non quella reale: il sole si sposta, il cielo
  cambia colore, la nebbia si infittisce, le finestre e i lampioni si accendono al tramonto.
  È la dimostrazione visibile che la simulazione ha un orologio proprio.
* **Interfaccia** in alto a sinistra: nome del gioco, giorno simulato con l'ora, e il nome
  dell'area in cui ti trovi (8 aree: piazza, tre strade, stagno, locanda, sala del consiglio,
  bosco; fuori da tutte, "Campi di Everafter").

### Costo misurato della scena

Misurato avviando la scena con Godot 4.7.2 headless (`--script res://tests/run_world_tests.gd`):

| Voce | Valore |
| --- | --- |
| Draw call (mesh + MultiMesh + terreno) | **145** |
| Triangoli totali | **107.643** (50.562 terreno + 57.081 villaggio ed erba) |
| Collider statici | **292** |
| Materiali distinti | **≤ 24** (verificato da un test) |
| Istanze d'erba | 2.600 in 1 draw call |

Per confronto: una casa "a primitive" sarebbe circa 15 nodi e 15 draw call; qui l'intera foresta
ne costa una manciata, perché `MeshBaker` fonde per materiale.

## 5. Struttura del repository

```
project.godot                  scena principale, autoload, input, rendering
icon.svg                       icona provvisoria (vettoriale, senza dipendenze)
config/game_config.tres        valori di tuning modificabili dall'editor
src/
  core/                        orologio simulato, configurazione, logging, singleton
    simulation_clock.gd          tempo simulato deterministico (1 tick = 1 minuto)
    game_config.gd               risorsa di configurazione + validazione
    game_log.gd                  logger minimale a livelli
    autoload/event_bus.gd        singleton "EventBus": segnali condivisi tra moduli
    autoload/game_root.gd        singleton "Game": possiede config e SimulationLoop
  simulation/                  sistemi della civiltà (indipendenti dalla scena 3D)
    simulation_system.gd         contratto di ogni sistema
    simulation_loop.gd           fixed timestep, pausa, velocità, catch-up
    systems/day_cycle_system.gd  sole e fase del giorno
  world/                       mondo 3D
    scenes/main_world.tscn       scena principale
    main_world.gd                radice di composizione: terreno, villaggio, spawn, aree
    terrain_generator.gd         height field deterministico (mesh + heightmap di collisione)
    player_explorer.gd           esploratore in prima persona (CharacterBody3D)
    areas/area_registry.gd       regioni nominate, pura dati
    environment/
      village_layout.gd          il piano del villaggio: strade, lotti, pesi del terreno
      village_materials.gd       palette unica e materiali condivisi
      mesh_baker.gd              fonde primitive in una mesh per materiale
      building_factory.gd        case, locanda, sala, pozzo, banchi, oggetti
      vegetation_builder.gd      alberi, cespugli, massi, erba (MultiMesh)
      village_builder.gd         assembla il villaggio: mesh, collider, acqua
      sky_rig.gd                 sole, cielo, nebbia, bagliore notturno
  ui/
    scenes/world_hud.tscn        interfaccia discreta: titolo, giorno, area
    world_hud.gd
    scenes/diagnostics_hud.tscn  pannello diagnostico (F1)
    diagnostics_hud.gd
tests/
  run_tests.gd                 runner di unità (exit code 0/1)
  run_world_tests.gd           runner di integrazione (avvia la scena, interroga la fisica)
  harness/test_harness.gd      micro harness di asserzioni
  unit/                        clock, loop, day cycle, terreno, config, layout, aree,
                               materiali, baker, direzione artistica
  integration/
    test_world_scene.gd        scena, terreno vs fisica, collisioni del giocatore, budget
tools/
  check_project.py             verifiche statiche di coerenza del progetto (solo Python 3)
  run_checks.sh                esegue tutti i controlli disponibili
docs/
  ARCHITECTURE.md              scelte architetturali e regole di dipendenza
  ROADMAP.md                   fasi successive, criteri di accettazione, rischi
```

## 6. Renderer e prestazioni

**Renderer scelto: `forward_plus`** (con MSAA 3D 2x, una sola luce con ombre a 130 m, tonemapping
filmico, SSAO e glow disattivati, `Camera3D.far = 420`).

Motivazione:

* una GTX 1060 gestisce Vulkan senza problemi; con 145 draw call e ~108k triangoli la scena è
  molto al di sotto di ciò che mette in difficoltà quella scheda a 1080p;
* `forward_plus` offre gli strumenti di debug migliori e resta il percorso più mantenuto del
  motore, quindi è la scelta più stabile su cui costruire le fasi successive;
* la compatibilità è gestita a livello di impostazione, non di codice: se un driver Vulkan dà
  problemi si passa a `mobile` o `gl_compatibility` in *Project Settings → Rendering → Renderer →
  Rendering Method*. **Nessuna riga di codice dipende dal renderer scelto.**

Regole di costo applicate nel codice, non solo dichiarate:

1. **una mesh per materiale** (`MeshBaker`): un villaggio di centinaia di solidi diventa 145 draw
   call invece di migliaia;
2. **una palette condivisa** (`VillageMaterials`): ≤ 24 materiali per tutto il villaggio, con
   variazione cromatica affidata ai colori per vertice;
3. **erba in `MultiMesh`**, senza ombre proiettate;
4. **una sola mappa d'ombre**: la luce di riempimento (`Sky/Fill`) non ne ha;
5. **niente SSAO, niente glow, niente nebbia volumetrica**;
6. un test (`PerformanceBudget`) fallisce se draw call, triangoli o collider superano il budget:
   il costo non può raddoppiare di nascosto.

## 7. Controlli e verifiche

### Con solo Python 3 (nessun motore necessario)

```bash
python3 tools/check_project.py            # coerenza di percorsi, scene, nodi, azioni di input
pip install gdtoolkit                     # opzionale: parser e linter GDScript
gdparse $(find src tests -name '*.gd')    # sintassi GDScript
gdlint src tests                          # stile
```

### Con Godot installato

```bash
bash tools/run_checks.sh                              # esegue tutto ciò che è disponibile
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_world_tests.gd
```

`tools/run_checks.sh` stampa chiaramente quali controlli sono stati **eseguiti** e quali sono stati
**saltati** perché lo strumento non è installato: non dichiara mai superato un test non eseguito.

### Verifiche realmente eseguite su questa fase

Le due suite sono state eseguite con un motore **Godot 4.7.2-stable reale**, in modalità headless
(build WebAssembly avviata sotto Node, renderer "dummy"): gli script GDScript sono stati compilati
ed eseguiti dal motore, la scena principale è stata istanziata, il server fisico ha simulato.

| Controllo | Strumento | Esito |
| --- | --- | --- |
| Sintassi di tutti i 35 script GDScript di `src/` e `tests/` | `gdparse` (gdtoolkit 4.5.0) | **eseguito — OK** |
| Stile GDScript | `gdlint` (gdtoolkit 4.5.0) | **eseguito — 0 problemi** |
| Coerenza progetto: scena principale, autoload, `res://`, ext/sub resource, percorsi `$Nodo` degli script rispetto alle scene, azioni di input, `.gitignore` | `tools/check_project.py` | **eseguito — OK** |
| Suite di unità headless (`tests/run_tests.gd`) | Godot 4.7.2 headless | **eseguito — 355 passati, 0 falliti** |
| Suite di integrazione (`tests/run_world_tests.gd`) | Godot 4.7.2 headless | **eseguito — 49 passati, 0 falliti** |
| Resa visiva su GPU (come *appare* il villaggio) | — | **NON eseguito**: l'ambiente di verifica non ha GPU. Geometria, winding, normali, materiali e collisioni sono verificati; l'immagine finale no |
| Prova su Windows con Godot desktop | — | **NON eseguita**: da fare in revisione |

Che cosa copre davvero la suite di integrazione, perché è la parte che conta:

* **terreno visto = terreno camminato**: 196 raggi verso il basso confrontano la superficie fisica
  (`HeightMapShape3D`) con `TerrainGenerator.height_at()`; lo scarto massimo ammesso è 5 cm ed è
  risultato ~0. Questo è il test che avrebbe preso subito il bug di winding della fase precedente.
* **il giocatore sta in piedi**: dopo 45 frame di fisica `is_on_floor()` è vero e il centro della
  capsula è a una mezza altezza dal terreno.
* **il giocatore non affonda**: su 120 frame ulteriori la distanza minima dal terreno resta
  positiva.
* **i muri fermano il giocatore**: `PhysicsServer3D.body_test_motion()` con la **capsula reale del
  giocatore** contro una casa vera; la corsa si interrompe ben prima dei 12 metri richiesti.
* **il giocatore non esce dal mondo**: la posizione è limitata ai bordi del terreno.
* **budget**: draw call, triangoli e collider restano entro i limiti dichiarati.

### Tre difetti reali trovati eseguendo il motore

La fase precedente dichiarava i test "scritti ma non eseguiti". Eseguendoli sono emersi tre bug:

1. **`SimulationClock.to_string()` non veniva mai chiamata.** In GDScript il metodo virtuale è
   `_to_string()`; un metodo chiamato `to_string()` non sovrascrive nulla. Ora corretto, e il test
   confronta la stringa formattata, quindi la regressione non può tornare.
2. **Il terreno aveva il winding invertito**: tutte le normali puntavano verso il basso. Misurato
   sul motore: Godot 4.7.2 ricava la normale di un triangolo `(a, b, c)` come `(c − a) × (b − a)`.
   Con il back-face culling attivo il suolo sarebbe sparito visto dall'alto. Corretto, e coperto da
   `tests/unit/test_mesh_baker.gd` e dai raggi della suite di integrazione.
3. **Un test del loop chiedeva l'impossibile**: `update(0.25)` a velocità x4 pretende 20 tick, ma
   il guard `max_steps_per_frame = 12` (giustamente) li limita, e l'accumulatore in virgola mobile
   perde il ventesimo tick. Il test ora usa un `tick_seconds` potenza di due e un tetto esplicito,
   e verifica il guard come comportamento proprio.

## 8. Limiti noti di questa fase

* **Nessun NPC**, bisogno, lavoro, inventario, prezzo, relazione, legge, fazione o cronaca: è la
  fase successiva, deliberatamente non iniziata.
* **Nessun interno**: le case sono volumi chiusi con una scatola di collisione. Porte e finestre
  sono dettagli di superficie, non aperture.
* **Nessuna serializzazione**: `to_dict()` / `from_dict()` esistono su clock, loop e sistemi, ma
  non c'è ancora un modulo `persistence`.
* **La resa visiva non è stata vista su GPU.** Geometria, materiali e illuminazione sono costruiti
  con criterio e verificati strutturalmente, ma l'aspetto finale va giudicato a schermo.
* Il terreno è un'unica mesh generata all'avvio (25.600 vertici). Oltre queste dimensioni serviranno
  chunk e streaming (in roadmap).
* Alberi e oggetti non hanno LOD: a 145 draw call non serve, ma andrà rivisto se il mondo cresce.
* L'IA generativa non è integrata e non è richiesta per giocare.
* Nessun preset di export: l'esportazione Windows verrà configurata quando ci saranno contenuti
  sufficienti da impacchettare.

## 9. Come contribuire / proseguire

1. Leggi [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) prima di scrivere codice: contiene le
   regole di dipendenza tra moduli e la convenzione sul determinismo.
2. Scegli la fase successiva in [`docs/ROADMAP.md`](docs/ROADMAP.md).
3. Ogni sistema nuovo arriva con: script tipizzato, test headless, riga di documentazione,
   nessuna API dichiarata ma non usata.
4. Prima di proporre una modifica: `bash tools/run_checks.sh`. Una modifica che tocca mondo,
   terreno o giocatore deve mantenere verde anche `tests/run_world_tests.gd`.
