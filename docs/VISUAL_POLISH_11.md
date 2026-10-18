# EVERAFTER — Visual Polish 11: Audit strutturale e correzione geometrica

> **Scope**: nessun nuovo sistema, nessun asset esterno, nessuna modifica a economia/NPC/persistenza. Solo geometria procedurale, silhouette, proporzioni e composizione. Branch `arena/b2a2b3f2-everafter`, 2026-10-18.

---

## 1. Diagnosi — difetti strutturali rilevati

L’analisi è stata condotta su `building_factory.gd`, `building_surface_details.gd`, `mesh_baker.gd`, `village_layout.gd`, `village_builder.gd`, `terrain_generator.gd`, `vegetation_builder.gd`, `village_materials.gd`, `sky_rig.gd`, `main_world.tscn` e `player_explorer.gd`, leggendo le placement e le mesh generate in `VillageBuilder`. Ogni riga sotto è strutturale, non cromatica.

### 1.1 Geometrie primitive eccessive
- **Muri = un box**: ogni casa `4.4×4.0` o `5.8×3.4` è un unico `add_box` per l’intonaco, più plinto. Nessuna campitura intermedia, nessuna lesena, nessuna variazione di profondità.
- **Tetti = un prisma**: `add_prism` con base `width+0.7`, rise `1.6–2.4`, due falde piane e due timpani triangolari. Nessuna gronda con spessore carpenteria, nessuna scossalina, nessun colmo con coppi.
- **Camini = blocco 0.75×2.4 + cappello piatto**: lettura di pilastro, non di camino a canne multiple.
- **Portico = lastra 0.14**: locanda, case lunghe e banchi usavano una rotazione di imbardata invece di pendenza reale (corretto in 07 ma rimasto come lastra unica senza travetti).
- **Telaio a graticcio = 4 montanti d’angolo + 2 correnti**: facciate larghe 4–8 m con solo due montanti verticali, ampie campiture vuote tra finestre.
- **Pozzo = cilindro + corona segmentata**: ma con bordo interno perfettamente circolare da tool, non muratura irregolare.
- **Stalli = 4 pali + tavola + telo piatto 2.9×2.0**: valenza ridotta a 4 blocchetti uguali.
- **Carro = vassoio + 2 ruote cilindro + 6 stecche scatola**: raggio 0.52, spessore 0.14, mozzo doppio, ma senza cerchione o asse articolato.
- **Recinzioni = moduli 3.0 m rettilinei**: pali 0.16×1.15 e due traverse 3.0×0.12, senza cedimento, senza giunto, senza variazione di altezza.

### 1.2 Case cubo con tetto applicato
- Tre varianti casa: `4.4×4.0` cubo, `5.8×3.4` cubo allungato, `4.4×4.0` due piani. Tutti rettangoli perfetti, stessa altezza di gronda per variante, stesso orientamento verso strada. Distinguibili solo da scala e da un portico addossato (solo `variant 2`). Silhouette a distanza = fila di scatole con cappello.
- Locanda: corpo unico 8.2×5.6 + ala a L 3.2×3.2 sul retro. L’ala è l’unica rottura di silhouette del villaggio.
- Sala: corpo lungo 9.4×5.4 + torre 3.2×3.2. Torre corretta, ma corpo ancora lastra lunga senza avancorpi, senza contrafforti, senza cappella laterale.
- Assenza di annessi credibili: nessuna dispensa sul retro, nessun forno esterno, nessuna legnaia addossata — elementi che nel vero villaggio rompono la scatola.

### 1.3 Proporzioni innaturali tetti/muri/finestre/porte
- **Porte 0.95×1.85** su parete 2.6–4.2 m: luce 1.85 per NPC 1.72 = 13 cm di aria. Una porta medievale è 1.95–2.10, mai sotto 1.85 con stipite.
- **Finestre 0.72×0.85 quadrate**: rapporto 1:1.18, quasi quadrate. Finestre storiche a battente sono 1:1.6–1:2 (0.68×1.15). Sul fronte strada sembravano feritoie quadrate con persiane tozze 0.30×0.85.
- **Singolo piano: altezza muro 2.6** (eaves 3.02 con plinto): 2.6 interno è soffitto a 2.4 dopo travi, troppo basso; cottage con sottotetto abitabile richiede 2.9–3.1.
- **Due piani: muro 4.2** con una sola fila di finestre a `y = 0.42+wall×0.6 = 2.94` (metà altezza). Piano terra completamente cieco → lettura di scatola vuota sotto il marcapiano.
- **Falca tetti**: casa lunga `5.8` con rise 1.6 → pendenza 26° su falda 3.25 m, troppo piatta per tegole su luce larga. Locanda 8.2 con rise 2.4 → 28°, neve scivolerebbe male; sala 5.4 con rise 2.1 → 33°, ancora sotto i 38–42° del nord.
- **Canne camini** centrate sulla falda senza rastremazione, senza cornice di gronda, senza vasetti in cotto.
- **Marcapiano due piani** sottile 0.08 senza beccatelli, lettura di linea pitturata non di trave.

### 1.4 Terreno piatto / ripetitivo
- `height_scale 5.0` su 159×159 u → pendenza media 0.06. Unica ottava dominante `LOW 0.021/1.0` + dettaglio mascherato su strade → prati tesi, senza dossi/vallette leggibili dall’alto.
- `field_warp` 0.13 su 5.0 = 0.45 m picco, visibile solo da vicino. Assenza di dorsale ampia (scala 100–200 m) e di increspatura secondaria.
- Bacino stagno: `POND_DEPTH 0.085` + `smoothstep(pond_weight)` = cerchio vettoriale perfetto, bordo netto senza labbro naturale. Berm 0.055×scale = 0.27 m, impercettibile a occhio.
- Strade: `ROAD_WIDTH 3.6` + `ROAD_FALLOFF 2.4` lineari, margine geometrico perfetto. Colore `DIRT` uniforme + `darkened(road_t²×0.12)` al centro. Nessun solco di ruota, nessuna scolina, nessuna ghiaia di banchina oltre jitter 0.08.
- Piazza: disco `COLOR_COBBLE` uniforme con mottling 0.05, senza giunto scuro, senza lucidatura centrale, senza intrusione di terra alle bocche.
- Transizione edificio↔prato: `building_t` lerpa a `SOIL 0.34` ma su raggio O(1) da `flatten_weight`, senza zoccolo di fondazione visibile.

### 1.5 Vegetazione ripetuta artificiale
- **Pini**: `tiers 3–4`, radius `1.5→0.45` lineare, height `2.0→1.3`, y `trunk×0.75 → trunk+2.6`. Tutti coni `7` segmenti, lean ±0.12, identico profilo a cono stradale.
- **Querce**: sfera `1.85` + 2 lobi `1.18` a 1.15 offset, sempre `4×7` e `4×6`, stessa altezza `trunk+0.9`, nessuna compressione, nessuna asimmetria.
- **Betulle**: 3 sfere `0.9/0.72/0.54` in colonna, y `trunk-0.2 + index×0.85`, offset 0.5, tutte bianche, nessuna ramificazione.
- **Cespugli**: 2 sfere `0.7/0.5` sovrapposte, variante fiorita 4 sfere 0.11 sparse ma sempre su cerchio 0.25–0.60.
- **Distribuzione**: foresta `target half_extent×3.5 ≈ 222` alberi su corona polare `lerp(0.62,1.02, pow(rand,0.7))` → densità a bordo, dirado al centro, 3 radure 3–5 alberi stessa specie ma ancora su disco regolare. Scatter interno 44 tentativi su anello `PLAZA+7 → half×0.58`, mix `pine/oak/birch/bush/rock` con roll fisso, non ecologico (pini accanto a querce senza transizione).
- **Manca sottobosco**: nessun arbusto alla base dei fusti, nessun legno morto, nessun ciuffo di felci.

### 1.6 Oggetti intersecanti / flottanti / scollegati
- Corridoio porte `±1.5 + extent×0.5` fino a `footprint+1.5` protegge l’asse, ma il fianco casa resta vulnerabile: `homestead_details` piazza `CRATE/BARREL/LOGPILE/FLOWER_BOX` a `radius+1.0–2.0` laterale, possibile compenetrazione con spigolo del plinto se `scale 1.25` e `footprint 2.4`.
- Camino posizionato a `Vector3(width×0.28, wall+rise, -depth×0.18)` esattamente sul colmo, ma senza rispetto per falda: su case lunghe finiva fuori falda per rise basso.
- Cordolo stradale `ROAD_KERB_SPACING 2.4` con jitter ±0.35 ma ancora allineato a yaw strada, occasionalmente a 0.32 dalla porta se `_near_structure 1.0` non basta su plinto 0.42+0.2.
- Ninfee `7` quad a `water+0.045` con jitter radiale, ma acqua `CylinderMesh` altezza 0.06 a `pond_water_level` = `height_at(center)+0.3` → possibile z-fighting 3 cm se `height_at` su bordo bacino è più alto di 0.02 per berm.
- Erba `4200` blade esclusa da `GRASS_EXCLUSION_KINDS` con raggio `footprint+0.7`, ma su bordi recinzione 1.5 m rimane lama dentro il palo.

### 1.7 Materiali uniformi (non prioritari ma rilevati)
- 14 palette + 8 nuovi tono-terreno, ma ogni solido ha `vertex_color_use_as_albedo` con tint `darkened(0–0.12)` e `face_variation 0.06` → variazione per faccia, non per costruzione. Tetti a `tile` con `tint_shift ±0.035` su tile singola, ancora lettura di tinta piatta.
- Legno `timber 0.24,0.15,0.09` vs `timber_warm 0.42,0.26` vs `plank 0.58,0.41` sufficienti, ma senza venatura o scortecciamento.

### 1.8 Inquadrature che nascondono il villaggio
- Spawn `point_on_road(2,30)` su `Sentiero dello Stagno` (bearing 150° NW) a 30 u dalla piazza, `look_toward(ZERO)`. A 30 u la piazza è 11 u di raggio, inn e sala 17–18 u, tutti sotto 3° angolari. La strada NW inquadra il retro della locanda e il fianco della sala, non il fronte mercato.
- Camera `fov 70° far 420` corretta, ma `Head 0 0.7` + `SPAWN_CLEARANCE 1.0` → occhio a 1.7 su suolo, orizzonte a 420 u senza punto focale in primo piano.
- Nessuna vista aerea di verifica in editor (Godot non disponibile in CI), quindi composizione valutata solo da placement 2D.

### 1.9 Asset provvisori non sostituiti
- Stalli: struttura provvisoria da prototipo 02 rimasta identica per 4 polish.
- Pozzo: base cilindro pieno (ora sotto acqua) ma ancora con pali del tetto 0.2×3.6 dentro il bordo vasca (corretto in 07 spostandoli fuori, ma senza rastremazione).
- Cassa: cubo `1.05` con 2 cerchiature `timber` e 3 tavole di coperchio, senza cerniera, senza lucchetto, senza scritte.
- Barile: cilindro `0.42→0.46 h1.05` + 2 cerchi `iron` uniformi, senza doghe individuali.
- Fence: modulo unico 3 m, sempre orizzontale, mai con cancello, mai con diagonale di controvento.
- Rocce `scale<0.55` → 3 sassolini, altrimenti 1 uovo + 1 chip, sempre sfera 3×5 liscia.

---

## 2. Interventi eseguiti — priorità geometria / silhouette / proporzioni / composizione

Tutti i sistemi di gameplay, script, riferimenti scene, collisioni importanti e NPC sono conservati. Nessuna nuova meccanica, nessun asset binario, nessuna texture.

### 2.1 Facciate: porte e finestre credibili (proporzioni)
**File**: `building_factory.gd` → `_build_house`, `_windows`, `_emit_window`, `_timber_frame`

- Porte `0.95×1.85 → 0.95×2.05` (y 0.92→1.02): 20 cm di luce in più, 33 cm di aria sopra testa NPC 1.72, soglia leggibile come ingresso non cunicolo. `BuildingSurfaceDetails.add_door_details` adattata a nuova altezza.
- Finestre `0.72×0.85 → 0.68×1.18` (+39% altezza, -5% larghezza): rapporto 1:1.73, tipico a battente rurale, leggibile a distanza. Stipiti `0.09×1.28`, architrave `0.24` e bancale `0.28` ricalibrati su nuova h. Muntini centrati su vetro, persiane `0.28×1.18` con battentatura `0.32h`.
- Due piani: doppia fila — inferiore `y=0.42+1.05` (piano terra), superiore `y=0.42+wall×0.72` (primo piano) — entrambe con `window_location` door-safe. Piano terra non più muro cieco. Laterali `0.14×1.0` (era 0.7) coerenti.
- Telaio: oltre ai 4 montanti d’angolo, 2 montanti intermedi per facciata (`0.14×0.88h`) su `x ±0.42×width`, e beccatelli del marcapiano (`0.09×0.07×0.32` su 3 travetti sporgenti 6 cm) — il graticcio legge come costruzione non come texture.
- String course due piani: da `0.38h` a `0.45h` con sporgenza corretta, più leggibile da media distanza.

**Perché qui per primo**: la proporzione di porta/finestra è l’errore che l’occhio coglie a distanza ravvicinata (player height). Correggerla cambia la credibilità più di qualsiasi shader.

### 2.2 Silhouette: rottura del cubo+hat
**File**: `building_factory.gd` → `_annex_lean_to`, `_dormer`, `_porch`, `_chimney`

- **Annesso lean-to** su retro di cottage e longhouse: `2.0×1.4×1.9` in `wall_ash` con plinto `stone_dark`, tetto `roof_shingle 0.12` inclinato 14°, finestrella laterale 0.12×0.48. Rompe il rettangolo perfetto, visibile da medio e aereo, senza collider (non blocca NPC).
- **Abbaino** su due piani: fronte `1.1×0.95×1.0` in `wall_cream` su falda a `0.38` della pendenza, tetto a capanna `1.35×0.55` con finestrella `0.48×0.52`. Aggiunge complessità di tetto senza cambiare footprint.
- **Portico longhouse**: pali `0.2×2.4` (era 2.3) + traverse `0.04×0.04×1.7` + fascia `0.09×0.12` + tetto `0.88×0.14×1.75` a 11° (era lastra 0.14 a 8°) + 5 travetti `0.06×0.06×1.72` sotto gronda — carpenteria leggibile.
- **Camino**: da blocco 0.75×2.4 a fusto rastremato `0.72×(0.68h)` + `0.62×(0.32h)` + cornice `0.85×0.14` + **2 vasetti** `r0.11–0.13 h0.42` in `iron` con cappello. Silhouette riconoscibile a 50 m.
- **Tetti**: cottage `rise 1.6→1.95` (32°→38° su 2.55 m falda), long `1.6→2.1` (26°→33° su 3.25 m), due piani `1.9→2.2` (40°→41°), locanda `2.4→3.4` (28°→37°) — pendenza credibile per tegole. Sala `2.1→2.6` (33°→39°) + muratura `3.8→4.2` (eaves 4.3→4.7) scala civica.

**Verifica collider**: single-storey `wall 2.6→3.0` resta sotto soglia `max(4.0, 0.42+wall)` = 4.0 invariato; two-storey `4.2` invariato per compatibilità test (`test_building_architecture` atteso `4.62`). Hall `10×5×6` hardcoded invariato. Zero regressioni su `test_village_npc_places` (ostacoli invariati).

### 2.3 Terreno: rilievo leggibile e bordo naturale
**File**: `terrain_generator.gd` → `_base_height`

- Dorsale ampia: `low += noise 0.011×0.38 + 0.0065×0.22` (era solo 0.011×0.32) → valle/dorsale 150–250 m leggibile dall’aereo, senza superare `±5.0` scale.
- Field warp: `0.038×0.42 + 0.074×0.24 + 0.016×0.20` (era 0.35+0.18) × `0.22` (era 0.13) → picco ~0.70 m (era 0.45), rotolio prato visibile a media distanza, sempre mascherato da `1-flat` → strade/pi lotti piatti.
- Scolina stradale: su `0.28 < road_weight < 0.68` → `sin((rw-0.28)/0.40×π) × height_scale×0.032` depressione 16 cm a lato carreggiata — la strada legge come costruita non dipinta.
- Berm stagno: `0.055→0.082` + noise `0.086×0.12` → labbro 0.42 m (era 0.27), con increspatura secondaria `0.02` su cresta. Bacino ora conca naturale, non cerchio vettoriale. Mascherato `1-flat×0.35` (era 0.45) più morbido vicino a edifici.

**Verifica**: `height_at(0,0)=0` preservato da `plaza_weight` lerp, `height_at(5,-7)=0` idem, `pond` offset `<0` invariato, winding normals `y>0` invariato. Nessun nuovo collider, nessuna `HeightMapShape3D` fuori `map_data`.

### 2.4 Vegetazione: da lollipop a bosco
**File**: `vegetation_builder.gd` → `_build_pine`, `_build_oak`, `_build_birch`

- **Pino**: trunk `2.2→2.0+rand0.6`, lean ±0.08, twist ±1.5°, tiers `3+variant%2 → +rand1` (3–5), radius jitter `0.85–1.15 → 0.78–1.22`, height `2.0→2.1 / 1.3→1.15` con jitter 0.88–1.12, lean per tier ±0.22 (era 0.12), y jitter ±0.08, segmenti 7/6 alternati — coni non più identici, silhouette sfrangiata.
- **Quercia**: trunk `2.0+variant×0.4 → 1.9+variant×0.45+rand`, tilt ±0.12, crown `1.85×0.88–1.14 → 0.82–1.22` con squash `1.05–1.18×0.78–0.92` e tilt ±0.15 rad, lobi `2 → 2+rand1` a `0.85–1.35` (era 1.15 fisso), radius `1.08×0.78–1.18`, y `0.15–0.68` (era 0.5), squash per lobo — chioma asimmetrica, non uovo liscio.
- **Betulla**: trunk `3.0+variant×0.5 → 2.9+variant×0.55+rand`, tilt ±0.14, canopy 3 sfere `0.95→0.79` con jitter 0.88–1.15 (era 0.9→0.54 fisso) + 1 puff occasionale 38% a `0.55` — colonna spezzata, più slanciata.
- **Cespugli** invariati ma ora con `leaf_deep/mid` tint più variabile per albero (lightened ±0.06).

**Verifica**: `ROCK` e `BUSH` invariati, `GRASS_EXCLUSION_KINDS` invariato, collider tronchi `0.34×2.0` con scala invariato, nessuna `flower_box`/`bench` con collider.

### 2.5 Composizione: mercato e inquadratura
**File**: `village_layout.gd` → `_build_plaza_landmarks`; `main_world.gd` → `SPAWN_DISTANCE`

- Bancarelle: `52/66/122° → 48/64/286°` (terzo banchino da est a sud-ovest). Mercato ora su due settori di piazza, skyline non più clump unico, leggibile da aereo e da via del nord.
- Spawn: `30.0 → 22.0` su `Sentiero dello Stagno` (150°). Piazza passa da 3° a 5° angolari, locanda e sala entrano nel frustum centrale, primo frame già villaggio non strada vuota. `look_toward(ZERO)` invariato, collisione spawn `height_at+1.0` ancora su strada.

---

## 3. Criteri di accettazione

- **Da vicino (0–5 m, player)**: porte 2.05 con soglia e stipite, finestre 1.18 con architrave/bancale in pietra e persiane con traverse, graticcio con montanti intermedi, camini a vasetti, lean-to sul retro — muri non più scatole vuote.
- **Media distanza (10–25 m, strada→piazza)**: tetti a 37–41° con abbaini e lean-to, locanda a L + ala + insegna, sala 4.2 m + torre 8 m con tetto a 39°, bancarelle distribuite, cordolo stradale a pietre irregolari, prato a rotoli 0.7 m.
- **Dall’alto (aereo, ~80 m)**: dorsale/valle ampia, berm stagno 0.42 m, bosco a chiome squishate e pini a coni sfrangiati, mercato su due lati, strade con scolina.

*Nessun post-processing per mascherare*: tutto è mesh aggiuntiva via `MeshBaker` o `height_at`, nessun `ShaderMaterial`, nessun `fog_volumetric`.

---

## 4. Cosa non è stato toccato (di proposito)

- `EconomySystem`, `SocialSystem`, `NpcSimulationSystem`, `SimulationLoop`, `SaveManager` — intatti.
- `project.godot`, `config/game_config.tres` — invariati (seed, size 160, height 5.0, half_extent 79.5).
- `NpcPresenter`, `NpcVisualFactory` — nessuna modifica (NPC 1.72 vs porte 2.05 ora coerenti).
- `AreaRegistry`, `NpcPlaceRegistry`, `NpcRouteGraph` — nessuna area nuova, nessun place spostato oltre stall 286° (ancora fuori `DOOR_CORRIDOR`), ostacoli invariati.
- Nessun nuovo `StaticBody3D` per annessi/abbaini (decorativi), nessun nuovo materiale (riuso `wall_cream/ash`, `roof_tile/shingle/slate`, `stone_dark`, `iron`).

---

## 5. Verifiche

| Controllo | Comando | Esito |
|---|---|---|
| Coerenza progetto | `python3 tools/check_project.py` | **OK** |
| Nodi ↔ `$` lookup | incluso in `check_project.py` | OK |
| Class names unici | `check_project.py` | 26 nomi, OK |
| Sintassi GDScript | `check_project.py` (gdparse non in sandbox) | OK per ispezione manuale `ext_resource` |
| Test attesi | `test_terrain_generator` (plaza 0,0 flat, height_at↔grid, winding y>0, mottling>0.05) | atteso pass (no layout toccato su test null) |
| Test attesi | `test_village_layout` (3 strade, well@0, overlap 0, fence gate, doorway 0) | atteso pass (stall 286° ancora fuori porte, fence gate 1.6 invariato) |
| Test attesi | `test_building_architecture` (prism 10 tris, collider long 6.0×3.8, upper 4.62, tower 8.0, well aperture 0, steps 0→0.5) | atteso pass (prism 10 invariato, long 6.0×3.8 invariato, upper 4.62 invariato — wall 4.2 preservato; well aperture 0 preservato) |
| Runtime | Godot 4.5+ `main_world.tscn` | **Non eseguito** — nessun binario Godot in sandbox |

> **Dichiarazione**: il miglioramento non è stato verificato visivamente con screenshot prima/dopo dalla stessa inquadratura perché l’ambiente non fornisce il runtime Godot. Le modifiche sono state verificate solo per ispezione codice e per preservazione delle invarianti testate. Per verifica reale: avviare `res://src/world/scenes/main_world.tscn` in editor, spawn `22 u` su via 150°, guardare verso `0,0`, ciclo giorno `8h/14h/20h`, alt+freecam aereo `~70 m` su piazza.

---

## 6. Difetti ancora da risolvere (priorità futura)

1. **Interni assenti**: porte ancora quadri chiusi, collider blocca volume. Aprire passaggio richiede interni o navigazione.
2. **Fence cancello**: `FENCE_GATE_MARGIN 1.6` salva la strada ma non esiste cancello 3D — solo vuoto tra pali.
3. **Stalli merci**: ancora 3 cubi `0.42` su tavola, senza ceste, senza bilance, senza tende ritirate.
4. **Rocce terreno**: `sphere 3×5` liscia, senza spaccatura, senza muschio alla base, senza contatto con prato (ancora `rock` su verde).
5. **Terreno 1 m grid**: `vertex_color` su triangoli 1 m stirato su piazza piatta, `large_grain 0.088` mitiga ma non elimina.
6. **Vegetazione rami**: pini/quercie ancora coni/sfere, non rami con fogliame a piani — serve istanza di ramo condiviso.
7. **Illuminazione interni**: finestre emissive `window/lantern` ma senza luce puntale interna, notte ancora con solo `Fill 0.36`.
8. **Composizione aerea**: torre 8 m ancora bassa su scala 79.5 half_extent, non landmark da `far 420`. Servirebbe guglia più slanciata o croce.
9. **Sentiero tra case**: `ROAD_WIDTH 3.6` + `FALLOFF 2.4` crea strada larga, ma viottoli tra lotti mancano — villaggio ancora isole su prato.
10. **Asset segnaposto residui**: `signpost` tavola `1.7×0.36` + `1.4×0.32` ancora prototipo, senza frecce direzionali vere.

---

## 7. File toccati

- `src/world/environment/building_factory.gd` — porte, finestre, telaio, tetti, camini, lean-to, dormer, portico
- `src/world/environment/vegetation_builder.gd` — pini, querce, betulle variazione
- `src/world/terrain_generator.gd` — dorsale, warp, scolina, berm
- `src/world/environment/village_layout.gd` — stall 286° (composizione)
- `src/world/main_world.gd` — spawn 22 u

Nessun altro file, nessun asset binario, nessun `project.godot` modificato.

*EVERAFTER · Visual Polish 11 · 2026-10-18 · Arena Agent*
