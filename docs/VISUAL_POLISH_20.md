# EVERAFTER — Visual Polish 20: revisione finale di paesaggio e architettura

Revisione artistica finale del mondo 3D esistente, considerando tutte le modifiche grafiche precedenti (Polish 06–19). **Nessuna nuova funzionalità, nessuna ricostruzione da zero, nessun nuovo sistema di simulazione.** Il lavoro si concentra sui difetti residui che incidono di più sulla qualità percepita dalla telecamera di gioco; gli elementi già riusciti (tetti del kit `RoofArchitecture`, alberi a scheletro+foglie di Polish 18, composizione di Polish 19, pavimentazione di Polish 15) non sono stati modificati.

> Riferimenti: `src/world/environment/building_factory.gd` (recinzioni, cataste, arredi), `src/world/environment/building_architecture.gd` (fondazioni, gradini, variazione tetti), `src/world/environment/mesh_baker.gd` e `village_materials.gd` invariati, `docs/VISUAL_POLISH_12-19.md` per il contesto.

---

## 1. Metodo — revisione statica, non visiva

**In questo ambiente non è disponibile un eseguibile Godot.** Il download da `github.com` e `objects.githubusercontent.com` fallisce con `SSL_ERROR_SYSCALL` (vedi §5), non esistono pacchetti `godot` in `apt` e il repository non include binari. Di conseguenza:

* **Nessuno screenshot reale è stato acquisito** (né vista generale, né livello giocatore, né dettaglio edificio, né area naturale).
* **Nessuna misura di triangoli/draw-call/collider è stata presa dal motore**; i numeri sotto sono conteggi statici o letti dal log di Polish 15 (175 mesh, 230 740 triangoli, 346 collider — ultima misura reale).
* Tutte le diagnosi sotto derivano da **lettura del codice**, confronto tra polish precedenti e verifica dei placement a partire da `VillageLayout` (stesso seed `20261016`, `160x160` celle, `half_extent 79.5`).

La revisione è quindi **soltanto statica**; non vengono inventati risultati visivi o misurazioni di prestazione dal motore.

Cosa è stato controllato a codice:

* `VillageLayout` — posizione, footprint e regole di rigetto di tutti i placement (plaza, 3 strade, 13 case, locanda, sala, 3 banchi, 14 recinzioni, 6–8 lampioni, ~285 alberi, 18 rocce di riva + 18 outcrop di versante, 22 cluster di fiori, ecc.).
* `BuildingArchitecture` + `RoofArchitecture` — kit tetti, gronde, abbaini, camini, plinti, scale.
* `BuildingFactory` — tutti i prop piccoli (cassa, barile, catasta, carro, panchina, fioriera, lampione, recinzione, pozzo, banco).
* `GroundSurfaces` — plaza, strade, piazzole porte, cordoli.
* `TerrainGenerator` + `TerrainRelaxer` — pendenze, spalle stradali, orizzonte, piazzole.
* `VegetationBuilder` + `MeadowBuilder` — alberi, cespugli, rocce, erba.
* `SkyRig` — luce e nebbia (invariato in questo polish).
* `VillageBuilder` — assemblaggio, gerarchia dei nodi, collider, orientamento delle rocce sul pendio.

Verifiche statiche eseguite (vedi §5): `python3 tools/check_project.py` **OK**, `gdparse` su tutti i file toccati **OK**, `gdlint` **0 problemi** sui file modificati. Le suite headless Godot (`run_tests.gd` e `run_world_tests.gd`) **non sono state eseguite**.

---

## 2. Diagnosi — difetti principali rimasti (prima di questo polish)

### 2.1 Geometria degli edifici e dei prop

1. **Recinzione “timbrata”.** 9 moduli sul lato sud-est + 5 sul risvolto = 27 m di steccato identico: pali `0.16×1.15` h sempre uguale, cima a punta identica `r0.13 h0.20`, due traverse `3.0×0.12` perfettamente orizzontali. Da media distanza la ripetizione è immediata; manca il controvento diagonale che il vero recinto ha ogni 2–3 campate.
2. **Catasta “tubi”.** 9–10 cataste (3 lungo le strade + 6 nei cortili) ognuna con `4+3+2=9` tronchi identici `Ø0.28 l2.4`, tutti paralleli, stesso colore per fila `darkened(row*0.05)`, nessuna variazione di lunghezza/diametro/inclinazione. Da 3 m si legge come un pacco, non come legna tagliata.
3. **Arredi a filo sospeso.** `Crate` (cubo `1.05`), `Barrel` (cilindro `h1.05`), `FlowerBox` (cilindro `h0.52`), `Bench` (piedi `h0.16`) e `Lamp` (basetta `h0.35`) hanno il fondo esattamente a `y=0` sul `height_at` del loro centro. Su pendenze erbose tipiche (0.08–0.15 di slope fuori dalle piazzole) il filo a valle galleggia di 2–4 cm, visibile a 1.7 m di altezza occhio. Lo stesso vale per i gradini `stone_dark h0.14` + `stone h0.28` davanti alle porte e per il plinto `stone_dark h0.42` delle case.
4. **Cassa e barile ancora provvisori.** La cassa è un cubo `plank` con 2 cerchiature `timber` + 3 assi di coperchio + 4 montanti d’angolo: leggibile a 2 m ma senza cerniera/lucchetto/scritte e con proporzioni da scatola. Il barile è un cilindro liscio `10` segmenti + 2 cerchi `iron`: manca la lettura delle doghe verticali. Non sono stati toccati in questo polish perché non sono il difetto più visibile dalla camera di gioco, ma restano asset provvisori.

### 2.2 Silhouette e proporzioni dei tetti

5. **Tetti “copia-incolla”.** Le tre varianti casa hanno già pendenze diverse (`pitch_scale` 0.94–1.07, `rise` 1.85–2.20) e `overhang`/`bell_cast` variati per `house_id`, ma la copertura è ancora `wall_cream/roof_tile` per tutte le `v0`, `wall_ochre/roof_shingle` per le `v1`, `wall_pale/roof_slate` per le `v2`, con solo 7 eccezioni esplicite (`19,24,28→moss`, `16,27→shingle`, `21,25→tile`). Su 13 case, 3–4 condividono identica coppia muro/tetto, leggibile come ripetizione a distanza media.

Le altre qualità del kit tetti (gronda, corsi, colmo, timpano, abbaino, camino, torre) sono già riuscite e non sono state toccate.

### 2.3 Materiali di legno, pietra e coperture

6. **Variazione solo per-vertice.** `VillageMaterials` ha già 30+ colori con `roughness` 0.78–0.96 e `vertex_color_use_as_albedo`, ma le facciate usano sempre gli stessi 4 intonaci e i tetti gli stessi 4 manti. La `tint_shift` esistente `[-0.05,+0.04]` è al limite inferiore per rompere la ripetizione da 15 m.

Pietra e legno sono coerenti (intonaco caldo, pietra calda `stone`, legno noce scuro `timber`, tegole `roof_tile` ecc.) e non richiedevano correzioni.

### 2.4 Terreno, pendenze e transizioni

7. **Bordi orizzonte ancora geometrici.** `HORIZON_RIM_WIDTH 14.0 × HORIZON_RIM_HEIGHT 0.70 × height_scale 5.0 = 3.5 m` di rialzo al bordo, con rumore `0.028` + `0.012`. Da occhio (far 420) il bordo quadrato della mesh `160×160` resta leggibile come una cornice sollevata, soprattutto dove le 3 strade escono con sella `0.28` — voluto, ma ancora artificiale su mappa piccola.
8. **Transizione edificio↔prato solo a colore.** Il `TerrainGenerator` dipinge `COLOR_SOIL`/`COLOR_GRAVEL` attorno alle case via `building_t`, ma non c’è un bordo geometrico (ghiaia, zoccolo) tra plinto e prato: da 2 m il plinto sembra appoggiato su prato tinto, non su ghiaia compattata. Il difetto è minore (non è un bordo di piazza) e non è stato corretto in questo polish per non aggiungere una nuova mesh.

### 2.5 Sentieri e piazza

9. **Bocche strada.** Già corrette in Polish 15 (cordolo che lascia il varco, `distance_to_roads <3.35` scarta le celle di piazza). Residuo minimo: la piazzola porta (`APRON_LENGTH 1.55`) finisce a `0.05 m` dalla carreggiata, quindi tra soglia e strada resta una striscia d’erba di 5 cm che a raso può leggere come una giunzione. Non corretto qui perché richiederebbe riprogettare la griglia della piazzola.

### 2.6 Vegetazione e rocce

10. **Dettaglio a distanza netto.** `DETAIL_RADIUS 22 m` (Polish 18) — dentro: querce `810` tri, abeti `505` tri; fuori: `170–270` tri. A 25–30 m (bordo villaggio visto dalla piazza) la transizione è un salto di sagoma, non un LOD continuo. Accettato in Polish 18 per tenere il budget sotto `90 k` tri, qui non modificato perché aumentare il raggio avrebbe sforato il margine `~29 k` di Polish 15.

Rocce già corrette in Polish 17 (`add_rock` stratificato, base interrata, allineamento al pendio via `_surface_transform`, talus di 1–2 chips): nessuna correzione necessaria.

### 2.7 Primo piano / villaggio / sfondo — intersezioni — camera di gioco

11. **Nessun difetto di occlusione aggiuntivo** rispetto a Polish 19: le `arrival sightline` (pozzo–stagno `5.0 m`, strada–piazza `4.5 m`, corridoio d’arrivo `3.2+2.2 m`) e i `VISTA_KNOTS` sono già verificati. Le 7 viste bloccate residue sono canyon realistici (fine strada = muro di case) e leggono come tale; il campanile resta visibile come “solo cima”.

12. **Intersezioni residue minori.** Pozzo: corona `stone` lascia l’apertura `r0.92` (verificato da `test_building_architecture`), acqua a `y0.72` non interseca pietra. Stagno: disco acqua `r*0.92 h0.06` a `pond_level+0.3` non fa z-fighting col terreno (bacino `POND_DEPTH 0.085`). Recinzione: cancello già libero (`FENCE_GATE_MARGIN 1.6` > `ROAD_WIDTH 0.5`). Nessuna superficie sospesa critica oltre i fili di §2.1.3.

---

## 3. Correzioni effettivamente realizzate (solo queste)

Tutte le correzioni sono **geometriche e di tinta**, senza nuovi materiali, texture o collider, senza spostare placement, strade, piazza, stagno o dimensioni mappa.

### 3.1 Recinzione — irregolarità misurata

*File:* `src/world/environment/building_factory.gd` → `_build_fence()`

*Prima:* 2 pali cubici identici `0.16×1.15` + punta `r0.13 h0.20` + 2 traverse `3.0×0.12`.

*Ora:*

* altezza pali `1.15 ±0.05` (jitter indipendente per palo), spessore `0.16 ±0.015`, cappello `r0.11–0.15 h0.16–0.21` con tinta `darkened(0–0.04)`;
* traverse `l3.0 ±0.04`, spessore `0.11±0.015 × 0.08±0.015` con tinta `darkened(0–0.05)` e `post_jitter` verticale `±0.06`;
* controvento diagonale `0.09×1.05` a `34°` su ~52 % dei moduli, che rompe la maglia rettangolare senza chiudere il cancello e senza collider aggiuntivo.

*Effetto:* 27 m di steccato non leggono più come un pezzo unico; il cancello carraio resta libero (`distance_to_roads` già verificato).

### 3.2 Catasta — variabilità di taglio

*File:* `src/world/environment/building_factory.gd` → `_build_logpile()`

*Prima:* 9 tronchi identici `Ø0.28 l2.4` paralleli, `y = 0.30 + row*0.55`.

*Ora:* per tronco `l = 2.4 −0.18/+0.12`, `Ø = 0.28 −0.03/+0.025` (base `*0.95` in punta per leggera conicità), `x ±0.04`, `z ±0.04`, `yaw ±3.5°`, `y = 0.28 + row*0.52 ±0.02`, tinta `darkened(row*0.04 + 0–0.03)`.

*Effetto:* la catasta d’imbocco (primo lotto di ogni strada, `PLOT_MOUTH_YARD_DEPTH 6 m`) — che Polish 19 ha reso il bordo del villaggio — non legge più come un bancale.

### 3.3 Arredi e lampione — chiusura del filo su pendenze

*File:* `src/world/environment/building_factory.gd` → `_build_crate`, `_build_barrel`, `_build_flower_box`, `_build_bench`, `_build_lamp`

* `Crate` — base interrata `embed = 0.04*scale` (da `y size*0.5` a `size*0.5−embed`).
* `Barrel` — `embed = 0.05` per fusto e cerchi (da `y0.52/0.25/0.80` a `y−embed`).
* `FlowerBox` — `embed = 0.04*scale` per tino, cerchi e terra.
* `Bench` — `embed = 0.03` per piedi in pietra e telai.
* `Lamp` — basetta `h0.35→0.38` a `y0.16` (invece di `y0.18`), palo a `y1.87` (invece di `1.90`).

*Effetto:* su pendenze erbose fuori piazzola il filo a valle non mostra più il “giorno” sotto l’oggetto; l’interramento è <5 cm, quindi su piazzola già piana non si nota.

### 3.4 Fondazioni e gradini — zoccolo interrato

*File:* `src/world/environment/building_architecture.gd` → `_foundation()`, `_steps()`

* `Foundation` — da `Vector3(w+0.18, 0.42, d+0.18)` a `Vector3(0,0.21,0)` → `Vector3(w+0.18, 0.48, d+0.18)` a `Vector3(0,0.18,0)` (altezza `+6 cm`, centro `−3 cm`): lo zoccolo scende 3 cm sotto il filo terreno.
* `Steps` — da `y0.07/y0.14` a `y0.04/y0.11` (`−3 cm`).

*Effetto:* il plinto non mostra più luce su pendenze di 6–8 % (tipiche appena fuori `PLOT_FALLOFF 2.6`); i gradini non galleggiano.

### 3.5 Variazione delle coperture — rottura del “copia-incolla”

*File:* `src/world/environment/building_architecture.gd` → `_house_variation()`

* Oltre alle 7 case-simbolo fissate (`19,24,28→moss`, `16,27→shingle`, `21,25→tile`), il 12 % delle restanti riceve `roof_moss` spontaneo (`posmod(num*17+v*31,100)<12`) e un ulteriore 6 % di `roof_tile` diventa `roof_slate` (`moss_hash 12–17`). Deterministico su `house_id`, quindi stabile tra salvataggi.
* `tint_shift` esistente `[-0.05,+0.04]` allargata di `±0.012` (`(posmod(num*29+v*7,5)−2)*0.006`) per variazione per-vertice senza nuovi materiali.

*Effetto:* su 13 case, 1–2 in più hanno `roof_moss` e 1–2 `roof_slate` inattesi, senza toccare le case-simbolo; da 20 m la fila non è più 4× identica.

*Cosa non è stato cambiato di proposito:* `RoofArchitecture` (gronde, corsi, colmo, timpano, abbaino, camino, guglia), `MeshBaker` (primitive), `VillageMaterials` (palette), `GroundSurfaces` (piazza/strade), `SkyRig`, `TerrainGenerator`/`TerrainRelaxer`, `VegetationBuilder`/`MeadowBuilder` — già riusciti.

---

## 4. Asset sostituiti e asset ancora provvisori

| Asset | Stato dopo Polish 20 |
|---|---|
| **Case / Locanda / Sala / Pozzo / Banchi** | **Sostituiti** (kit `BuildingArchitecture` + `RoofArchitecture` da Polish 12/13/07, qui solo fondazione interrata e variazione tetti). Non più provvisori. |
| **Recinzione** | **Sostituita** (da modulo identico a modulo con jitter e diagonale). Non più provvisoria. |
| **Catasta** | **Sostituita** (da tubi identici a tronchi con variazione di taglio). Non più provvisoria. |
| **Lampione** | **Ritoccato** (base interrata). Ancora semplice (palo `6` lati, mensola `0.7×0.1`, lanterna `0.34×0.44`): accettabile come arredo, ma resta il modello più povero del set. |
| **Panchina / Fioriera** | **Ritoccate** (interrate). Geometria già buona (piedi in pietra, doghe, fiori `cloth_red/cream/leaf_bright`): non più provvisorie. |
| **Cassa / Barile / Carro / Segnaletica** | **Ancora provvisori.** Cassa: cubo `1.05` con 4 montanti + 3 assi di coperchio; barile: cilindro `10` lati + 2 cerchi; carro: vassoio `1.7×2.9` + 2 ruote `r0.52` + 6 razze; segnaletica: palo `2.5 m` + 2 assi. Leggibili da 2 m ma senza doghe/assi individuali o ferramenta completa. Sono i prossimi da rifare, non hanno mosso la priorità di questo polish (visibili solo nei cortili, non nella vista d’arrivo). |
| **Vegetazione / Rocce / Erba / Acqua** | **Sostituiti** (Polish 16/18 + outcrop 17, qui invariati). Non più provvisori. |
| **Terreno / Piazza / Strade / Cordoli** | **Sostituiti** (Polish 14/15, qui invariati tranne l’interramento dei plinti che chiude il filo). Non più provvisori. |

Nessun modello binario, texture o shader è stato aggiunto; il repository resta solo-testo.

---

## 5. Problemi tecnici riscontrati

1. **Godot non disponibile in questo ambiente.** `curl -L https://github.com/godotengine/godot/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip` → `302` verso `objects.githubusercontent.com` → `SSL_ERROR_SYSCALL` su `release-assets.githubusercontent.com:443` e su `objects.githubusercontent.com:443`. `pip install godot` non esiste, `npm`/`registry.npmjs.org` non fornisce Godot. Il repository non include binari e non esiste un Godot headless pre-installato (`which godot` / `godot4` / `/usr/local/bin/godot` → non trovato). Di conseguenza **nessuna suite Godot è stata eseguita**.

2. **gdtoolkit non preinstallato.** `gdparse`/`gdlint` non trovati di default; installato via `pip install gdtoolkit --break-system-packages` (4.5.0). Nessun errore di lint sui file modificati dopo l’installazione; i 12 warning di stile di Polish 07 su file non toccati (autoload, cronaca, persistenza) persistono ma non riguardano questo polish.

3. **Nessun altro errore di build.** `python3 tools/check_project.py` → `RESULT: OK` (90 class_name, 0 duplicati, .gitignore coerente). `gdparse` → `Success: no problems found`. `git diff --check` → `OK`.

---

## 6. Test realmente eseguiti

| Test | Strumento | Esito |
|---|---|---|
| Coerenza progetto: scena principale, autoload, `res://`, `ext_resource`/`sub_resource`, percorsi `$Nodo`, azioni `project.godot`, `.gitignore` | `python3 tools/check_project.py` | **Eseguito — OK** |
| Sintassi GDScript su tutti i file toccati + 2 file di supporto | `gdparse` 4.5.0 (`/usr/local/bin/gdparse`) | **Eseguito — Success** |
| Stile GDScript sui file modificati | `gdlint` 4.5.0 | **Eseguito — 0 problemi** |
| Headless unit suite (`tests/run_tests.gd`, 1162 asserzioni in Polish 05) | `godot --headless --script res://tests/run_tests.gd` | **Non eseguito — Godot non disponibile** (vedi §5) |
| Integrazione mondo (`tests/run_world_tests.gd`, 113 asserzioni) | `godot --headless --script res://tests/run_world_tests.gd` | **Non eseguito — Godot non disponibile** |
| Confronto visivo (`tests/visual/building_review.tscn`, `paving_review`, `vegetation_review`, `composition_review`) | `godot --path . res://tests/visual/*.tscn` | **Non eseguito — GPU non disponibile, nessun screenshot** |

Non vengono dichiarati come passati test non eseguiti. Le nuove asserzioni compositive di Polish 19 (3 banchi, primo lotto catasta, sightline, nodi, lampione per strada) non sono state rieseguite col motore, ma il codice di placement non è stato mosso da questo polish (solo la geometria dei prop), quindi restano valide sul placement.

---

## 7. Limiti grafici ancora evidenti (dopo Polish 20)

* **Cassa / barile / carro / segnaletica** ancora low-poly e ripetitivi da vicino (vedi §4). A 0.8 m si contano i poligoni della cassa; il barile non mostra le doghe verticali.
* **Interni assenti.** Porte e finestre sono superfici chiuse; porte apribili, interni e navigazione interna non esistono — i collider bloccano ancora il volume dell’edificio (scelta intenzionale: aprire un passaggio senza interno sarebbe peggio).
* **Terreno a griglia 1 m.** Su pendenze dolci (micro-rilievo `0.065`/`0.12` + plinti) la sfaccettatura `1×1 m` si legge a raso; servirebbero `0.5 m` o un normal map del terreno (fuori budget di questo polish senza texture).
* **Bordo orizzonte quadrato.** Il rialzo `HORIZON_RIM 3.5 m` con sella alle strade nasconde il bordo quadrato della mesh `159×159 u`, ma da 60 m di quota (F4 aereo di `building_review`) la cornice resta geometricamente quadrata.
* **LOD vegetazione a salto.** `DETAIL_RADIUS 22 m` tiene il budget sotto `90 k` tri, ma a 22–28 m la chioma passa da `~600` a `~200` tri con un salto di sagoma visibile se il giocatore si ferma sul confine; un morph continuo richiederebbe un sistema LOD non previsto.
* **Conifere low-poly da vicino.** Verticillo a `12` punte (72 tri): a 1.5 m si contano le punte, come dichiarato in Polish 18. Accettato per il budget.
* **Una sola ombra.** `Sun` unica con `shadow_enabled`, `Fill` senza ombre, `SSAO` + `glow` + fog (mai volumetrica) — corretto per GTX 1060, ma le facciate in ombra non proiettano occlusione tra loro.
* **Resa visiva non verificata su GPU.** Geometria, materiali e collisioni sono verificati staticamente; l’aspetto finale (bilanciamento luce, saturazione `leaf_bright`/`roof_moss`, nebbia a `0.0028/0.0042`) va giudicato a schermo su Windows con Godot desktop — come dichiarato in ogni polish dal 06 in poi.

---

## 8. File modificati e costo

| File | Intervento |
|---|---|
| `src/world/environment/building_factory.gd` | recinzione con jitter e diagonale, catasta con variazione di taglio, interramento crate/barile/flower_box/bench/lamp |
| `src/world/environment/building_architecture.gd` | fondazione e gradini interrati, variazione tetti (moss spontaneo + slate su tile, tint_shift allargata) |
| `docs/VISUAL_POLISH_20.md` | questo resoconto |
| `docs/VISUAL_POLISH_11.md` … `VISUAL_POLISH_19.md`, `README.md` | invariati (README elenca già le fasi; l’indice verrà aggiornato al merge) |

*Nessun nuovo materiale, mesh o draw call:* i prop restano fusi per materiale (`MeshBaker`), l’erba resta `MultiMesh` a 1 draw call, i collider restano `346` (limite `900`), le mesh `~175` (limite `260`). Il budget triangoli non si muove in modo misurabile (recinzione `+2` tri per modulo con diagonale, catasta `0` tri in più, fondazione `0` tri).

---

## 9. Coerenza della scena vista dalla telecamera di gioco

* **Vista generale (spawn `22 m` su `Sentiero dello Stagno`, verso `0,0`)** — *non acquisita* (motore non disponibile). In base al placement, inquadrerebbe: pozzo al centro, banchi mercato a `44°/63°`, locanda `90° r17.5`, sala `210° r18.5` con campanile `12 m`, recinzione a sud-est con cancello, cataste d’imbocco basse, lampione d’imbocco su ogni strada.
* **Livello giocatore (1.7 m)** — i plinti e i gradini interrati chiudono il filo; le cataste variate non ripetono; la recinzione non legge come timbrata.
* **Dettaglio edificio (cottage `v0` a `330° r15.5` e casa a due piani `v1`)** — plinto interrato, timpano in intonaco già corretto in Polish 07, tetto con `tint_shift` allargata; nessuna nuova intersezione introdotta.
* **Area naturale (riva stagno `33,-27 r8.5` e prato sud `222°`)** — ninfee `7`, sassi di riva `18×2` anelli, canne, fiori `8` chiazze, outcrop di versante `18` con talus; nessuna intersezione con strade o porte (verificato via `distance_to_roads` e `pond_weight`).

Tutti i riferimenti alle scene (`res://src/world/scenes/main_world.tscn`, autoload `EventBus`/`Game`, `SkyRig`, `Village`, `Player`) restano validi (`check_project.py` OK). Nessuna collisione, navigazione o funzionalità esistente è stata danneggiata (i collider sono invariati).

> **Nota sulla numerazione:** la serie documentale contiene già `VISUAL_POLISH_18.md` e `VISUAL_POLISH_19.md`; questo intervento continua la serie come **20** senza sovrascrivere i resoconti precedenti.
