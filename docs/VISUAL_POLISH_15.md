# EVERAFTER — Visual Polish 15: sentieri, piazza e superfici calpestabili

Questo documento registra l'intervento **Visual Polish 15** sulle superfici calpestabili del
villaggio: strade, piazza, cordoli e soglie delle porte. Descrive che cosa è stato trovato, quale
metodo è stato scelto, che cosa è cambiato e come è stato verificato. **Nessun sistema di gioco è
stato toccato**: nessuna nuova meccanica, nessuna modifica a economia, NPC, salvataggi, input o
altezza del giocatore; il contratto di collisione (la `HeightMapShape3D` del terreno) resta l'unica
superficie su cui si cammina.

> Riferimenti: `src/world/environment/ground_surfaces.gd` (nuovo, geometria della pavimentazione),
> `src/world/environment/paving_textures.gd` (nuovo, texture procedurali),
> `src/world/environment/village_layout.gd` (tracciati curvi),
> `src/world/environment/village_materials.gd` (due materiali condivisi),
> `src/world/environment/village_builder.gd` (integrazione e cordoli),
> `src/world/environment/terrain_relaxer.gd` (guardiano geometrico corretto),
> `tests/unit/test_ground_surfaces.gd`, `tests/unit/test_village_layout.gd`,
> `tests/unit/test_terrain_relaxer.gd`, `tests/integration/test_paved_surfaces.gd`,
> `tests/visual/paving_review.tscn`.

---

## 1. Diagnosi — perché le superfici sembravano ritagli incollati (`BEFORE`)

Prima di questo intervento piazza e strade **non esistevano come geometria**. Erano tre cose
sovrapposte:

1. **Colore per vertice sul terreno.** Il `TerrainGenerator` dipingeva un disco di ciottoli e tre
   nastri di terra battuta sui vertici della griglia 160×160, cioè con una risoluzione di 1 m.
   Nessuna pietra poteva essere più piccola di una cella: da vicino il selciato era una macchia
   uniforme, non una superficie.
2. **Un anello di cordoli sospesi.** `VillageBuilder` aggiungeva cordoli a raggio e offset fissi,
   senza campionare la quota: su un pendio la pietra restava orizzontale e un capo si staccava da
   terra. Attorno alla piazza il cordolo era un cerchio perfetto, quindi il bordo della
   pavimentazione raccontava una circonferenza da compasso.
3. **Un bordo di colore netto.** Il peso della piazza scendeva a zero in 4,5 m e quello della strada
   in 2,4 m: il passaggio pietra → terra → erba era una fascia continua, ma **retta** e senza
   materiale intermedio. Non c'era ghiaia, non c'era polvere di pietra, non c'era nessuna zona in
   cui i due materiali si mescolassero.

I tracciati avevano un difetto separato e altrettanto visibile: il generatore avanzava di **17 m**
lungo un rilevamento e poi applicava uno scostamento casuale. Ogni giunto era un ginocchio, e il
villaggio era circondato da tre spezzate. Infine nessuna superficie aveva un contatto credibile con
gli edifici: la strada passava davanti alle case senza una soglia, e la piazza si fermava a pochi
centimetri dalla facciata senza un marciapiede.

## 2. Metodo — una pelle, non un secondo terreno

Il vincolo più forte è che il giocatore, gli NPC e la fisica conoscono **solo** il height field.
Qualsiasi nuova superficie doveva quindi essere:

* **visiva e basta**: nessun collider aggiunto, nessuna seconda collisione da tenere sincronizzata;
* **appoggiata al suolo**: ogni vertice campiona `terrain.height_at()`, con un sollevamento fra
  0,7 e 2,6 cm (sotto la tolleranza di gradino della capsula e sotto `floor_max_angle = 50°`);
* **economica**: la pavimentazione è una griglia grossolana con **due materiali condivisi**, non un
  modello pietra per pietra. Il dettaglio delle pietre vive in una texture procedurale, non in
  triangoli;
* **deterministica**: stessi seed, stesso villaggio, stessa pavimentazione su ogni macchina.

Non è stato introdotto nessun plugin, nessuna mesh importata e nessuna immagine: il repository
resta di solo testo.

## 3. Interventi (`AFTER`)

### 3.1 Tracciati — curve continue invece di spezzate

`VillageLayout._build_roads()` non avanza più a passi casuali. Ogni strada è una polilinea
campionata ogni **3 m** lungo la direzione del rilevamento, con due termini sinusoidali:

| termine | lunghezza d'onda | ampiezza |
|---|---|---|
| meandro | 44 m | fino a 2,0 m |
| deriva | 168 m | fino a 3,0 m |

Entrambi sono moltiplicati per una maschera `smoothstep` che si apre nei primi **24 m**
(`ROAD_MOUTH_BLEND`): la strada esce dalla piazza radialmente e solo dopo inizia a piegare, quindi
nessun accesso viene storpiato. Il campionamento termina **esattamente** sul bordo della mappa,
senza l'ultimo tratto fuori passo che prima poteva ripiegare su sé stesso.

La curva è deterministica e ha un limite di sterzata: il test misura l'angolo fra segmenti
consecutivi e impone **< 16°** (misurato: peggiore **8,7°**), oltre a uno scostamento dalla corda fra
**0,9 m e 12 m** (misurato: **3,6 m**). Le tre strade sono 69 punti in tutto, 23 ciascuna.

Le case lungo la strada sono ora distribuite per **lunghezza d'arco** (`ROAD_PLOT_SPACING = 9 m`),
non per segmento: con una polilinea densa, "due case per segmento" avrebbe impacchettato tutto il
ciglio. Anche i lampioni e i carri usano la lunghezza d'arco, con un ritmo irregolare (19–27 m).
Il test `test_npc_route_graph` e `test_village_npc_places` restano verdi: la rete di percorso
ricampiona le stesse curve a 3 m e trova 43 nodi, zero luoghi irraggiungibili.

### 3.2 Piazza — una composizione, non un disco

`GroundSurfaces._build_plaza()` costruisce un disco a **56 settori** e quindici fasce, con un buco
centrale per il pozzo (raggio 1,52 m). Il bordo non è più un cerchio: `plaza_edge_radius()` somma
tre sinusoidi (3, 7 e 13 lobi); misurata, l'escursione è **10,46–10,98 m** (0,52 m di spread) attorno
a 10,72 m, tutta dentro l'anello dei cordoli a 12,2 m.

Le campiture sono leggibili dalla camera di gioco, senza aggiungere meccaniche:

* **corte del pozzo** (fino a 3,2 m): pietra più calda e consumata;
* **anello di drenaggio** (3,2–3,52 m): una fila scura di lastre;
* **campo centrale**: acciottolato con venature lente, più chiaro dove passa la gente;
* **fila di soldati** (8,95–9,7 m): lastre chiare alternate, la "cornice" della piazza;
* **campo esterno** (9,7 m → bordo): lastre più polverose, che sfumano nel ghiaietto.

Le UV della piazza sono **polari**: U segue l'arco, V il raggio. I corsi di pietra girano quindi
attorno al pozzo e non si allungano al bordo; una griglia UV allineata al mondo avrebbe letto come
un pavimento piastrellato.

Attorno al bordo c'è un **marciapiede di ghiaia** irregolare (due fasce, da `plaza_edge_radius()` a
11,92 m) con colore che passa da polvere di pietra a ghiaia a prato. È la transizione che prima
mancava: la pavimentazione non finisce più contro l'erba con uno scalino di colore.

### 3.3 Carreggiata e banchine — una strada che si legge da vicino e da lontano

`GroundSurfaces._build_roads()` genera un nastro a **cinque corsie** (verge, bordo, centro, bordo,
verge) campionato ogni 1,4 m. Il nastro segue la curva esatta e ha:

* **larghezza variabile** con un meandro di ±6 cm per lato e un lieve allargamento alla foce
  (+0,55 m per 3,4 m), dove i carri girano e l'acqua scorre;
* **lembo esterno irregolare**: il bordo del nastro non è mai una riga dritta, ma la carreggiata
  fisica in `VillageLayout` resta larga 3,6 m, quindi il percorso NPC e le distanze non cambiano;
* **colore per corsia**: terra battuta al centro, ghiaia sui bordi, verde prato sull'ultima corsia.
  È questo gradiente, non un taglio, a nascondere il bordo geometrico;
* **solchi delle ruote nella texture** (due avvallamenti a V = 0,347 e 0,653, σ = 0,055), non nella
  geometria: seguono ogni curva senza un triangolo in più;
* **nessuna pavimentazione sotto un muro**: le celle vengono scartate contro le impronte reali
  degli edifici (5,8×3,4 / 4,4×4,0 per le case, 8,2×5,6 locanda, 9,4×5,4 sala), non contro un
  raggio approssimato. La strada si interrompe prima della fondazione invece di attraversarla;
* **la foce entra sotto la piazza**: il nastro inizia 1 m dentro il disco, così la pietra e lo
  sterrato non si incontrano su una cucitura visibile.

### 3.4 Soglie e vialetti — la strada arriva alla porta

Ogni casa, locanda e sala riceve una **soglia** in pietra larga quanto l'apertura (1,84 m per le
case, 2,34 m per la locanda, 3,04 m per la sala) e un **vialetto** di tre file fino alla
carreggiata, interrotto 5 cm prima del bordo. Il vialetto parte a 0,72 m dalla facciata, quindi non
entra mai nel muro, e viene accorciato in base alla distanza reale dalla strada: dove il cortile è
stretto resta una soglia, dove è largo arriva al ciglio. I cordoli stradali vengono saltati in
corrispondenza dei vialetti, così l'accesso resta libero anche otticamente.

Le porte, gli ancoraggi NPC (`VillageNpcPlaces`) e i percorsi (`NpcRouteGraph`) non sono stati
modificati: la pavimentazione non ha collider e non cambia nessuna quota di gioco.

### 3.5 Cordoli — pietre appoggiate al pendio

I cordoli non sono più box a quota fissa. Ogni pietra:

* campiona il terreno ai **due capi** della propria lunghezza e viene inclinata con
  `atan2(Δh, lunghezza)`;
* è **interrata di 5–6 cm**, quindi nessun angolo resta sollevato;
* sporge di **7–11 cm**, non di 20: è un cordolo, non un gradino che il giocatore attraverserebbe
  senza collisione;
* ha lunghezza 0,92–1,08 m sulla piazza e 0,72–0,98 m lungo le strade, con fughe e qualche pietra
  mancante (7% sulla piazza, 14% sulle strade) per non sembrare stampato;
* viene saltata davanti alle foci delle strade, ai vialetti, alle fondazioni e allo stagno.

Misurato sul villaggio reale: **178 pietre**, ognuna un box fuso nella mesh condivisa
(`cobble`), cioè 2 136 triangoli dentro il baker degli oggetti — non 178 nodi.

### 3.6 Materiali e texture procedurali

Due sole chiavi di materiale, condivise con il resto del villaggio:

| chiave | uso | texture | ripetizione |
|---|---|---|---|
| `paving_cobble` | piazza, soglie, vialetti | acciottolato 384² | 3,2 m |
| `paving_road` | carreggiata, banchine, marciapiede | sterrato 256² | 4,0 m |

Le texture sono generate in codice all'avvio, con hash interi deterministici e nessun file
immagine. L'albedo è volutamente quasi grigio: il colore caldo lo portano la palette e i colori per
vertice, così la pavimentazione resta nello stesso spazio colore degli edifici. Ogni materiale ha
anche una **normal map** ricavata dallo stesso campo di altezze (bisello delle pietre, grana,
solchi) e **mipmap**, perché la piazza si guarda più spesso da 20 m che da 2 m. Il `cull_mode` è
disattivato: una superficie piana vista da un lato non ha bisogno di backface culling, quindi un
anello scritto nel verso sbagliato non può far sparire mezza piazza.

### 3.7 Il difetto che è emerso solo eseguendo: `TerrainRelaxer`

Il primo giro di test sul motore ha fatto emergere un difetto **preesistente**, non introdotto qui:
`TerrainShape` falliva con "open ground never steps more than the walkable cap (worst 0.99 m)"
contro un limite di 0,72 m. Sul commit di partenza, compilato e misurato con lo stesso motore, il
valore era **0,96 m**: falliva già prima di questo intervento (185 test superati, 1 fallito).

La causa era il rilassamento di talus. Era scritto come una morsa bidirezionale con punto medio:

```
lower = highest - max_step
upper = lowest + max_step
if lower > upper: clamped = (highest + lowest) / 2
```

Quando i due limiti si incrociano (una cella fra due vicini molto diversi) il punto medio
**contraddice entrambi** i vicini, e la passata successiva amplifica la contraddizione: un test
diretto con 200 passate portava il salto peggiore da 0,99 m a **3,8 m**. Ecco perché dodici passate
non bastavano e perché aumentarle peggiorava le cose.

La correzione separa le due metà in modo che ciascuna sia **monotona**:

* **riempimento** — una cella aperta sotto un vicino protetto (piazza, strada, piazzola) sale fino a
  un gradino sotto di esso: la fondazione ottiene una gonna, non un plinto con il muro attorno;
* **taglio** — una cella aperta sopra qualunque vicino scende fino a un gradino sopra di esso: il
  taglio di una strada in pendio diventa una rampa camminabile.

Ogni metà muove le quote in una sola direzione, quindi Gauss–Seidel propaga il vincolo di una cella
per passata e il ciclo termina davvero. `RELAX_PASSES` sale da 12 a 40 (una passata è una scansione
lineare sulla griglia). Risultato misurato: **salto massimo 0,72 m su tutto il terreno aperto**,
esattamente il cap dichiarato, e il test di integrazione passa. Il test `test_terrain_relaxer.gd`
continua a coprire entrambi i lati: una piazzola protetta non si muove e la gonna attorno sale; un
picco non protetto viene tagliato.

### 3.8 Prestazioni

* **2 draw call** (uno per materiale) e **2 984 triangoli** per tutta la pavimentazione
  (8 952 vertici), cordoli esclusi.
* **0 collider** aggiunti: il conteggio resta quello di prima.
* **0 nodi per pietra**: le pietre sono texture; i cordoli sono box fusi in `MeshBaker`.
* La pavimentazione non proietta ombre (`cast_shadow = OFF`): è terreno, non un volume.
* Budget complessivo misurato sul mondo reale: **175 mesh, 230 740 triangoli, 346 collider**
  (limiti 260 / 260 000 / 900). Prima dell'intervento: 227 / 253 890 / 352. Il costo è **sceso**:
  le tre curve dense assorbono meno prop e i cordoli sostituiscono l'anello precedente.

## 4. Verifiche

### 4.1 Controlli statici

| controllo | esito |
|---|---|
| `python3 tools/check_project.py` | **RESULT: OK** (riferimenti `res://`, scene, nodi `$`, azioni di input) |
| `gdparse` su tutti i file toccati | **OK** |
| `gdlint` sui file toccati | **nessun problema** |
| `gdlint src tests` sull'intero repository | 17 violazioni, **tutte preesistenti** (identiche sul commit di partenza, in file non toccati: `vegetation_builder.gd`, `test_chronicle_book.gd`, `game_root.gd`, `save_manager.gd`, `chronicle_*.gd`, `json_codec.gd`) |

### 4.2 Test headless

Eseguiti con **Godot 4.7.2-stable** (`--headless`, renderer dummy) compilato dai sorgenti:

| comando | esito |
|---|---|
| `godot --headless --path . --script res://tests/run_tests.gd` | **1676 passati, 0 falliti, 0 saltati** — `RESULT: OK` |
| `godot --headless --path . --script res://tests/run_world_tests.gd` | **199 passati, 0 falliti, 0 saltati** — `RESULT: OK` |

Suite nuove e estese:

| suite | che cosa verifica |
|---|---|
| `tests/unit/test_ground_surfaces.gd` (nuovo) | quota dei vertici (0,007…0,026 m dal suolo, nessuno sotto −0,002), bordo non circolare (>0,35 m di escursione, dentro 10,2–11,25 m), nessun vertice dentro una fondazione, copertura della carreggiata ogni 8 m, determinismo, 2 sole chiavi di materiale, cordoli 100–520 e 12 triangoli ciascuno |
| `test_village_layout.gd` (esteso) | curve con ≥20 punti, sterzata < 16°, scostamento 0,9–12 m, estremi sui rilevamenti giusti |
| `test_terrain_relaxer.gd` (esteso/corretto) | i controlli ausiliari erano chiamati senza underscore e non venivano risolti: la suite non eseguiva quattro dei suoi cinque gruppi. Ora li esegue e copre il rilassamento a due metà |
| `tests/integration/test_paved_surfaces.gd` (nuovo) | nodo `Paving` presente, ≥2 mesh, **0 collider**, 1 000–9 000 triangoli, texture e normal map presenti, UV presenti, quota −0,01…0,055 m rispetto al terreno reale |
| `test_world_scene.gd` (esteso) | il villaggio espone il nodo `Paving`; budget 260 mesh / 260 000 triangoli / 900 collider |
| `test_world_scene.gd::check_terrain_shape` | salto massimo sul terreno aperto ≤ 0,72 m + tolleranza, ora rispettato (0,720 m) |

### 4.3 Confronto visivo

`tests/visual/paving_review.tscn` costruisce il villaggio reale (stesso seed del gioco, senza
salvataggi, senza NPC) e offre cinque viste dalla camera di gioco: occhio umano sulla strada sud
verso la piazza, piazza dal bordo, aerea a tre quarti, soglia di una casa, ciglio della strada dello
stagno.

**Limite dichiarato:** la macchina di verifica non ha GPU, X11 né Vulkan, quindi il gioco è stato
eseguito solo in `--headless` con renderer dummy. Le misure sopra sono geometriche e di scena, non
pixel: **non è stato prodotto uno screenshot renderizzato** e nessuna affermazione di questo
documento dipende da un'immagine. Per controllare la composizione senza GPU è stata invece
proiettata dall'alto la geometria reale (vertici e colori estratti dalla scena) in una mappa
ortografica: su quella si sono verificati a occhio il bordo irregolare della piazza, le cinque
campiture, i tre imbocchi, i cordoli e i vialetti. La scena di confronto resta lo strumento con cui
completare la verifica visiva su una macchina con scheda grafica.

## 5. Limiti dichiarati

1. **Nessun collider sulla pavimentazione**, per progetto: si cammina sul heightmap. Il prezzo è che
   un cordolo alto non è un ostacolo; per questo i cordoli sporgono solo 7–11 cm.
2. **Il colore del terreno sotto la pavimentazione è ancora dipinto** e resta visibile nelle fughe
   fra una cella e l'altra e sotto le foci delle strade. Non è un secondo strato di materiale: è lo
   stesso `TerrainGenerator` di prima.
3. **La pavimentazione è una pelle a quota quasi costante** (0,7–2,6 cm): su un dosso molto stretto
   un vertice può avvicinarsi al terreno più di quanto un solo numero suggerisca. Il test misura lo
   scostamento reale, non una promessa.
4. **Le UV della piazza sono polari e quelle dei vialetti rettangolari**: due mappature sullo stesso
   materiale. È voluto, ma un futuro cambio di texture deve funzionare per entrambe.
5. **La correzione del relaxer cambia la forma del terreno** rispetto alle fasi precedenti (salto
   massimo 0,72 m invece di 0,96–0,99 m). È una modifica voluta alla silhouette, non al contratto:
   mesh e `HeightMapShape3D` leggono la stessa griglia, e le piazzole sono ancora protette.
6. **Nessuna nuova meccanica**: la piazza resta un luogo, non un sistema. Nessuna interazione,
   nessun suono, nessun evento nuovo.

## 6. File toccati

* **Nuovi**: `src/world/environment/ground_surfaces.gd`,
  `src/world/environment/paving_textures.gd`, `tests/unit/test_ground_surfaces.gd`,
  `tests/integration/test_paved_surfaces.gd`, `tests/visual/paving_review.gd` +
  `tests/visual/paving_review.tscn`, questo documento.
* **Modificati**: `src/world/environment/village_layout.gd` (tracciati curvi, campionamento per
  lunghezza d'arco, cache dei limiti delle strade), `src/world/environment/village_materials.gd`
  (due chiavi, texture, normal map), `src/world/environment/village_builder.gd` (integrazione,
  cordoli delegati, statistiche), `src/world/environment/terrain_relaxer.gd` (rilassamento a due
  metà monotone), `src/world/terrain_generator.gd` (40 passate di rilassamento),
  `tests/unit/test_village_layout.gd`, `tests/unit/test_terrain_relaxer.gd`,
  `tests/integration/test_world_scene.gd`, `tests/run_tests.gd`, `tests/run_world_tests.gd`,
  `README.md`.
