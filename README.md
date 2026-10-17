# EVERAFTER

Simulazione 3D di una civiltà persistente e autonoma, realizzata con **Godot 4** e **GDScript tipizzato**.

Il mondo è abitato da personaggi con identità, bisogni, professioni, obiettivi, relazioni e memoria.
Gli abitanti agiranno autonomamente, la società evolverà e gli eventi lasceranno conseguenze nel tempo.
Il gioco deve funzionare **offline**, senza servizi a pagamento e senza server obbligatori.

Questo repository contiene oggi la **fase Economia locale (`0.4.0-economy`)**, costruita sopra il
villaggio esplorabile e gli abitanti autonomi delle fasi precedenti: un ambiente fantasy medievale
a codice, camminabile in prima persona, con terreno procedurale e ciclo giorno/notte, abitato da
**10 persone** (numero configurabile) che hanno un nome, un mestiere, bisogni, una casa, un posto
di lavoro, una routine giornaliera e un **ciclo economico delle risorse** (`Cibo`, `Legno`,
`Pietra`, `Moneta`). La simulazione gira anche quando nessuno li guarda.

> Stato onesto del progetto: **esistono il villaggio 3D, gli NPC autonomi e il primo sistema
> economico locale; non esistono ancora mercati dinamici complessi, finanza avanzata, relazioni
> simulate, politica, cronache o salvataggi.** Le strutture dati per relazioni e ricordi sono
> seminate, ma non c'è ancora un sistema sociale o politico. Sono progettati in
> [`docs/ROADMAP.md`](docs/ROADMAP.md), non implementati.

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
| **Clic sinistro** (mouse catturato) | Seleziona l'abitante sotto il mirino e apre la sua scheda |
| **Clic sinistro** (mouse libero) | Seleziona l'abitante sotto il puntatore e cattura di nuovo il mouse |
| **Elenco "Abitanti"** | Sceglie un abitante dal pannello, anche se è lontano e non è disegnato |

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

### Gli abitanti (novità di questa fase)

Nel villaggio vivono **10 abitanti iniziali**, configurabili in un solo punto
(`npc_population_size` in `config/game_config.tres`, da 0 a 16). Ognuno ha:

* un **ID stabile** (`npc_001` … `npc_016`), un nome e un'età adulta;
* **professione** (agricoltore, raccoglitrice, pescatore, panettiera, locandiera, boscaiolo,
  cavatore, mercante, cancelliera, tessitrice, …) e un **posto di lavoro** con un orario;
* una **personalità** numerica (diligenza, socievolezza, curiosità, calma);
* tre **bisogni** (energia, fame, benessere) che cambiano a ogni minuto simulato;
* una **casa** e una posizione sul terreno;
* un **obiettivo** e un'**attività** correnti, con un motivo leggibile;
* relazioni e ricordi iniziali, presenti come dati ma **non ancora simulati**.

La giornata è regolata da regole esplicite e deterministiche: sveglia e sonno tra le 22:00 e le
06:00, turno di lavoro nella propria fascia, pasti quando la fame supera la soglia (locanda o
mercato se aperti, altrimenti la dispensa di casa), riposo quando l'energia scende, tempo libero
in piazza, alla locanda o allo stagno. Non ci sono numeri casuali: lo stesso stato iniziale e lo
stesso numero di tick producono lo stesso risultato su qualunque macchina.

Gli abitanti sono rappresentati da capsule colorate per mestiere, con il nome sopra la testa. Le
capsule vengono create solo entro `npc_view_distance` (70 unità, configurabile) e distrutte quando
si allontanano: **la simulazione non si ferma mai** per un NPC non disegnato. Il pannello in basso
a destra mostra la scheda dell'abitante selezionato (nome, età, professione, attività, obiettivo,
tre barre dei bisogni, riepilogo). Si può selezionare cliccando la capsula oppure scegliendo il
nome dall'elenco: l'elenco funziona anche per chi è fuori portata visiva.

Il pannello e le capsule leggono soltanto i `NpcRecord`; non li modificano. La simulazione vive in
`src/npcs/` e `src/economy/` e non conosce né la scena 3D né l'interfaccia.

### Economia locale e ciclo delle risorse (novità di questa fase)

Il modulo `src/economy/` collega in modo deterministico il lavoro degli abitanti alle risorse della
comunità:

* **Quattro risorse intere non negative** (`ResourceType`): **Cibo** (`food`, prezzo base `2`),
  **Legno** (`wood`, prezzo base `3`), **Pietra** (`stone`, prezzo base `4`) e **Moneta** (`coin`,
  unità `1`).
* **Inventari convalidati** (`ResourceInventory`): magazzino collettivo del villaggio (`village`,
  scorte iniziali configurabili: `24 Cibo`, `12 Legno`, `10 Pietra`, `60 Moneta`), sacche
  individuali degli abitanti (`npc_001` … `npc_016`, `4 Moneta` iniziali) ed emporio di scambio del
  mercato (`market`, scorte finite). Nessuna operazione può portare una risorsa sotto zero o
  modificare parzialmente lo stato in caso di errore.
* **Produzione legata al lavoro reale**: un lavoratore accumula progresso produttivo (`+1` minuto
  lavorato per tick) **solo** mentre si trova fisicamente nel proprio luogo di lavoro con
  `Activity.WORKING`, prerequisiti della postazione soddisfatti (`workplace_prerequisites`), fame
  `< 92` ed energia `> 5`:
  * **Agricoltore** (`farmer`): `60` min lavorati → `+3 Cibo` (`+2 Moneta` di compenso dalla cassa
    comune);
  * **Raccoglitrice / Pescatore / Panettiera** (`forager`, `fisher`, `baker`): `60` min lavorati →
    `+2 Cibo` (`+1 Moneta`);
  * **Locandiera** (`innkeeper`): `75` min lavorati → `+2 Cibo` (`+1 Moneta`);
  * **Boscaiolo** (`woodcutter`): `60` min lavorati → `+2 Legno` (`+2 Moneta`);
  * **Cavatore / addetto all'estrazione** (`quarry_worker`): `60` min lavorati → `+2 Pietra`
    (`+2 Moneta`);
  * **Commerciante** (`merchant`): ogni `60` min lavorati al mercato facilita gli scambi tra sacche
    individuali, magazzino del villaggio ed emporio a prezzi base fissi, **senza mai creare risorse
    o moneta dal nulla**.
* **Consumo alimentare e carenze**: ogni pasto (`Activity.EATING` o razione serale delle `19:00`)
  consuma `1 Cibo` (dalla sacca personale o dal magazzino del villaggio, versando `2 Moneta` alla
  cassa comune se disponibili). Se il cibo è esaurito (`0 Cibo`), il pasto fallisce senza portare le
  scorte in negativo, registra una carenza, riduce il benessere (`-4,5` immediati e deriva negativa)
  e impedisce alla fame di scendere sotto `76,0`, **senza introdurre mortalità né carestie
  irreversibili**.
* **Progetti comunitari**: `Legno`, `Pietra` e `Moneta` vengono impiegati in progetti del villaggio
  (*Rinforzo del Granaio Comune*, *Cavalletto della Segheria*, *Armatura del Banco di Pietra*,
  *Manutenzione del Pozzo*) che migliorano la resa produttiva (`+1` per lotto) o il benessere.
* **Pannello economico** (`EconomyPanel`, a sinistra sotto `WorldHud`): mostra scorte disponibili,
  produzione e consumo del periodo (`+prod / -cons`), stato dei progetti, carenze attive e ultime
  transazioni importanti leggendo direttamente `EconomySystem`.

### Costo misurato della scena

Misura della fase precedente, avviando la scena con Godot 4.7.2 headless
(`--script res://tests/run_world_tests.gd`). Il villaggio non è cambiato in questa fase: cambiano
solo le capsule degli abitanti, che sono viste temporanee create entro `npc_view_distance` e
liberate fuori portata.

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
  npcs/                        simulazione degli abitanti (pura logica, nessun nodo)
    npc_personality.gd           tratti numerici 0..100
    npc_needs.gd                 energia, fame, benessere; pressione e serializzazione
    npc_place.gd                 luogo logico: tipo, posizione, orari, cibo
    npc_place_registry.gd        indice dei luoghi e ricerche deterministiche
    npc_record.gd                stato di un abitante: identità, spazio, obiettivo, relazioni
    npc_roster.gd                tabella fissa di 16 abitanti, nomi stabili
    npc_route_graph.gd           rete di waypoint su strade e luoghi, con ostacoli reali
    npc_simulation_system.gd     macchina a stati delle routine, movimento, bisogni
  economy/                     economia locale e ciclo delle risorse (pura logica, nessun nodo)
    resource_type.gd             tipi di risorsa (cibo, legno, pietra, moneta), prezzi e soglie
    resource_inventory.gd        inventario intero non negativo con operazioni atomiche
    economy_transaction.gd       registro tipizzato delle transazioni e dei rifiuti
    economy_rules.gd             regole di produzione, prerequisiti, progetti e riepiloghi
    economy_system.gd            sistema economico deterministico (produzione, consumo, scambi)
  world/                       mondo 3D
    scenes/main_world.tscn       scena principale
    main_world.gd                radice di composizione: terreno, villaggio, abitanti, spawn
    terrain_generator.gd         height field deterministico (mesh + heightmap di collisione)
    player_explorer.gd           esploratore in prima persona (CharacterBody3D)
    npcs/
      village_npc_places.gd      dal piano del villaggio ai luoghi della simulazione
      npc_presenter.gd           capsule, nomi, selezione con raycast, culling
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
    scenes/npc_panel.tscn        scheda dell'abitante selezionato
    npc_panel.gd
    scenes/economy_panel.tscn    pannello economico del villaggio
    economy_panel.gd
tests/
  run_tests.gd                 runner di unità (exit code 0/1)
  run_world_tests.gd           runner di integrazione (avvia la scena, interroga la fisica)
  harness/test_harness.gd      micro harness di asserzioni
  unit/                        clock, loop, day cycle, terreno, config, layout, aree,
                               materiali, baker, direzione artistica, dati NPC, roster,
                               rete di percorso, simulazione NPC, luoghi del villaggio,
                               inventari/transazioni ed economia simulata
  integration/
    test_world_scene.gd        scena, terreno vs fisica, collisioni, budget, abitanti,
                               selezione, pannello NPC e pannello economico
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

### Verifiche eseguite su questa fase

Il motore **Godot 4.7.2-stable** è stato compilato dai sorgenti in questa sessione (build headless
`linuxbsd`, senza X11, Wayland né driver grafici) e usato per eseguire davvero entrambe le suite.
Nessun numero qui sotto è stimato.

| Controllo | Strumento | Esito |
| --- | --- | --- |
| Sintassi di tutti i 59 script GDScript di `src/` e `tests/` | `gdparse` (gdtoolkit 4.5.0) | **eseguito — OK** |
| Stile GDScript | `gdlint` (gdtoolkit 4.5.0) | **eseguito — 0 problemi** |
| Coerenza progetto: scena principale, autoload, `res://`, ext/sub resource, percorsi `$Nodo` degli script rispetto alle scene, azioni di input, `.gitignore` | `tools/check_project.py` | **eseguito — OK** |
| Suite di unità headless (`tests/run_tests.gd`) | Godot 4.7.2 headless | **eseguito — 918 passati, 0 falliti, 0 saltati** |
| Suite di integrazione (`tests/run_world_tests.gd`) | Godot 4.7.2 headless | **eseguito — 96 passati, 0 falliti, 0 saltati** |
| Resa visiva su GPU (come *appare* il villaggio e come si muovono le capsule) | — | **NON eseguita**: l'ambiente di verifica non ha GPU. Geometria, materiali e collisioni sono verificati; l'immagine finale no |
| Prova su Windows con Godot desktop, selezione col mouse e pannello | — | **NON eseguita**: da fare in revisione |

`bash tools/run_checks.sh` esegue tutti e cinque i controlli e termina con
`All executed checks passed.` (in questa sessione: 918 + 96 asserzioni, zero errori di script).

I controlli statici non sostituiscono l'esecuzione: coprono sintassi, stile, percorsi delle risorse
e coerenza dei nodi, non il comportamento. La suite di unità contiene le prove di determinismo,
bisogni, routine, movimento continuo e luoghi; la suite di integrazione contiene le prove di
selezione, pannello e simulazione senza viste.

```bash
bash tools/run_checks.sh
```

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
* **budget**: draw call, triangoli e collider restano entro i limiti dichiarati (il conteggio
  esclude le capsule degli abitanti, che sono viste temporanee).
* **abitanti** (`check_npcs`): la popolazione segue `npc_population_size`, gli ID sono unici e i
  nomi stabili; i bisogni evolvono con `Game.advance_simulation()`; con `render_distance` a 0
  nessuna capsula è disegnata eppure i record continuano a cambiare; la selezione dal presenter
  arriva al pannello, che mostra nome, attività, obiettivo, barre e riepilogo del personaggio
  scelto; un ID inesistente viene rifiutato senza cambiare la selezione.

### Difetti reali trovati eseguendo il motore nella fase precedente

La fase precedente dichiarava i test "scritti ma non eseguiti". Eseguendoli sono emersi tre bug
(riguardano il terreno e il loop del tempo, non gli abitanti):

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

### Difetti reali trovati eseguendo il motore in questa fase

1. **Un errore di parsing che solo il motore vede.** `npc_route_graph.gd` conteneva
   `var current := queue.pop_back()`: `pop_back()` restituisce un `Variant` e Godot tratta
   l'inferenza da `Variant` come errore, quindi il motore rifiutava l'intero script (e a cascata
   `NpcSimulationSystem`, `Game` e la scena). `gdparse` e `gdlint` non lo segnalano, perché la
   sintassi è valida: è la prova che i controlli statici non sostituiscono l'esecuzione. Corretto
   con un tipo esplicito.
2. **Uno steccato tagliava la strada dei campi.** Il recinto del paddock attraversava la strada
   sud-ovest con un box di collisione di 3 m: il giocatore non poteva raggiungere i campi e il
   grafo dei percorsi segnalava `work_field` come irraggiungibile. Il layout ora lascia un cancello
   aperto sulla carreggiata, e `test_village_layout` verifica che nessuno steccato la ostruisca.
3. **Precedenza degli operatori in una stringa di log.** `_build_summary()` concatenava due
   stringhe e applicava `%` solo alla seconda: all'avvio il motore stampava
   "String formatting error". Ora la stringa viene composta prima di essere formattata.
4. **Il runner di integrazione non poteva nominare gli autoload.** Il suo script è compilato prima
   che `Game` e `EventBus` esistano: i riferimenti statici fallivano e la scena si costruiva a
   metà (niente giocatore, niente presentatore, niente pannello). Ora il modulo di test viene
   caricato a runtime dopo il primo frame e l'autoload è risolto tramite l'albero.
5. **`null` in `ARRAY_INDEX`.** Il conteggio dei triangoli del budget chiamava `is_empty()` su
   `null` per le mesh non indicizzate, generando un errore di script a ogni superficie. Corretto:
   il conteggio ora include anche quelle superfici.

## 8. Limiti noti di questa fase

* **Economia locale a prezzi base fissi**: sono implementati inventari, produzione da lavoro,
  consumo alimentare, scambi tramite mercante e progetti comunitari; **non** esistono ancora prezzi
  dinamici da domanda/offerta complessa, prestiti, debito, tassazione o mercati multi-insediamento.
* **Nessuna simulazione sociale o politica**: relazioni e ricordi esistono come dati iniziali (e
  sono serializzati), ma nessuna regola li modifica ancora. Non ci sono fazioni, leggi, cronache o
  eventi politici.
* **La memoria non è un sistema**: i ricordi sono un elenco seminato, non un registro che cresce
  con le azioni.
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
