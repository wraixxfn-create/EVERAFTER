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
| `npcs/` | dati e simulazione degli abitanti: personalità, bisogni, luoghi, record, roster, rete di percorso, macchina a stati |
| `economy/` | economia locale e ciclo delle risorse: tipi di risorsa (`food`, `wood`, `stone`, `coin`), inventari non negativi con operazioni atomiche, registro transazioni, regole di produzione/consumo/scambio/progetti ed `EconomySystem` |
| `social/` | relazioni a coppie, interazioni sociali, memoria individuale limitata e registro oggettivo degli eventi: `RelationshipGraph`, `MemoryBook`, `SocialRules`, `SocialSystem` |
| `world/` | scena principale, generatore di terreno, esploratore in prima persona, costruzione del villaggio, registro delle aree, ponte verso i luoghi degli NPC |
| `world/npcs/` | presentazione degli abitanti: capsule, nomi, selezione, culling; nessuna scrittura sui record |
| `ui/` | HUD del mondo (titolo, giorno, area), pannello economico (`EconomyPanel`), pannello diagnostico e scheda dell'abitante (`NpcPanel`) |
| `tests/` | harness di asserzioni, runner di unità, runner di integrazione, suite di unità e di integrazione |
| `tools/` | verifiche statiche di coerenza del progetto, script che esegue tutti i controlli |
| `config/` | `game_config.tres`, i valori di tuning modificabili senza toccare il codice |

### Moduli previsti, non ancora presenti

`governance/`, `history/`, `events/`, `persistence/`, `ai/` sono descritti in `ROADMAP.md`.
**Nessuno di questi esiste nel codice.** Questo documento non li elenca tra i moduli attivi, perché
un'architettura che dichiara moduli inesistenti è più pericolosa di un'architettura incompleta.
`npcs/`, `economy/` e `social/` invece esistono e costituiscono le fasi completate della
simulazione locale.

La memoria individuale, che la roadmap indicava come modulo `memory/`, vive **dentro** `social/`
(`npc_memory.gd` + `memory_book.gd`): un ricordo esiste solo come conseguenza di un evento sociale o
come background iniziale, e separare i due moduli avrebbe creato un confine senza comportamento.
Se in futuro servirà una memoria non sociale (luoghi visitati, mestiere appreso) il modulo nascerà
allora, con un motivo per esistere.

## Dipendenze consentite

```
core  ->  niente
simulation  ->  core
npcs  ->  core, simulation, economy (opzionale, iniettato)
economy  ->  core, simulation, npcs
social  ->  core, simulation, npcs, economy (opzionale, iniettato)
world  ->  core, simulation, npcs, economy, social
world/npcs  ->  core, npcs, world
ui  ->  core, simulation, npcs, economy, social, world
tests  ->  tutto (ma senza dipendere da una GPU)
```

`npcs/` è **pura logica**: non importa `Node`, `Node3D`, `Camera3D` né `TerrainGenerator`. L'unico
punto in cui il piano 3D del villaggio diventa dati per gli NPC è
`src/world/npcs/village_npc_places.gd`: conosce sia `VillageLayout` sia `NpcPlace`, e produce un
`NpcPlaceRegistry` e una lista di ostacoli. Così la posizione dei luoghi resta quella reale del
villaggio, ma la simulazione non dipende dalla scena.

Regole operative:

* `simulation/` non conosce né la scena 3D né l'interfaccia. Comunica tramite `EventBus` e metodi
  espliciti, e si fa iniettare il proprio `SimulationClock` (mai lo singleton) così da essere
  testabile in isolamento.
* Il mondo 3D osserva la simulazione e non la pilota.
* `social/` legge `npcs/` ed `economy/` ma **non scrive nei record** se non il benessere, con una
  regola documentata: lo stato sociale ha un solo proprietario, il `SocialSystem`.
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
* I sistemi sono **puri nel tempo**: ricevono il numero di tick e l'orologio, restituiscono niente,
  modificano il proprio stato. Questo rende ogni sistema testabile con un orologio sintetico.

## Simulazione degli abitanti

La popolazione vive in `src/npcs/` e non ha alcun nodo. Il contratto con il resto dell'applicazione
è un `Array[NpcRecord]` più un `NpcPlaceRegistry` e un `NpcRouteGraph`.

### Dati

* **`NpcPersonality`**: quattro interi 0..100 (diligenza, socievolezza, curiosità, calma).
* **`NpcNeeds`**: tre float 0..100. Per la fame **100 significa affamato**, per energia e
  benessere **100 significa pieno**. `get_pressure()` è la media normalizzata usata per i
  riepiloghi.
* **`NpcPlace`**: id, nome, tipo (`HOME`, `WORK`, `FOOD`, `REST`, `SOCIAL`, `LEISURE`), posizione
  XZ, orario di apertura (con supporto alla mezzanotte), disponibilità di cibo, capienza futura.
* **`NpcPlaceRegistry`**: indice per id e ricerche deterministiche (primo luogo aperto, filtrato
  per tipo). Non contiene nodi.
* **`NpcRecord`**: identità, età, professione, personalità, bisogni, casa, lavoro, posizione,
  destinazione, percorso, obiettivo, attività, relazioni e ricordi. `to_dict()` / `from_dict()`
  copiano anche relazioni e ricordi, per la futura persistenza.
* **`NpcRoster`**: tabella fissa di 16 abitanti. `build(n)` restituisce sempre i primi `n`, con gli
  stessi nomi, mestieri e orari: è ciò che rende i nomi stabili tra un avvio e l'altro. Il numero
  richiesto viene da `GameConfig.npc_population_size`; il roster non legge la configurazione e non
  contiene codice di scena.

### Regole

Un solo metodo (`on_tick`) aggiorna **tutti** i record. Per ogni abitante:

1. i bisogni avanzano in base all'attività corrente (lavoro, cammino, sonno, pasto, socialità,
   attesa) e il benessere deriva verso un valore obiettivo legato alla calma;
2. una macchina a stati esplicita decide l'azione successiva:
   * fame urgente (≥ 88) o energia urgente (≤ 7): cerca cibo o riposo;
   * dentro il proprio turno: mangia se la fame è ≥ 62, altrimenti va a lavorare;
   * tra le 22:00 e le 06:00: va a dormire a casa;
   * fame ≥ 62: cerca cibo; energia ≤ 28: riposa;
   * altrimenti tempo libero: un luogo sociale aperto, alternato a una passeggiata in base al
     cursore `leisure_cursor` e alla socievolezza;
3. il movimento avanza lungo il percorso di `NpcRouteGraph` di al massimo
   `WALK_DISTANCE_PER_TICK` unità per tick. **La posizione non viene mai assegnata alla
   destinazione**: si muove solo il cursore sul percorso. Se il percorso è vuoto, il record entra
   in `BLOCKED` per tre tick e il problema viene registrato una volta sola;
4. un luogo irraggiungibile non viene scelto: la ricerca filtra con `is_place_reachable()`. Se non
   esiste alcun luogo di riposo raggiungibile, l'abitante dorme dove si trova; se non c'è cibo,
   aspetta e riprova. Non viene mai teletrasportato;
5. le decisioni non usano `randf()`, `Time`, delta di frame né ordine di iterazione di un
   `Dictionary`. Lo stesso stato iniziale e lo stesso numero di tick danno lo stesso `to_dict()`.

### Separazione dalla scena

`NpcPresenter` e `NpcPanel` sono **lettori**. Il presenter crea capsule solo entro
`npc_view_distance`; quando un record esce dal raggio, il nodo viene liberato, ma il record
continua ad avanzare nello stesso loop di simulazione. La selezione nasce da un raycast contro i
corpi degli NPC (layer `1 << 3`, maschera vuota: il giocatore ci cammina attraverso) oppure
dall'elenco nel pannello; entrambi pubblicano `EventBus.npc_selected`.

### Tempo

L'avanzamento è quello di `SimulationLoop`: un tick = un minuto simulato. `Game.advance_simulation(n)`
esegue `n` tick senza frame, ed è il punto di aggancio già pronto per il futuro "tempo trascorso
mentre il giocatore era assente". La simulazione non dipende dal frame rate: un frame può produrre
più tick (fino a `max_steps_per_frame`) o nessuno.

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
* Il pannello degli abitanti (`NpcPanel`) è un `CanvasLayer` con un `OptionButton` e barre dei
  bisogni. Legge `Game.get_npc_system()` e ascolta `EventBus.npc_system_ready` /
  `EventBus.npc_selected`; non possiede stato di simulazione. Se l'abitante selezionato non ha una
  capsula 3D, il pannello continua a mostrarne i dati live: è la prova visibile della separazione
  simulazione/rendering.
* Il pannello economico (`EconomyPanel`) è anch'esso un `CanvasLayer` in sola lettura, ancorato a
  sinistra sotto `WorldHud`. Legge direttamente `Game.get_economy_system()` senza mantenere
  contatori indipendenti che possano divergere dallo stato reale.

---

## Sistema economico locale (`src/economy/`)

`src/economy/` è un modulo puro (`RefCounted`, nessun `Node`, nessuna dipendenza dal rendering)
registrato nel `SimulationLoop` immediatamente dopo `NpcSimulationSystem`.

### 1. Risorse, prezzi base e soglie di carenza (`ResourceType`)

Tutte le quantità sono **interi non negativi (`int >= 0`)** conservati in `ResourceInventory`:

| ID | Etichetta | Prezzo base (`Moneta`) | Soglia carenza villaggio | Ruolo |
| --- | --- | --- | --- | --- |
| `food` | Cibo | `2` | `< 8` | Consumato dagli abitanti durante i pasti |
| `wood` | Legno | `3` | `< 4` | Materiale per progetti comunitari e scambi |
| `stone` | Pietra | `4` | `< 4` | Materiale per progetti comunitari e scambi |
| `coin` | Moneta | `1` | `< 6` | Mezzo di scambio per compensi, pasti, acquisti e progetti |

### 2. Inventari e atomicità delle transazioni (`ResourceInventory`, `EconomySystem`)

* **Magazzino del villaggio (`village`)**: scorte iniziali da `GameConfig` (`24 Cibo`, `12 Legno`,
  `10 Pietra`, `60 Moneta`).
* **Sacche individuali (`npc_001` … `npc_016`)**: usate per i compensi di lavoro, l'acquisto dei
  pasti e piccole scorte personali (`0` materiali iniziali, `4 Moneta` ciascuno).
* **Emporio del mercato (`market`)**: inventario finito di controparte per il commerciante
  (`12 Cibo`, `10 Legno`, `8 Pietra`, `50 Moneta`).
* **Validazione rigorosa**: `set_amount`, `add`, `remove`, `add_bundle`, `remove_bundle`,
  `transfer_resource`, `execute_trade`, `execute_barter` e `fund_project` convalidano tutti i
  parametri prima di toccare lo stato. Qualsiasi operazione non valida (quantità `<= 0`, risorsa
  sconosciuta, fondi/scorte insufficienti, proprietario inesistente) viene **rifiutata senza
  effetti collaterali**, incrementando `rejected_transaction_count` e registrando una transazione
  `KIND_REJECTED`. Non vengono mai assegnate risorse casuali o gratuite per mascherare una
  produzione insufficiente.

### 3. Formule di produzione e prerequisiti (`EconomyRules`)

Ad ogni tick (`1` minuto simulato), un abitante accumula `+1` minuto di lavoro (`_work_progress`)
**solo se tutte** le condizioni seguenti sono vere (`can_worker_produce_now`):

1. `record.activity == NpcRecord.Activity.WORKING` e `record.current_place_id == record.workplace_id`;
2. il prerequisito della postazione (`_workplace_prerequisites[workplace_id].ready`) è `true`;
3. `record.needs.hunger < 92.0` (`MAX_WORKER_HUNGER_FOR_PRODUCTION`) e
   `record.needs.energy > 5.0` (`MIN_WORKER_ENERGY_FOR_PRODUCTION`).

Se un lavoratore dorme, cammina, riposa per stanchezza, cerca cibo o ha la postazione non pronta,
**non accumula progresso e non produce**.

Quando `_work_progress[npc_id] >= minutes_per_batch`, viene sottratto `minutes_per_batch` e il
magazzino del villaggio riceve `batch_amount + bonus_progetti`:

| Professione (`profession_id`) | Luogo (`workplace_id`) | Prerequisito documentato | `minutes_per_batch` | Lotto base | Compenso per lotto |
| --- | --- | --- | --- | --- | --- |
| `farmer` (Agricoltore) | `work_field` | Campi arati e attrezzi agricoli | `60` min | `+3 Cibo` | `2 Moneta` |
| `forager` (Raccoglitrice) | `work_garden` | Orto recintato ed essiccatoio | `60` min | `+2 Cibo` | `1 Moneta` |
| `fisher` (Pescatore) | `work_pond` | Pontile dello stagno e reti | `60` min | `+2 Cibo` | `1 Moneta` |
| `baker` (Panettiera) | `work_inn` | Forno e dispensa della locanda | `60` min | `+2 Cibo` | `1 Moneta` |
| `innkeeper` (Locandiera) | `work_inn` | Forno e dispensa della locanda | `75` min | `+2 Cibo` | `1 Moneta` |
| `woodcutter` (Boscaiolo) | `work_workshop` | Cavalletto da taglio e asce | `60` min | `+2 Legno` | `2 Moneta` |
| `quarry_worker` (Cavatore) | `work_forge` | Banco d'estrazione, cunei e picconi | `60` min | `+2 Pietra` | `2 Moneta` |
| `merchant` (Commerciante) | `work_market` | Banco dei pesi e registro | `60` min | *Scambio* | — |

Il compenso viene trasferito dalla cassa comune (`village`) alla sacca dell'abitante solo se il
villaggio dispone delle monete necessarie (nessuna creazione di moneta dal nulla).

### 4. Formule di consumo alimentare e carenze

* **Razione per pasto**: `FOOD_UNITS_PER_MEAL = 1 Cibo`, costo `MEAL_PRICE_COIN = 2 Moneta`.
* **Quando avviene**:
  1. all'ingresso in `Activity.EATING` presso un luogo con `provides_food == true` (es. locanda o
     casa), tramite `EconomySystem.request_meal_for_npc(record, tick)`;
  2. alle `19:00` (`DAILY_RATION_MINUTE = 1140`), se l'abitante non ha ancora consumato una razione
     nella giornata corrente (`_ate_today`).
* **Ordine di prelievo**: prima dalla sacca personale dell'abitante (`>= 1 Cibo`), altrimenti dal
  magazzino del villaggio (`>= 1 Cibo`), versando fino a `2 Moneta` dalla sacca dell'abitante alla
  cassa del villaggio.
* **Effetto della scarsità di cibo (`0 Cibo` disponibile)**:
  * il pasto viene rifiutato (`last_meal_satisfied = false`), `unfed_meal_attempts_period` e
    `unfed_meal_attempts_total` aumentano di `1`, e le scorte restano a `0`;
  * il benessere cala immediatamente di `-4,5` (`UNFED_WELLBEING_PENALTY`);
  * durante i tick di `Activity.EATING` senza razione, la fame non può scendere sotto `76,0`
    (`UNFED_HUNGER_FLOOR`, solo lieve sollievo con acqua/riposo a `-0,25/min` invece di
    `-2,8/min`) e il benessere subisce una deriva negativa aggiuntiva di `-0,08/min`;
  * **nessun abitante muore** e i bisogni restano sempre nell'intervallo `[0, 100]`.

### 5. Formule di scambio e ruolo del commerciante

* **Acquisto a prezzo base fisso (`execute_trade`)**:
  `costo_totale = quantità * ResourceType.base_price(resource_id)`. Richiede che il venditore
  possieda `>= quantità` della risorsa e il compratore `>= costo_totale` in `Moneta`.
* **Baratto (`execute_barter`)**: scambia `give_amount` di `give_resource` contro `receive_amount`
  di `receive_resource` tra due inventari distinti dopo aver verificato entrambe le disponibilità.
* **Intermediazione del commerciante (`_run_merchant_brokerage`)**: ogni `60` minuti lavorati al
  mercato (`work_market`), il commerciante:
  1. trasferisce o acquista eventuali materiali presenti nelle sacche degli abitanti verso il
     magazzino del villaggio;
  2. se il villaggio ha `< 16 Cibo` e l'emporio (`market`) ha `>= 2 Cibo`, acquista `2 Cibo` per
     `4 Moneta` (o baratta `1 Pietra` per `2 Cibo` se il villaggio ha `>= 6 Pietra`);
  3. se il villaggio ha eccedenze (`> 16 Legno` o `> 14 Pietra`) e l'emporio ha moneta, vende `2`
     unità all'emporio al prezzo base (`6` o `8 Moneta`).
  In ogni caso la somma totale di `Cibo`, `Legno`, `Pietra` e `Moneta` nel sistema (`village +
  market + sacche NPC`) **resta invariata** (legge di conservazione verificata dai test).

### 6. Progetti comunitari (`CommunityProject`)

Alle `18:00` (`PROJECT_CHECK_MINUTE = 1080`) o tramite `fund_project(project_id, tick)`, il
villaggio può finanziare in ordine i progetti comunitari (mantenendo in automatico una riserva di
sicurezza di `4 Legno`, `4 Pietra`, `12 Moneta`):

1. **Rinforzo del Granaio Comune** (`granary_repair`): costo `6 Legno, 4 Pietra, 8 Moneta` →
   `+1 Cibo` per ogni lotto agricolo/alimentare e `+2,0` benessere a tutti gli abitanti.
2. **Cavalletto e Tettoia della Segheria** (`logging_trestle`): costo `4 Legno, 4 Pietra, 6 Moneta`
   → `+1 Legno` per ogni lotto del boscaiolo e `+1,5` benessere.
3. **Armatura del Banco di Pietra** (`quarry_shoring`): costo `6 Legno, 2 Pietra, 8 Moneta` →
   `+1 Pietra` per ogni lotto di estrazione e `+1,5` benessere.
4. **Manutenzione del Pozzo e della Piazza** (`well_maintenance`, ripetibile): costo
   `4 Legno, 4 Pietra, 4 Moneta` → `+3,0` benessere a tutti gli abitanti.

### 7. Regole implementate vs funzionalità future

| Aspetto | Già implementato (`0.4.0-economy`) | Futuro (non ancora implementato) |
| --- | --- | --- |
| Risorse e inventari | `Cibo`, `Legno`, `Pietra`, `Moneta` intere non negative; magazzino villaggio, emporio e sacche NPC | Materie prime secondarie, utensili usurabili, logistica di trasporto fisico |
| Produzione | Lotti orari legati a `Activity.WORKING`, luogo effettivo, prerequisiti postazione e bisogni | Stagionalità dei raccolti, catene multi-stadio (grano → farina → pane), qualità |
| Consumo e scarsità | `1 Cibo` a pasto; carenze che riducono benessere e lasciano gli abitanti affamati senza mortalità | Malattie, emigrazione o mortalità opzionale in fasi avanzate |
| Prezzi e mercato | Prezzi base fissi (`2, 3, 4`), baratto convalidato e intermediazione conservativa del mercante | Prezzi dinamici guidati da domanda/offerta, aste, rotte commerciali esterne |
| Progetti comunitari | 4 progetti con costi in `Legno`, `Pietra`, `Moneta` e bonus di resa/benessere | Costruzione fisica di nuovi edifici 3D tramite cantieri multi-giorno |
| Relazioni e politica | Strutture dati iniziali in `NpcRecord` | Evoluzione delle relazioni, fazioni, tasse, leggi e cronache (`Fase 3+`) |

## Sistema sociale (`src/social/`)

Prima versione **persistente e deterministica** delle relazioni personali e della memoria degli
abitanti. Nessuna chiamata di rete, nessun modello linguistico: solo regole numeriche in
`social_rules.gd`, funzioni pure e costanti nominate. Il sistema è un `SimulationSystem` registrato
dopo `npc_life` ed `economy`, quindi a ogni tick legge una routine e delle scorte già aggiornate.

### 1. Identità di una relazione e duplicati

* Una relazione appartiene a una **coppia non ordinata** di ID. La chiave è canonica:
  `SocialRelationship.canonical_key(a, b)` ordina i due ID lessicograficamente e li unisce con `|`
  (`npc_001|npc_002`). Non esiste una seconda forma della stessa chiave.
* `RelationshipGraph` è l'**unico proprietario**. `create()` restituisce `null` e registra un errore
  se la coppia esiste già, se un ID è vuoto o se i due ID coincidono: nessun duplicato può entrare
  nel grafo, nemmeno da un file di salvataggio (`from_dict()` scarta la seconda occorrenza).
* Riferimenti a NPC inesistenti: `remove_orphans(known_ids)` elimina le relazioni con un membro
  sconosciuto e `validate(known_ids)` le segnala. Il caricamento di uno snapshot le pulisce prima di
  restituire il controllo.
* La scelta precedente — un dizionario simmetrico dentro ogni `NpcRecord` — è stata **rimossa**:
  due copie dello stesso legame possono divergere, e questa è la definizione di duplicato. Il
  record conserva solo `origin_note`, il background testuale che diventa il primo ricordo.

### 2. Attributi, intervalli e regole di aggiornamento

Tutti i valori sono interi in `0..100` (`SocialRelationship.VALUE_MIN/MAX`) e ogni scrittura passa
da `clamp_all()`.

| Attributo | Condivisione | Semantica |
| --- | --- | --- |
| `familiarity` | **condiviso** (un solo numero) | quanto si conoscono |
| `tension` | **condiviso** | quanto è teso il rapporto |
| `trust_a`, `trust_b` | **direzionale** (due numeri) | quanto A si fida di B e quanto B si fida di A |
| `affinity_a`, `affinity_b` | **direzionale** | quanto A vuole bene a B e viceversa |

La distinzione è sostanziale: ricevere aiuto aumenta **la fiducia di chi riceve** verso chi aiuta,
non il contrario. Per questo fiducia e affinità hanno due valori, mentre familiarità e tensione —
fatti della coppia, non di un lato — ne hanno uno.

Regole di aggiornamento (`gain_*`, `lose_*`, `shift_tension`), tutte con valore di ritorno pari al
cambiamento **effettivamente applicato**:

1. **Rendimenti decrescenti** — `scaled_gain(current, amount) = round(amount * (1 - current/100))`.
   A `0` il passo è pieno, a `90` vale un decimo, a `100` vale `0`.
2. **Tetto giornaliero condiviso** — `daily_gain_cap` (default `14`, configurabile) è il numero
   massimo di punti positivi che una coppia può guadagnare in un giorno simulato, **sommando
   familiarità, fiducia e affinità**. Il contatore si azzera al cambio di giorno.
3. **Nessun tetto sui peggioramenti** — `lose_trust`, `lose_affinity` e `shift_tension` sono sempre
   applicati: un litigio deve poter fare danno anche a fine giornata.

L'etichetta mostrata in UI (`kind_label()`) è **derivata** dai numeri, mai memorizzata: un'etichetta
salvata sarebbe una seconda fonte di verità in grado di contraddire i valori che descrive.

### 3. Interazioni: contesto, prossimità, attività

Un tick produce al massimo `MAX_INTERACTIONS_PER_TICK = 2` interazioni. I candidati devono:

* essere nello **stesso luogo** (`current_place_id`) e a distanza `<= interaction_radius` (3,2);
* non stare dormendo, camminando o recuperando da un percorso bloccato (`SocialRules.is_available`);
* non aver già interagito da meno di `cooldown_ticks` (45 minuti simulati).

L'ordine di scansione è fisso (ID di luogo ordinati, poi ordine di roster) e la coppia è
canonizzata (l'ID minore propone, l'altro risponde), quindi la stessa scena non viene mai ripetuta
con i ruoli invertiti. `decide_interaction()` valuta in questo ordine: **disaccordo** (stesso
posto di lavoro, entrambi al lavoro, carenza di cibo nel villaggio, fame `>= 72` di almeno uno,
calma media `< 70`), **aiuto** (luogo che serve cibo, uno senza razione o con fame `>= 78`,
l'altro con fame `<= 55`, energia `>= 20` e cibo realmente disponibile secondo
`EconomyRules.has_available_food_for`), **cooperazione** (entrambi al lavoro nello stesso posto),
**conversazione** o **saluto** (luogo sociale, soglia di familiarità `20`). Nessun dado: se le
condizioni non ci sono, non succede niente.

### 4. Evento oggettivo contro ricordo soggettivo

* `SocialEvent` è ciò che il mondo concorda sia accaduto: id (`evt_000042`), tipo, esito, tick,
  giorno, minuto, luogo, ID degli attori ordinati, iniziatore, descrizione, importanza `0..100`,
  effetti applicati. È immutabile e viene solo accodato.
* `NpcMemory` è ciò che un personaggio ne ha trattenuto: id (`mem_000107`), proprietario, tipo,
  `event_id`, giorno, altri partecipanti, luogo, **ruolo** (`ricevuto`, `offerto`, `rifiutato`,
  `condiviso`, `iniziato`), descrizione dal suo punto di vista, importanza propria, `source`
  (`diretto` / `raccontato`) e `certainty` (`0..100`).
* Lo stesso aiuto genera **due ricordi diversi** (importanza `58` per chi riceve, `40` per chi
  offre) che puntano allo stesso evento. `source` e `certainty` sono sempre `diretto` / `100` in
  questa fase: sono il punto d'aggancio già pronto per una prospettiva incompleta, senza che debba
  cambiare lo schema.

### 5. Limiti della memoria e regola di selezione

* `MemoryBook` ha una capacità per abitante (`social_memory_capacity`, default 24) e una soglia di
  importanza (`social_memory_importance_floor`, default 12). Un saluto (importanza 6) **non viene
  memorizzato**: l'evento esiste, il ricordo no.
* `retention_score = importanza * 3 + 2 * max(0, 6 - giorni_trascorsi)`. L'importanza domina; la
  freschezza rompe solo i pareggi. Quando il libro è pieno esce il punteggio più basso (a pari
  punteggio il più vecchio, poi l'ID minore).
* I ricordi con importanza `>= 75` (`PERMANENT_IMPORTANCE`) sono eliminati solo se non esiste alcun
  ricordo non protetto; ogni eliminazione è contata (`evicted_count`), quelle protette anche
  (`evicted_protected_count`) e scritte nel log. Il registro oggettivo conserva comunque l'evento:
  dimenticare è una proprietà del personaggio, non del mondo.
* Il registro eventi è limitato (`social_event_log_limit`, default 160): esce prima l'evento meno
  importante (a pari importanza il più vecchio) e la rimozione è contata in `dropped_event_count`.

### 6. Conseguenze sulla simulazione

`SocialRules.cooperation_willingness(asker, partner)` parte da `50` e applica `+0,4` per punto di
fiducia sopra 50, `+0,2` per punto di affinità sopra 50, `-0,6` per punto di tensione, `+14` se
l'interrogato ricorda un **aiuto ricevuto** da quella persona (importanza `>= 45`), `-18` se ricorda
un **litigio degli ultimi 3 giorni** (importanza `>= 45`). Oltre la soglia `55` la cooperazione è
accettata. Con fiducia 60 e affinità 50 la stessa coppia rifiuta a `54` e accetta a `68` dopo un
aiuto memorizzato: la memoria cambia un comportamento, non solo un testo.

Gli effetti raggiungono lo stato simulato: cooperazione accettata `+0,8` di benessere a entrambi,
aiuto `+2,5` a chi riceve e `+0,5` a chi offre, disaccordo `-2,0` a entrambi. È l'unica scrittura
che questo sistema fa su un `NpcRecord`, ed è sempre clampata.

### 7. Interfaccia

`NpcPanel` mostra tre relazioni principali (in ordine di `SocialRelationship.strength()`), la riga
"Ultimo cambiamento" con il motivo documentato e il giorno dell'evento che lo spiega, e tre ricordi
rilevanti. Le righe sono costruite dal sistema (`relationship_lines`, `change_explanation`,
`memory_lines`), quindi l'interfaccia non può mostrare un numero diverso da quello simulato. Nessun
pannello nuovo e nessun valore aggiunto oltre a questi.

### 8. Persistenza

`SocialSystem.to_dict()` / `from_dict()` coprono grafo, memoria, registro eventi, contatori e
limiti, nella stessa convenzione di `SimulationClock`, `SimulationLoop`, `NpcSimulationSystem` ed
`EconomySystem`: ogni sistema serializza il proprio stato e il futuro modulo `persistence` dovrà
solo raccoglierli. Al caricamento ogni riferimento viene ripulito (`remove_orphans` su relazioni e
ricordi, `_drop_dangling_events` sugli eventi) e `validate()` deve restituire un array vuoto.

### 9. Che cosa non c'è ancora

Nessuna famiglia, gruppo o fazione; nessuna reputazione pubblica; nessuna cronaca giocabile; nessun
dialogo generativo; nessun ricordo non sociale; nessuna prospettiva incompleta attiva; le
interazioni non cambiano la destinazione di un abitante. Sono tutti in `ROADMAP.md`, non nel codice.

## Dati e persistenza

* Nessun save in questa fase. `SimulationClock`, `SimulationLoop` e i sistemi (abitanti, economia,
  sociale) espongono `to_dict()` / `from_dict()` per prepararne una, ma il modulo `persistence` non
  esiste ancora. Lo stato sociale — grafo, ricordi, registro eventi e contatori degli ID — è già
  coperto dal round trip e verificato dai test.
* Gli ID degli abitanti sono `npc_001` … `npc_016`: corti, stabili e leggibili. Non sono UUID,
  perché il roster è una tabella fissa e la stabilità tra un avvio e l'altro è più utile
  dell'unicità globale in questa fase. La persistenza potrà introdurre un UUID accanto all'ID
  stabile quando servirà.
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
   budget di draw call, triangoli e collider, e verifica gli abitanti: popolazione configurata,
   ID unici, nomi stabili, bisogni che avanzano senza view, selezione condivisa da presenter e
   pannello.

La nuova suite NPC aggiunge: dati e serializzazione, roster stabile, rete di percorso con
ostacoli e luoghi irraggiungibili, simulazione di 240+ tick con bisogni che evolvono, routine che
rispondono a orario e fame, sonno notturno, assenza di teletrasporti, determinismo e raggiungibilità
di ogni luogo reale del villaggio.

La suite economica (`TestEconomyInventory` + `TestEconomySimulation` + sezione `EconomyAndPanel` in
`test_world_scene.gd`) verifica inoltre che:

* nessuna risorsa diventi mai negativa;
* le transazioni non valide siano rifiutate senza effetti collaterali né modifiche parziali;
* la produzione dipenda dal lavoro effettivamente svolto e dai prerequisiti delle postazioni;
* il commerciante faciliti gli scambi senza creare ricchezza dal nulla;
* il consumo di cibo dipenda dal numero di abitanti e la scarsità incida sui bisogni senza
  mortalità;
* i riepiloghi di `EconomyPanel` corrispondano esattamente ai dati di `EconomySystem`;
* l'avanzamento di più giorni produca risultati identici e ripetibili a parità di condizioni
  iniziali.

La suite sociale (`TestSocialRelationships` + `TestSocialSimulation` + sezione `check_social` in
`test_world_scene.gd`) verifica inoltre che:

* la chiave di una relazione sia canonica e che `create()` rifiuti duplicati, ID vuoti e
  auto-relazioni, anche caricando da un dizionario;
* ogni evento e ogni ricordo indichino gli NPC davvero coinvolti, con ID presenti nel roster;
* i valori restino in `0..100` dopo guadagni, perdite e serializzazioni ripetute;
* il tetto giornaliero condiviso impedisca una crescita illimitata della fiducia: 40 giorni di
  cooperazione continua non portano alcun attributo oltre 100 e la crescita giornaliera non supera
  mai il tetto;
* la memoria rispetti la capacità configurata, non elimini ricordi permanenti quando ne esistono di
  eliminabili e conservi un contatore quando è costretta a farlo;
* la disponibilità a cooperare dipenda dalla memoria (lo stesso rapporto rifiuta prima di un aiuto
  memorizzato e accetta dopo) e non solo da un testo descrittivo;
* un round trip `to_dict()` → `from_dict()` ripristini gli stessi ID e gli stessi valori;
* caricare uno snapshot in un mondo più piccolo rimuova relazioni, ricordi **ed eventi** che
  citano abitanti assenti, senza lasciare riferimenti pendenti;
* `NpcPanel` mostri le relazioni e i ricordi costruiti dal sistema, con il motivo documentato
  dell'ultimo cambiamento.

Regola di progetto: il livello 3 è obbligatorio per qualunque modifica che tocchi mondo, terreno,
giocatore o presentazione degli NPC. È il livello che ha trovato i tre bug reali della prima fase e
i cinque della fase economia (inferenza da `Variant`, steccato sulla strada dei campi, precedenza
degli operatori in una stringa di log, autoload nominati troppo presto dal runner, `null` in
`ARRAY_INDEX`). In questa fase il difetto è arrivato dal livello 2, ma solo dal motore: una funzione
duplicata in `social_system.gd` che `gdparse` e `gdlint` accettavano e Godot rifiutava.

Ultima esecuzione completa: **1162 asserzioni di unità e 113 di integrazione, 0 fallite, 0
saltate** (`bash tools/run_checks.sh` con Godot 4.7.2 headless compilato dai sorgenti). Di queste,
251 di unità e 17 di integrazione coprono il sistema sociale; le cifre sono state misurate
disattivando le suite sociali e ripetendo l'esecuzione, non contate a mano.
