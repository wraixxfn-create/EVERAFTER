# EVERAFTER — Miglioramento del terreno e del paesaggio (Visual Polish 06)

Questo documento registra l'intervento di **polish esclusivamente grafico** sul terreno di
EVERAFTER: cosa è stato trovato analizzando la topografia esistente, cosa è cambiato, perché
le scelte rispettano i vincoli del progetto e quali controlli sono stati eseguiti.
**Nessun sistema di gioco è stato toccato**: mappa, dimensioni, economia, NPC, salvataggi e
collisioni sono invariati.

> Riferimenti incrociati: `src/world/terrain_generator.gd` (generatore), `src/world/environment/village_layout.gd`
> (tracciati e flatten), `src/world/environment/village_builder.gd` (cordoli e rive), `src/world/environment/vegetation_builder.gd` (erba).

---

## 1. Analisi del terreno prima dell'intervento

### 1.1 Topografia

- Base a tre ottave deterministiche: `LOW 0.021 / 1.0`, `MID 0.053 / 0.45`, `HIGH 0.121 / 0.18`,
  tutte modulate da `flatten_weight`. La componente bassa sopravvive su strade e lotti, le due
  alte svaniscono — rende i percorsi percorribili senza scavare trincee.
- `height_scale = 5.0` su `160×160` celle (159×159 u). Con `half_extent = 79.5` il dislivello
  utile è ≈ ±5 m: volutamente contenuto per restare walkable con `CharacterBody3D` raggio 0.4.
- **Difetto**: i campi aperti erano quasi piatti oltre alla singola onda `LOW`. Mancava la
  struttura a “vallette e dossi” dei prati reali; il rumore appariva come una pelle tesa, non
  come un paesaggio.
- **Difetto**: le rive dello stagno erano un taglio netto `terrain_offset = -0.085 * scale` con
  `smoothstep(pond_weight)` — leggibile come un cerchio vettoriale, non come una depressione
  naturale. Nessun berm di riva.

### 1.2 Sentieri e piazze

- Tre strade radiali uscenti dalla piazza: `ROAD_WIDTH 3.6`, `ROAD_FALLOFF 2.4`, `PLAZA_RADIUS 11`,
  `PLAZA_FALLOFF 4.5`. Peso lineare `1 - clamp((dist - R*0.5)/FALLOFF)` → transizione matematicamente
  liscia ma visivamente a **bordo geometrico perfetto**. Senza jitter, la piazza è un disco e le
  strade due strisce parallele.
- Cordolo della piazza già presente (44 segmenti a r 12.2) e cordolo stradale a pietre
  intervallate (`ROAD_KERB_SPACING 2.4`, gap 12 %). Buoni, ma le pietre della piazza erano
  identiche (1.9×0.28×0.7) e allineate allo stesso yaw — effetto “torus estruso”.
- Colori: `COLOR_DIRT (0.56,0.41,0.23)` uniforme su tutta la carreggiata, schiarito solo di
  `darkened(road_t²*0.12)` al centro. Nessuna variazione di argilla, ghiaia di banchina o usura
  da calpestio. Ripetizione evidente su lunghi rettilinei.
- Piazza: `COLOR_COBBLE (0.57,0.53,0.47)` uniforme → pavimento piatto, senza fughe scure, senza
  lucidatura centrale da calpestio secolare, senza intrusione di terra alle bocche delle strade.

### 1.3 Superfici erbose

- Base `COLOR_GRASS_DARK → COLOR_GRASS` modulata da `height_t`, + singolo patch `noise 0.031 → MEADOW*0.55`.
  Una sola scala → campi che appaiono come un unico prato sintetico.
- Motivi di sporcatura (`medium_grain 0.29/0.055 + fine 0.61/0.02`) deboli; il verde restava
  eccessivamente uniforme soprattutto sui dorsi collinari.
- Nessun “erba secca” su alture soleggiate, nessun “heath” desaturato nei pianori.

### 1.4 Zone rocciose

- Roccia solo su soglia `rock_t = (slope-0.35)/0.6`. Soglia fissa, nessun jitter → bande nette
  su pendii appena sopra 0.35, e scogliera improvvisa senza ghiaione di transizione al piede.
- Colore `COLOR_ROCK` unico, senza varianti calde/ghiaiose e senza muschio su pendii umidi
  vicino allo stagno.

### 1.5 Transizioni terreno ↔ edifici / rocce / vegetazione

- Fondazione degli edifici: `TerrainGenerator` livella il plot con `flatten_weight`, ma il
  colore restava “prato rasato” sotto il plinto in pietra. Stacco netto intonaco ↔ verde brillante.
- Rocce piazzate da `VegetationBuilder`: la mesh pietrosa si appoggia sul prato senza anello
  di ombra o muschio — galleggia visivamente.
- Vegetazione: erba esclusa correttamente dai plinti solidi (`GRASS_EXCLUSION_KINDS`), ma il
  terreno sotto la chioma non cambiava (nessun “leaf litter” o terra battuta).

### 1.6 Texture e difetti geometrici

- Nessuna texture esterna (repo solo-testo), ma i colori per-vertice su griglia 1 m possono
  apparire stirati sui triangoli grandi della piazza piatta. Due sole scale di grain non bastano.
- Sovrapposizioni: disco d’acqua `r = pond_radius*0.92` ben dentro il bacino, nessun z-fighting
  terreno-acqua rilevato. Pilastri di recinzione evitano già la strada (`FENCE_GATE_MARGIN 1.6`).
- Piccoli difetti: le pietre del cordolo stradale a volte attraversavano l’imbocco di un lotto
  (corretto da `_near_structure`), ma il cordolo della piazza restava troppo regolare.

---

## 2. Interventi

### 2.1 Variazioni di colore e materiale del terreno (`terrain_generator.gd`)

Palette ampliata mantenendo gli 8 colori storici come ancore (compatibilità visiva):

| Nuovo | Valore | Ruolo |
|---|---|---|
| `COLOR_GRASS_DRY` | `0.46,0.52,0.20` | Ciuffi soleggiati su alture, dorati e meno saturi |
| `COLOR_HEATH` | `0.38,0.44,0.22` | Brughiera desaturata nei pianori |
| `COLOR_CLAY` | `0.62,0.38,0.20` | Striature argillose lungo le strade |
| `COLOR_GRAVEL` | `0.52,0.49,0.43` | Ghiaia di banchina e fondazioni |
| `COLOR_MOSS` | `0.22,0.36,0.18` | Muschio su rocce umide e riva |
| `COLOR_SAND_LIGHT` | `0.78,0.71,0.52` | Sabbia asciutta di riva |
| `COLOR_SOIL` | `0.36,0.28,0.19` | Terra battuta attorno alle case |
| `COLOR_STONE_WARM` | `0.60,0.55,0.46` | Pietra calda dei ciottoli |

Tecnica: tutte le nuove tinte sono `lerp` tra colori esistenti + jitter deterministico via
`_value_noise` hashato (stesso seme del terreno). Nessuna texture, nessun `ShaderMaterial`:
solo `vertex_color_use_as_albedo` su `StandardMaterial3D` (roughness 0.93), quindi nessun
costo aggiuntivo per la GPU — resta sotto il budget GTX 1060.

### 2.2 Eliminazione bordi artificiali e superfici uniformi

- **Bordo stradale / piazza wobblato**: in `_vertex_color` il peso grezzo di `layout.road_weight`
  e `layout.plaza_weight` viene perturbato da due ottave di `edge_jitter`
  (`0.082/0.22 + 0.156/0.10`). Risultato: il colore “terra” oscilla di ±0.7 m rispetto al limite
  fisico di flatten. Il sentiero resta fisicamente piatto (collisioni invariate), ma l’occhio
  legge un bordo organico. Gap col plinto evitato da `building_t` che maschera il jitter vicino
  alle case.
- **Transizioni levigate con `smoothstep`**: `road_core = smoothstep((road_w-0.45)/0.5)` e
  `plaza_core = smoothstep((plaza_w-0.30)/0.6)` danno un plateau centrale e una caduta morbida
  invece del gradiente lineare precedente.
- **Meadow a due scale**: `meadow_big 0.019 + meadow_small 0.041` (62 % / 38 %) invece di
  singolo `0.031`. I campi non sono più un pattern ripetuto.
- **Grain a tre scale**: `medium 0.29/0.055 + fine 0.61/0.02 + large 0.088/0.038`. La componente
  “large” sopravvive alla griglia 1 m e spezza le facce ampie della piazza piatta.

### 2.3 Sentieri, piazze, aree erbose e zone rocciose rifinite

**Sentieri**
- Terra base `DIRT` + striature `CLAY` (`clay_n` da `value_noise` stirato 1.08×0.92, 0.062/0.24).
- Banchina in `GRAVEL` (`road_shoulder` + `gravel_n 0.098`) — la transizione terra→erba non
  è più un salto.
- Solco centrale: `dist_to_road = layout.road_distance(x,z)` → maschera `centre_mask =
  smoothstep(1 - dist/(ROAD_WIDTH*0.48))` oscurata di 0.10 e virata a `SOIL` 0.14. Due solchi di
  ruota accennati con `cos(dist*1.85*TAU)`.

**Piazza**
- Ciottoli variegati: `cobble_big 0.062` (calore) + `cobble_small 0.22` (granulata),
  `STONE_WARM` e `GRAVEL` accennati. Giunti scuri (`cobble_small>0.62`) con `DIRT 0.10`.
- Lucidatura: `centre_polish = smoothstep(1 - dist/PLAZA*0.62)` schiarita di 0.055 — il centro
  consunto è più chiaro.
- Bordo sporco: `plaza_edge 0.09` inscurito; alle bocche `overlap = plaza_w * road_w`
  vira a `DIRT 0.22` (la strada entra nella piazza).
- Cordolo (`village_builder.gd`): lunghezze 1.75–2.05 invece di 1.9 fisso, altezze 0.26–0.30,
  yaw ±2°, posizionamento ±1.5 cm — non più un toroide perfetto.

**Erba**
- `height_t` resta l’altimetro, ma ora `dry_t = (dry_noise-0.66)/0.28 *0.20*height_t` schiarisce
  le alture soleggiate, e `heath_t = (heath_noise-0.58)/0.32 *0.16` desatura i pianori.
- Entrambi mascherati da `slope` per non sporcare le scarpate.

**Roccia**
- Soglia wobblata: `slope_adj = slope + noise*0.08`, `rock_t = smoothstep((slope_adj-0.30)/0.52)`
  + bias d’altura `+0.18*(height/scale)`.
- Variazione in-palette: `rock_key` lerpa a `GRAVEL 0.32` e, se `pond_hint>0.08`, a `MOSS 0.55`.
- Ghiaione al piede: `scree_t = ((slope-0.18)/0.18)*(1-rock_t)*0.28` — sparso, non invasivo.

### 2.4 Transizione terreno ↔ edifici / rocce / vegetazione

- **Anello calpestato** (`building_t`): derivato da `flatten_weight > max(plaza,road)` senza
  iterare i placement (O1). `color.lerp(SOIL, building_t*0.34)` crea una fascia di terra battuta
  1–2 m attorno a ogni casa/locanda/sala. Se `building_t>0.62`, ulteriore `GRAVEL 0.32`
  simula lo spruzzo di fondazione. Mascherato da `rock_t` e `max(road,plaza)` per non sporcare
  cordoli e selciati.
- **Rocce**: le pietre vicino all’acqua virano a muschio, e lo ghiaione al piede ammorbidisce
  il passaggio prato→parete.
- **Vegetazione**: l’erba resta esclusa dai plinti (`GRASS_EXCLUSION_KINDS`), ma il terreno vi
  contribuisce: `heath` e `dry` sono attenuati su `slope`, così le chiome non fluttuano su
  verde brillante.

### 2.5 Texture stirate, ripetizioni, sovrapposizioni, difetti

- Stiramento: evitato — nessun UV, solo colori per vertice; il `large_grain 0.088` garantisce
  varianza anche su triangoli grandi.
- Ripetizione: tre ottave di altezza + due di prato + due di bordo + tre di grain, tutte con
  offset irrazionali (e.g. `+31.7/-18.3`, `+11.4/-52.8`). Nessuna tazza di pattern visibile a
  scala mappa.
- Sovrapposizioni: disco acqua r `0.92*pond_radius` (già esistente) + coroncina di ciottoli a
  `0.88/1.06*r` leggermente interrata (`h+0.06` con `size.y 0.12–0.18`) — nessun piano coincidente.
- Difetti: cordolo piazza non più rigido, cordolo stradale già con `_near_structure` gap,
  plinti e zoccoli invariati (nessun nuovo collider che interseca la `HeightMapShape3D`).

### 2.6 Leggere variazioni topografiche (sicure)

Tutte dentro `if layout!=null and flat<0.95` → mai su strade, piazze o lotti:

- **Warp dei campi**: `field_warp = noise 0.038*0.35 + 0.074*0.18`, poi `height += warp *
  (1-flat)*scale*0.13`. Picco ≈ 0.45 m nei prati, zero sul costruito.
- **Onda ampia**: `low += noise 0.011*0.32` prima del calcolo — crea colline di fondovalle
  più organiche senza toccare la logica di `detail*(1-flat)`.
- **Berm di riva**: dopo il carve del bacino, `if 0.06<pond_w<0.88: height += sin(pond_w*PI)*
  (1-flat*0.45)*scale*0.055`. Labbro < 0.30 m che rende l’invaso una conca naturale.
- Navigazione: `Maxslope` su campi resta < 0.35 (testata via `_slope_at`); strade e porte
  restano piatte per costruzione (plaza lerp e `flatten` non alterati).

### 2.7 Profondità visiva

- **Occlusione di valle**: `ao_t = (0.45-height_t)/0.45 * (1-built*0.65) *0.07` inscurisce i
  fondo-valle non costruiti — profondità a costo zero (solo tint).
- **Riva umida**: `pond_w*0.08` inscurito + `moss_edge` a `pond_w≈0.52`.
- **Roccia & ghiaione** danno lettura di altezza anche da lontano.
- Nuova coroncina di riva (`village_builder._bake_pond_shore_pebbles`): 18 settori con due anelli
  di ciottoli (`rock`/`stone`, 0.55–0.95 m) e canneti occasionali (`leaf_deep` quads 0.55–0.85 m)
  — profondità senza volumetrica, senza texture.

---

## 3. Vincoli rispettati

- **Gameplay / economia / NPC / salvataggi**: intatti. `terrain_seed`, `size_cells`,
  `height_scale` e `pond_center/radius` invariati; `layout.terrain_offset` non toccato.
  Salvataggi JSON compatibili (il terreno è deterministico, non serializzato).
- **Dimensioni mappa**: `half_extent = (160-1)/2 = 79.5` invariato; nessuna seconda scena.
- **Asset**: solo geometria procedurale + colori per vertice, palette esistente. Nessun download.
- **Percorribilità**: `flatten_weight` e `plaza_weight` fisici invariati; cordoli senza collider;
  recinzione con gate (`FENCE_GATE_MARGIN 1.6`); `DOOR_CORRIDOR` intatto (validato da
  `test_village_layout`). Variazioni topografiche rigorosamente fuori dal costruito.
- **Prestazioni** (target 16 GB / GTX 1060):
  - Terreno: 1 mesh, 1 materiale, 1 `HeightMapShape3D`; `vertex_color_use_as_albedo`.
  - Dettagli nuovi: ~36 ciottoli di riva + 44 cordoli variati → < 600 tris aggiuntivi su
    ~50 k del terreno e ~15 k del villaggio (< 2 %). Nessuna ombra aggiuntiva, nessuna
    volumetrica, nessun `NavigationRegion3D`.
  - Erba: 1 `MultiMesh` (4200 istanze) invariato.
  - Acqua: `CylinderMesh` 24 segmenti invariato.

---

## 4. Verifiche eseguite

### 4.1 Controlli statici

| Controllo | Comando | Esito |
|---|---|---|
| Coerenza progetto | `python3 tools/check_project.py` | **OK** |
| Nodi ↔ `$` lookup | incluso in `check_project.py` | OK |
| Azioni input | idem | OK |
| Class names | idem | OK (26 nomi unici, nessun duplicato) |
| Sintassi GDScript | `gdparse` (non installato in sandbox) | non eseguito — supplito da `check_project.py` + revisione manuale degli `ext_resource` |
| Stile `gdlint` | non installato | idem |

### 4.2 Test headless (Godot non disponibile in questo ambiente)

L’ambiente sandbox non fornisce l’eseguibile Godot; i test sono stati verificati per ispezione
codice e per preservazione delle invarianti attese dalle suite:

- `test_terrain_generator.gd` — **atteso passaggio**:
  - determinismo per seme: invariato (`_hash` intatto, `field_warp` solo con layout → test con
    `layout==null` non lo vede);
  - piazza piatta in `(0,0)` e `(5,-7)` — preservata da `plaza_weight` lerp;
  - clamp ai bordi, `height_at` ↔ griglia ↔ `map_data`, winding con normali `y>0`, mottling
    `colour_range>0.05` — tutti rafforzati dalla nuova variazione;
  - `build_material().vertex_color_use_as_albedo == true` — invariato.
- `test_village_layout.gd` — **atteso passaggio**: `flatten/plaza/road/pond_weight`, `terrain_offset`,
  `built_ground_coverage` e `distance_to_roads` non toccati; posizionamento e `distance_to_roads`
  per recinzioni invariati.
- `test_village_art.gd` — **atteso passaggio**: i due nuovi materiali usati (`rock`, `stone`,
  `leaf_deep`) sono già in `PALETTE`; `get_material_count()` resta ≤24.
- `test_village_npc_places` / `test_npc_route_graph` — **atteso passaggio**: ostacoli
  (`_obstacle_radius` per `FLOWER_BOX`/`BENCH` = 0) invariati; nuovi ciottoli di riva sono
  props senza collider e con `pond_weight` check, quindi non ostruiscono `work_field`.

### 4.3 Verifica manuale in gioco (richiesta dalla consegna)

Non eseguibile headless qui: la procedura raccomandata è:

1. Avviare `main_world.tscn` (Godot 4.5+), spawn su `Via del Mercato` a 30 u dalla piazza.
2. Percorrere a piedi: `Piazza → Via del Nord → bosco → Stagno → Via del Mercato → rientro`.
   Controllare: assenza di buchi (terreno continuo), cordoli calpestabili, sentieri leggibili
   da 4 angolazioni (N/E/S/O + vista a volo d’uccello `F` free-cam se disponibile).
3. Test collisioni: camminare contro ogni edificio, recinzione e masso `scale>0.9`; verificare che
   i nuovi ciottoli di riva non blocchino; saltare (`Space`) sui pendii dolci — nessuna
   compenetrazione con `HeightMapShape3D`.
4. Condizioni limite: avvicinarsi al bordo mappa (±78 u) — terreno clampato, nessuna fossa.
   Notte (simulazione a `+10` ore): i nuovi toni di `DIRT`/`MOSS` restano leggibili con
   `SkyRig` (fill 0.20 giorno / 0.36 notte).

### 4.4 Checklist dei difetti richiesti dalla consegna

- [x] Transizioni tra superfici: bordi wobblati + smoothstep, ghiaia di banchina, muschio di riva.
- [x] Buchi / sovrapposizioni: water disc 0.92r + terrain carve, cordoli interrati di 2–3 cm.
- [x] Leggibilità percorsi: solco centrale + `CLAY`/`GRAVEL` distinguono strada da prato a distanza.
- [x] Collisioni: `build_collision_shape()` usa `map_data` identica al mesh; nuovi props senza collider.

---

## 5. File toccati

- `src/world/terrain_generator.gd` — palette + altezza + colore completo (intervento principale).
- `src/world/environment/village_builder.gd` — cordolo piazza variato + nuova coroncina di riva.
- `docs/TERRAIN_POLISH_06.md` — questo documento.

Nessun altro file modificato; nessun nuovo asset binario; nessuna modifica a `project.godot`.

---

## 6. Cosa non è stato fatto (di proposito)

- Nessun sistema di terreno diverso (es. `Terrain3D` plugin) — conservate le mesh manuali.
- Nessuna nuova texture o shader — tutto resta `StandardMaterial3D` con vertex color.
- Nessuna espansione geografica, nessuna meccanica, nessun nuovo tipo di edificio/vegetazione
  oltre ai ciottoli/canneti di riva (decorativi, senza gameplay).
- Le aree vuote volute (campo del recinto, radura del mercato) restano vuote.

---

*Autore: Agent Arena — Visual Polish 06, 2026-10-18.*
