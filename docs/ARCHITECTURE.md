# Architettura tecnica — EVERAFTER

Questo documento descrive l'architettura del progetto **così com'è implementata**, con l'intento
delle parti ancora da costruire separato e dichiarato come tale.

Il gioco è costruito con **Godot 4** e **GDScript tipizzato**. L'obiettivo architetturale è
sostenere una simulazione di popolazione persistente, deterministica e offline, in un mondo
3D esplorabile, senza dipendere da server o servizi online a pagamento.

## Principi architetturali

1. **Determinismo prima, realismo dopo.** La simulazione usa il proprio orologio e numeri interi
   o float controllati, mai `Time.get_ticks_msec()`. A parità di stato iniziale e di seed, lo
   stesso numero di tick produce lo stesso stato.
2. **Il mondo persiste indipendentemente dal giocatore.** La simulazione avanza per logica, non
   per rendering. Le entità lontane non vengono cancellate: sono simulate con un livello di
   dettaglio inferiore.
3. **Separazione tra simulazione e presentazione.** `simulation/` non conosce mesh, animazioni,
   materiali o input. Il mondo 3D e l'interfaccia osservano e reagiscono.
4. **Dati guidano la simulazione.** Professioni, bisogni, edifici, prezzi e regole sono dati
   modificabili (`config/`, risorse, tabelle), non costanti sparse nel codice.
5. **Nessuna dipendenza online obbligatoria.** Il gioco completo deve funzionare offline.
   L'IA generativa può solo arricchire descrizioni, dialoghi o cronache, e resta disattivabile.
6. **Semplice finché basta.** Nessun ECS, ORM o motore di regole personalizzato nella prima fase:
   si usano nodi, risorse e dizionari di Godot.
7. **Niente asset binari nel repository.** Tutto ciò che il progetto contiene è testo (script,
   scene, `.tres`, `.svg`) oppure generato a runtime dal codice. Questo mantiene il clone piccolo,
   le revisioni leggibili e il progetto riproducibile senza asset pipeline.
8. **Non dichiarare mai un comportamento come funzionante senza averlo eseguito.** Le verifiche
   statiche sono ammesse solo dichiarando esplicitamente che il motore non è stato eseguito.

## Moduli implementati

| Modulo | Responsabilità |
| --- | --- |
| `core/` | orologio simulato (`SimulationClock`), `GameConfig` e `game_log`, singleton `EventBus` e `Game` |
| `simulation/` | contratto `SimulationSystem`, `SimulationLoop` a fixed timestep, `DayCycleSystem` |
| `world/` | scena principale, generatore di terreno, esploratore in prima persona, costruzione del villaggio, registro delle aree |
| `ui/` | HUD del mondo (titolo, giorno, area) e pannello diagnostico |
| `tests/` | harness di asserzioni, runner di unità, runner di integrazione, suite di unità e di integrazione |
| `tools/` | verifiche statiche di coerenza del progetto, script che esegue tutti i controlli |
| `config/` | `game_config.tres`, i valori di tuning modificabili senza toccare il codice |

### Moduli previsti, non ancora presenti

`npc/`, `social/`, `economy/`, `governance/`, `history/`, `memory/`, `events/`, `persistence/`,
`ai/` sono descritti in `ROADMAP.md`. **Nessuno di questi esiste nel codice.** Questo documento
non li elenca tra i moduli attivi, perché un'architettura che dichiara moduli inesistenti è più
pericolosa di un'architettura incompleta.

## Dipendenze consentite

```
core  ->  niente
simulation  ->  core
world  ->  core, simulation
ui  ->  core, simulation, world
tests  ->  tutto (ma senza dipendere da una GPU)
```

Regole operative:

* `simulation/` non conosce né la scena 3D né l'interfaccia. Comunica tramite `EventBus` e metodi
  espliciti, e si fa iniettare il proprio `SimulationClock` (mai lo singleton) così da essere
  testabile in isolamento.
* Il mondo 3D osserva la simulazione e non la pilota.
* Nessun sistema salva in file direttamente: esiste un unico modulo di persistenza (da scrivere).
* Ogni sistema deve poter funzionare anche senza rendering.
* Le suite di test devono poter girare headless, senza GPU e senza autoload obbligatori.

## Simulazione

* Il tempo avanza a **tick logici fissi**: 1 tick = 60 secondi di gioco.
* `SimulationLoop` usa il **tempo simulato accumulato**, non i frame renderizzati.
* La velocità di gioco (x1, x3, x10) moltiplica l'avanzamento logico senza cambiare il tick.
* Il ciclo giorno/notte è pilotato da `DayCycleSystem`, non dall'ora reale.
* `max_steps_per_frame` limita i tick per frame: se il gioco resta in pausa a lungo o il frame
  dura molto, l'accumulatore non genera migliaia di tick in un solo fotogramma. Questo guard è
  considerato comportamento corretto e coperto da un test.
* I sistemi sono **puri nel tempo**: ricevono `delta_seconds` e l'orologio, restituiscono niente,
  modificano il proprio stato. Questo rende ogni sistema testabile con un orologio sintetico.

## Mondo 3D

Il mondo è costruito **interamente a codice**, senza asset binari, partendo da primitive.

* **`VillageLayout`** è il piano del villaggio: strade, lotti, oggetti, pesi del terreno. È
  costruito da un seme, è **pura dati** e non tocca né nodi né risorse. È la singola fonte di
  verità condivisa da terreno, edifici e registro delle aree: se la piazza si sposta, si sposta
  tutto insieme.
* **`TerrainGenerator`** produce un height field deterministico (value noise a più ottave) e
  consegna **due cose coerenti**: la mesh visibile e la `HeightMapShape3D` di collisione. Le
  strade e le aree edificate appiattiscono solo le ottave di dettaglio (`flatten_weight`), così
  un sentiero è percorribile senza scavare una trincea nelle colline.
* **`MeshBaker`** fonde primitive in **una mesh per materiale**. È il motivo per cui un villaggio
  di centinaia di solidi costa 145 draw call invece di migliaia.
* **`VillageMaterials`** è una palette unica di materiali condivisi. La variazione cromatica tra
  oggetti identici passa dai colori per vertice, non da materiali diversi.
* **`BuildingFactory`** e **`VegetationBuilder`** scrivono su un baker; **`VillageBuilder`**
  assembla il villaggio e i suoi collider.
* **`AreaRegistry`** è pura dati: cerchi e corridoi con priorità, che rispondono a "che zona è
  questa?" senza sapere che esiste un giocatore.

Regole di costruzione:

* Ogni entità ha **collisione reale**, non mesh decorative attraversabili.
* **Le mesh sono unite per materiale.**
* L'erba e gli oggetti ripetuti usano **`MultiMesh`**.
* **Una sola luce proietta ombre** (`DirectionalLight3D` del sole, `directional_shadow_max_distance
  = 130`); la luce di riempimento no. SSAO e glow sono disattivati.
* **Lod e streaming** (chunk, occlusion culling, distance culling) non sono implementati e sono
  dichiarati come lavoro futuro: al costo attuale della scena non servirebbero, e aggiungerli ora
  sarebbe complessità senza un problema da risolvere.

### Winding order: la convenzione misurata, non ricordata

Godot 4.7.2 ricava la normale di un triangolo `(a, b, c)` come **`(c − a) × (b − a)`**. È stato
misurato sul motore, perché la fase precedente aveva costruito il terreno con l'ordine opposto e
tutte le normali puntavano verso il basso: con il back-face culling attivo il suolo sarebbe
sparito visto dall'alto, e nessun controllo statico lo segnalava.

`MeshBaker` rispetta quella convenzione e `tests/unit/test_mesh_baker.gd` la verifica su ogni
solido (box, cilindro, sfera) controllando che il verso ricavato dalla geometria coincida con la
normale scritta **e** punti verso l'esterno.

## Rendering

**Renderer: `forward_plus`.**

* Una GTX 1060 gestisce Vulkan senza difficoltà; la scena misura 145 draw call e ~108.000
  triangoli, molto al di sotto della soglia critica per quella scheda a 1080p.
* `forward_plus` resta il percorso più mantenuto del motore e offre il debugging migliore, quindi
  è la base più stabile per le fasi successive.
* La compatibilità è un'impostazione, non del codice: `mobile` e `gl_compatibility` si attivano da
  *Project Settings → Rendering → Renderer* e **nessuna riga di codice dipende dal renderer**.

Target dichiarato: **1080p a 60 fps su GPU classe GTX 1060**. Il budget è difeso da un test
(`PerformanceBudget`), non solo da una dichiarazione.

## Interfaccia

* HUD minimale e coerente con il tono del gioco; il pannello diagnostico parte nascosto (F1).
* L'interfaccia mostra **stato leggibile** (giorno simulato, ora, area) e non numeri di debug nel
  flusso normale.
* Gli input sono tutti mappati come **azioni** in `project.godot`, mai come tasti fisici negli
  script, quindi sono rimappabili senza toccare il codice.
* Il mouse si libera con `Esc` e si riprende con clic sinistro o `F`; lo stato è pubblicato su
  `EventBus.mouse_capture_changed` così l'interfaccia lo comunica invece di lasciarlo indovinare.

## Dati e persistenza

* Nessun save in questa fase. `SimulationClock`, `SimulationLoop` e i sistemi espongono
  `to_dict()` / `from_dict()` per prepararne una, ma il modulo `persistence` non esiste ancora.
* Gli ID saranno **UUID** quando esisteranno le entità.
* La versione del save è prevista per la migrazione dei dati; non è ancora necessaria.

## IA generativa

* L'IA generativa **non è integrata** e non è richiesta per giocare.
* Se verrà integrata, servirà solo per descrizioni, dialoghi, cronache o testo.
* La logica di gioco resta deterministica e locale.
* L'accesso online è esplicito, documentato e disattivabile.

## Qualità del codice

* GDScript **tipizzato**.
* Nome di classe con `class_name`, docstring `##` in cima a ogni script.
* Nessun `@onready` che catturi un nodo prima che esista: la scena è costruita in `_ready()`
  secondo un ordine esplicito, e le dipendenze sono iniettate dai costruttori.
* Ogni sistema è testabile in isolamento; le suite girano headless, senza GPU e senza autoload.
* Prima di ogni modifica: `bash tools/run_checks.sh`.

## Verifiche

Tre livelli, dal più economico al più convincente.

1. **Statico** (`tools/check_project.py`, `gdparse`, `gdlint`): coerenza di percorsi, scene,
   risorse, riferimenti `$Nodo` degli script rispetto alle scene reali, azioni di input. Non
   esegue una riga di codice di gioco.
2. **Unità** (`tests/run_tests.gd`): classi pure, nessuna scena, nessuna GPU. Orologio, loop,
   day cycle, terreno, layout, aree, materiali, baker, direzione artistica.
3. **Integrazione** (`tests/run_world_tests.gd`): avvia la scena principale e interroga il server
   fisico. Confronta la superficie fisica con l'height field, verifica che il giocatore stia in
   piedi e non affondi, spinge la **capsula reale** contro un **edificio reale**, controlla il
   budget di draw call, triangoli e collider.

Regola di progetto: il livello 3 è obbligatorio per qualunque modifica che tocchi mondo, terreno o
giocatore. È il livello che ha trovato i tre bug reali della fase precedente.
