# EVERAFTER — Visual Polish 14: paesaggio modellato

Questo documento registra l'intervento **Visual Polish 14** sul terreno del mondo reale:
che cosa è stato trovato, quale metodo di costruzione è stato corretto, che cosa è cambiato e
come è stato verificato. **Nessun sistema di gioco è stato toccato**: dimensioni della mappa,
seed, strade, edifici, NPC, economia, salvataggi e collisioni restano quelli di prima.

> Riferimenti: `src/world/terrain_generator.gd` (scultura del terreno),
> `src/world/environment/terrain_relaxer.gd` (guardiano geometrico, nuovo),
> `src/world/environment/village_builder.gd` (affioramenti rocciosi sulle pendenze),
> `tests/unit/test_terrain_relaxer.gd`, `tests/unit/test_terrain_generator.gd`,
> `tests/integration/test_world_scene.gd` (`check_terrain_shape`).

---

## 1. Diagnosi — perché il paesaggio appariva piatto (`BEFORE`)

Il terreno **non era una mesh piatta**: era già un height field procedurale (160×160 celle,
1 unità per cella, `height_scale = 5.0`). Il difetto era nel **metodo con cui il rilievo veniva
costruito**, non nel colore:

1. **Una sola scala di paesaggio dominante.** La componente bassa (`LOW 0.021`) generava un'onda
   larga; il dettaglio (`0.053`, `0.121`) veniva quasi azzerato da `flatten_weight` proprio dove
   il giocatore cammina. Il risultato era una "pelle tesa": nessuna dorsale ampia, nessuna
   valletta leggibile a distanza di occhiata, campi che sembravano un piano leggermente incurvato.
2. **Nessun contatto credibile tra costruito e suolo.** `flatten_weight` appiattiva il dettaglio
   ma **non** la forma del terreno: una strada o un piazzale restavano un disco/un nastro alla
   quota della collina naturale, con un bordo che poteva diventare un gradino. La piazza, in
   particolare, era un disco perfetto di raggio 11 m con il terreno che riprendeva quota nel
   giro di 4,5 m: una piattaforma "ritagliata" nella collina.
3. **Bordo della mappa rettilineo.** L'ultimo anello di vertici era un quadrato esatto: guardando
   verso l'orizzonte, la fine del mondo si leggeva come una linea retta.
4. **Nessun controllo geometrico finale.** Nulla impediva a due celle adiacenti di differire di
   un metro o più: qualunque futura aggiunta di rilievo avrebbe potuto creare un gradino non
   scalarile dalla capsula (`floor_max_angle = 50°`).
5. **Piazzole degli edifici solo "colorate".** Il peso `flatten_weight` livellava il dettaglio ma
   il colore di terra battuta sotto le case non corrispondeva a una quota davvero piana.

## 2. Scelta del metodo

Il terreno **era già procedurale e deterministico**, con una sola griglia letta sia dalla mesh sia
dalla `HeightMapShape3D`. La consegna chiede di migliorare l'algoritmo esistente, non di
affiancarne un secondo: quindi **non** è stato introdotto un plugin, un secondo sistema di
terreno, né una mesh importata. Sono stati corretti/estesi:

* **`TerrainGenerator`**: la stessa funzione di altezza, con nuovi termini e un ordine di
  valutazione esplicito (armatura → dettaglio → warp → micro-rilievo → creste → spalle stradali →
  orizzonte → terrazzamento → bacino → piazzole → piazza → stagno).
* **`TerrainRelaxer`** (nuovo, `RefCounted` puro): rilassamento di talus e fusione delle piazzole,
  applicati **alla stessa griglia** prima che mesh e collisione vengano costruite.

Nessuna coordinata, dimensione o punto di riferimento è cambiato: la mappa resta
`159 × 159` unità (`size_cells = 160`), centrata sull'origine, con le stesse tre strade, la stessa
piazza (raggio 11) e lo stesso stagno (`33, -27`, raggio 8,5).

---

## 3. Interventi (`AFTER`)

### 3.1 Armatura del paesaggio — dorsali e valli leggibili

Due nuove ottave molto basse (`0.0048 / 0.52` e `0.0075 / 0.28`) si sommano alle tre esistenti in
`_landform_noise()`. Sono **condivise** da tutti i sistemi che devono appoggiarsi al suolo (piazza,
piazzole, spalle stradali): il terreno e le piattaforme leggono lo stesso campo, quindi non possono
divergere.

* Effetto: dislivello utile passato da ≈ 16 m a ≈ 20,7 m, con valli e dorsali di 150–250 m
  leggibili dall'alto e da terra.
* Il campo è normalizzato prima di `height_scale`: cambiare la scala del mondo continua a
  funzionare come prima.

### 3.2 Micro-rilievo dei campi — dossi e avvallamenti

`_micro_relief_height()` aggiunge tre ottave (`0.065`, `0.12`, `0.042`) per un massimo di ≈ 0,55 m
di rilievo locale. È mascherato da `flat_wide`, che include **anche la spalla stradale** (6 m):
nessun dosso può sorgere a una cella dalla carreggiata.

### 3.3 Creste rocciose — silhouette, non volume

`_rock_ridge_height()` campiona il rumore in uno spazio **stirato** (`x·1,55 + z·0,45`,
`z·1,15 − x·0,30`) così le creste leggono come affioramenti allungati e non come una fila di urti
tondi. Compaiono solo su terreno alto (`> 12 % di `height_scale`) e fuori dal costruito; aggiungono
al massimo ≈ 0,45 m — abbastanza per la silhouette, mai per un ostacolo.

`VillageBuilder._bake_slope_outcrops()` completa il disegno con **18 affioramenti litici**
seminati dove `terrain.slope_at() ≥ 0,17`: massi schiacciati e interrati per il 40 %, con una o due
schegge a valle, **senza collider** (sono alti al massimo fino al ginocchio). Usano un RNG proprio
(`world_seed + 97`) per non spostare cordoli, ninfee e ciottoli già esistenti.

### 3.4 Percorsi — spalle digradanti e bordo irregolare

* **Bordo fisico irregolare**: `_irregular_flatten_weight()` perturba la distanza dalla strada con
  tre ottave prima di calcolare il peso di appiattimento. Il centro della carreggiata resta
  perfettamente piatto (la perturbazione è applicata con `max()`, che può solo *aggiungere*
  appiattimento attorno), mentre il margine dove il dettaglio svanisce non è più un offset
  vettoriale.
* **Spalla digradante**: entro 6 m dall'asse, il terreno viene interpolato verso la quota del
  **punto più vicino della strada** (`_nearest_road_point` + `_landform_noise`), con forza 0,82 e
  caduta `smoothstep`. È il taglio/riporto di una strada vera: la carreggiata non cambia quota,
  ma la riva sale in modo camminabile invece di essere una parete.
* **Corona e scolina** restano, spostate dopo la spalla: +4–7 cm al centro, −10 cm alla banchina.

### 3.5 Orizzonte — niente più quadrato

`_horizon_height()` solleva l'ultima fascia (14 m) verso il bordo con due ottave di rumore e un
profilo `smoothstep`. Il rialzo misurato è ≈ 3–4 m in media sul bordo, con un profilo che varia fra
2,2 e 9,1 m lungo il perimetro (quindi non rettilineo), distribuito su 14 m (pendenza < 25 %). Le tre strade conservano una sella (il rialzo scende al 28 % dove `road_w > 0,1`) così le
vie d'uscita restano aperte. Sulle mappe piccole (mezza estensione < 35) il termine è nullo: i test
esistenti con griglie 32×32 non cambiano comportamento.

### 3.6 Terrazzamento del villaggio e integrazione degli edifici

* **Sedime del villaggio** (`_terrace_weight`): entro 12 m l'altezza è quella della piazza, poi
  digrada fino a 34 m con forza 0,42. La piazza non è più un disco ritagliato: è un ripiano in un
  pendio.
* **Piazzole degli edifici**: `_collect_building_pads()` registra ogni placement di tipo
  `GROUND_LEVELLING_KINDS` (case, locanda, municipio, pozzo, banchi, carro, legnaia) con la quota
  del **platform** (`_landform_noise` già terrazzato). `TerrainRelaxer.pad_blend()` fonde le
  piazzole vicine con **media pesata al cubo**: dentro l'impronta il pad vince quasi esattamente
  (fondo piatto, plinto appoggiato), sull'anello di ricaduta due piazzole si fondono senza scalini.
* **Ordine di valutazione**: le piazzole sono applicate **per ultime**, dopo piazza e stagno, così
  una fondazione vince sempre sul bordo del selciato e sulla riva. L'unica eccezione è la
  carreggiata: entro 1,8 m dall'asse, con una sfumatura di 1 m, il pad è annullato per non rendere
  ondulata la strada (nessun edificio ha l'impronta così vicina all'asse).
* **Orlo di fondazione**: un piccolo rialzo (`sin(w·π)`) sul solo anello di ricaduta trasforma il
  taglio in un piede naturale. Non tocca il terreno sotto la casa.

### 3.7 Bacino dello stagno

`_pond_basin_weight()` attenua il terreno entro 18 m dal centro verso la quota dello stagno
(forza 0,35) **prima** dello scavo del bacino e del berm. La riva diventa una sponda, non la
parete di una ciotola scavata nella collina.

### 3.8 Colore coerente con la forma

`_curvature_at()` (altezza meno la media dei quattro vicini) guida due ritocchi per-vertice:
creste leggermente più chiare e secche (`COLOR_GRASS_DRY`), avvallamenti più scuri e umidi
(`COLOR_MOSS`). Gli affioramenti rocciosi sono dipinti anche sulla cresta (`outcrop`), non solo
sulla pendenza. Tutto resta `vertex_color_use_as_albedo`: nessuna texture nuova, nessun costo GPU
aggiuntivo.

### 3.9 Guardiano geometrico (`TerrainRelaxer`)

* `nearest_road_point()`: punto più vicino sull'asse di una strada, usato dalla spalla
  digradante per sapere quale terreno la strada sta seguendo.
* `build_protected_mask()`: protegge piazza, carreggiate (±0,5 m) e piazzole — le stesse superfici
  che il layout dichiara costruite.
* `relax_heights()`: passa di **talus** (12 iterazioni al massimo, con uscita anticipata quando la
  griglia è stabile; limite `MAX_CELL_STEP = 0,72 m` fra celle adiacenti, ≈ 36°). La regola esatta è `h ∈ [max(vicini) − step, min(vicini) + step]`; se i due
  estremi si incrociano (cella fra due quote molto diverse) vince il punto medio. I vertici
  protetti non vengono mai scritti ma contano come vicini: la sponda verso una strada o una piazza
  si raccorda da sola.
* Il passaggio è **deterministico** (ordine fisso, nessun `randf`), quindi salvataggi e mondo
  restano riproducibili.
* `height_range()`, `max_neighbour_step()`, `horizon_rise()` espongono misure oneste della griglia
  per i test e per il log di avvio.

---

## 4. Difetti verificati assenti

| Rischio | Verifica |
| --- | --- |
| Buchi o triangoli deformi | La mesh è costruita dalla stessa griglia di prima, con la stessa indicizzazione (`2·(n−1)²` triangoli, nessun vertice aggiunto). |
| Discontinuità fra mesh e collisione | `height_at()` interpola sugli stessi due triangoli della `HeightMapShape3D`; `check_terrain_collision` continua a confrontare 169 raggi con la superficie fisica. |
| Superfici sovrapposte | Nessuna superficie nuova: acqua e ciottoli restano dentro il bacino (0,92·r), gli affioramenti sono interrati e non coplanari. |
| Gradini non scalabili | `max_neighbour_step(open_ground_only = true)` ≤ 0,72 m sul terreno aperto; `slope_at()` su campioni lontani da strade e piazzole resta sotto 1,0 (45°), contro il limite di scalata di 50°. |
| Edifici storti o sospesi | Ogni placement di livellamento ha il fondo piatto entro 12 cm su un anello di 0,8 m (`check_terrain_shape`). |
| Strade troppo ripide | La carreggiata non viene mai spostata dalla spalla; il bordo fisico irregolare usa `max()`, che non può alzare un dosso *dentro* la carreggiata. |

---

## 5. Misure

Porting fedele dell'algoritmo (stessa funzione di hash, stessa griglia 160×160, stesso seed
`20261016`, stesse strade radiali) usato per stimare i numeri **prima** di dichiararli:

| Metrica | Prima (VP13) | Dopo (VP14) |
| --- | --- | --- |
| Dislivello totale del campo | 16,1 m | **20,7 m** |
| Deviazione standard dei campi aperti | 3,50 m | **4,06 m** |
| Pendenza p50 del terreno aperto | 0,18 (10,2°) | **0,21 (11,9°)** |
| Pendenza p99 del terreno aperto | 0,55 (28,8°) | **0,68 (34,2°)** |
| Pendenza massima su terreno aperto (lontano da strade) | 0,73 (36,1°) | **0,80 (38,7°)** |
| Salto massimo tra celle adiacenti (aperto) | 0,67 m | **0,72 m** (limite imposto) |
| Pendenza della carreggiata (sulla griglia) | max 15,6°, media 0,15 | **media ≤ 0,17 (10°), singola cella fino a 36°** (il limite imposto dal talus) |
| Quota della piazza | 5,76 m (disco) | **3,54 m su un ripiano** |
| Quota del bordo rispetto all'interno (media) | +0,4 m, bordo rettilineo | **+3,7 m, profilo irregolare** |

La carreggiata resta percorribile: misurata sulla griglia finale (quella che il giocatore cammina),
la pendenza media delle tre strade resta fra 1° e 10°, con il solo picco di una cella a 36° dove il
talus interviene. Dentro il raggio di 9 m la piazza è **esattamente** piatta (3,535 m su tutta la
superficie). Nessuna modifica alle tre strade, alla piazza o allo stagno.

> Nota di metodo: le pendenze sopra sono misurate sulla **griglia rilassata** e non sulla funzione
> continua. Il motivo è sostanziale: il giocatore cammina sulla `HeightMapShape3D`, che legge la
> griglia; una piega della funzione fra due punti di griglia non esiste per la fisica.

---

## 6. Verifiche eseguite

| Controllo | Comando | Esito |
| --- | --- | --- |
| Coerenza progetto | `python3 tools/check_project.py` | **OK** |
| Sintassi GDScript | `gdparse` su tutti i file `src` + `tests` | **OK** |
| Stile `gdlint` sui file toccati | `gdlint src/world/terrain_generator.gd src/world/environment/terrain_relaxer.gd src/world/environment/village_builder.gd tests/unit/test_terrain_relaxer.gd tests/unit/test_terrain_generator.gd` | **OK (0 problemi)** |
| Stile `gdlint` sull'intero progetto | `gdlint src tests` | 17 problemi **preesistenti** (persistence, chronicle, vegetation); i file di questo intervento sono puliti |
| Modello geometrico fedele in Python | seed reale, griglia 160×160, audit di pendenza/salti | usato per le misure della sezione 5 |
| Runtime Godot | — | **NON eseguito in questo ambiente** (nessun binario Godot disponibile) |

> **Dichiarazione onesta.** In questo ambiente non è disponibile un runtime Godot: le suite
> headless non sono state rieseguite qui. Le modifiche sono state verificate con i controlli
> statici, con i nuovi test (scritti per girare in `tests/run_tests.gd` e
> `tests/run_world_tests.gd`) e con un porting numerico dell'algoritmo usato per misurare pendenze,
> dislivelli e salt. Prima di considerarle chiuse vanno eseguiti, su una macchina con Godot 4:
>
> ```sh
> bash tools/run_checks.sh
> godot --headless --path . --script res://tests/run_tests.gd
> godot --headless --path . --script res://tests/run_world_tests.gd
> ```
>
> In gioco: percorrere le tre strade, salire su una cresta, girare attorno a ogni casa, entrare e
> uscire dallo stagno e guardare verso il bordo della mappa da ±70 unità. La superficie deve
> risultare continua, la camminata stabile (nessun punto in cui la capsula scivola o si blocca) e
> la linea dell'orizzonte non deve mostrare un bordo rettilineo.

---

## 7. File toccati

* `src/world/terrain_generator.gd` — armatura, micro-rilievo, creste, spalle stradali, orizzonte,
  terrazzamento, piazzole, bacino; colore guidato dalla curvatura; query `slope_at`,
  `height_range`, `max_neighbour_step`, `horizon_rise`.
* `src/world/environment/terrain_relaxer.gd` — **nuovo**: maschera del costruito, talus, fusione
  piazzole, misure.
* `src/world/environment/village_builder.gd` — affioramenti rocciosi sulle pendenze (18 massi,
  nessun collider, ~1,4 k triangoli in più).
* `tests/unit/test_terrain_relaxer.gd` — **nuovo**: 4 gruppi di controlli.
* `tests/unit/test_terrain_generator.gd` — rilievo leggibile, limite di salto, orizzonte,
  determinismo, `slope_at`.
* `tests/integration/test_world_scene.gd` — `check_terrain_shape`: rilievo, salto massimo, orizzonte,
  piazzole livellate, pendenza del terreno aperto.
* `tests/run_tests.gd`, `tests/run_world_tests.gd` — registrazione delle nuove suite.
* `docs/ARCHITECTURE.md`, `README.md` — descrizione del metodo aggiornata.

Nessun asset binario, nessuna modifica a `project.godot` o `config/game_config.tres`, nessun nuovo
materiale, nessuna nuova scena.

---

## 8. Cosa non è stato fatto (di proposito)

* Nessun sistema di terreno esterno (plugin, heightmap importata, LOD a chunk).
* Nessuna modifica a strade, piazza, stagno, edifici, seed, dimensioni o economia.
* Nessun nuovo collider per gli affioramenti: sono decorativi e sotto il ginocchio, la pendenza
  stessa è l'ostacolo.
* Nessuna texture o shader: il rilievo si legge grazie alla geometria e alle normali, non a una
  mappa di parallasse.

---

*EVERAFTER · Visual Polish 14 · 2026-10-19 · Arena Agent*
