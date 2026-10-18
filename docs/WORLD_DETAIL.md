# EVERAFTER — Densità ambientale e dettagli del mondo (Visual Polish 04)

Questo documento registra l'intervento di rifinitura visiva sul villaggio 3D: cosa è stato
trovato esaminando la mappa, cosa è cambiato, quali regole tengono il risultato credibile e
quali controlli sono stati eseguiti. **Nessun sistema di gioco è stato toccato**: layout,
simulazione, economia, NPC e percorsi lavorano esattamente come prima; cambiano solo il
posizionamento, la varietà e i dettagli degli elementi già previsti dalla mappa.

---

## 1. Analisi della mappa prima dell'intervento

Esaminando la distribuzione di `VillageLayout` (il piano deterministico del villaggio) e i
builder 3D, i problemi principali erano:

1. **Ripetizioni troppo evidenti.** Un lampione esattamente al punto medio di ogni tratto
   stradale, sempre dallo stesso lato; case sempre alle stesse frazioni (0.32 / 0.72) di ogni
   segmento; il 78% dei lotti "casa o catasta di legna" e nient'altro; 26 tentativi di scatter
   con solo querce e massi nel perimetro del villaggio.
2. **Posizioni innaturali.** Il barile della piazza (bearing 96°) stava a quattro metri dalla
   facciata della locanda — esattamente sul portico e nel corridoio della porta d'ingresso.
3. **Zone vuote senza funzione.** La fascia tra i lotti stradali e il bosco (0.3–0.6
   `half_extent`) conteneva solo pochi alberi sparsi; le rive dello stagno erano solo "fine
   dell'acqua"; le case non avevano nessun segno di vita sui fianchi.
4. **Transizioni nette.** Le strade finivano nel terreno senza un bordo (la sola piazza aveva
   il cordolo); la vegetazione bassa cresceva fino alle soglie e sui gradini delle porte;
   l'erba passava attraverso casse, recinti e fioriere.
5. **Silhouette ripetitive.** Tutti i pini avevano gli stessi raggi di strato, tutte le querce
   la stessa corona: la varietà era solo nel colore.

## 2. Interventi

### 2.1 Distribuzione e varietà (`src/world/environment/village_layout.gd`)

* **Cortili (`_build_homestead_details`, nuovo passo)**: accanto a ogni casa, locanda e sala
  vengono ora sistemati 1–2 piccoli oggetti d'uso (cassa, barile, catasta di legna, fioriera
  su piedistallo) sui **fianchi o sul retro**, mai sul fronte. Il passo usa il sistema di
  accettazione/rifiuto esistente (`_add_placement`), quindi niente sovrapposizioni e niente
  oggetti sulla carreggiata.
* **Arredi fissi garantiti**: due panchine nella piazza rivolte verso il pozzo (bearing 172° e
  252°, tra le bocche delle strade), due fioriere (58°, 135°), una panchina sulla riva dello
  stagno rivolta all'acqua e due fioriere che la fiancheggiano. Garantiti per costruzione, non
  per estrazione casuale: la loro presenza non dipende dal seme.
* **Strade**: i lampioni non stanno più al punto medio fisso, oscillano tra il 30% e il 70%
  del tratto e tra 0,9 e 1,5 m dal bordo, con un 20% di tratti senza lampione; carri e barili
  compaiono a quote variabili. I lotti delle case hanno uno scostamento longitudinale ±1,4 m,
  così la fila non è più un colonnato misurato.
* **Bosco e radure**: densità dell'anello boschivo 3.2 → 3.5 alberi/unità, più tre **radure**
  (gruppi di 3–5 alberi della stessa specie) nella fascia vuota; lo scatter interno passa da 26
  a 44 tentazioni con mix quercia/pino/betulla/cespuglio/masso.
* **Stagno**: ciottoli alla linea d'acqua (8 grappoli), fiori selvatici sui cespugli di riva e
  la panchina con terrazza di fioriere descritta sopra.

### 2.2 Bordi dei sentieri e transizioni (`src/world/environment/village_builder.gd`)

* **Cordolo stradale (`_bake_road_kerb`, nuovo)**: pietre in `cobble` irregolari e a tratti
  interrotte lungo entrambi i margini di ogni strada, fuse nelle mesh delle props (zero draw
  call aggiuntivi, zero collider). Le pietre si interrompono entro il lotto di ogni edificio
  (`_near_structure`), così il cordolo non finisce mai dentro un gradino o un ingresso.
* **Ninfee (`_bake_pond_lilies`, nuovo)**: 7 quad orizzontali appena sopra la superficie dello
  stagno, nella zona della riva.
* **Erba (`vegetation_builder.build_grass`)**: 4200 ciuffi (prima 3600) distribuiti a due
  scale — uniforme + ciuffi sparsi (`GRASS_CLUMPS` × `GRASS_CLUMP_RADIUS`) — ed **esclusi dai
  piedistalli solidi** (`GRASS_EXCLUSION_KINDS`): niente lame sui gradini, dentro le casse o
  attraverso panchine e fioriere.

### 2.3 Dettagli architettonici (`building_factory.gd`, `building_surface_details.gd`)

Tutti dettagli già previsti dal linguaggio della mappa, costruiti con le primitive esistenti:

* **Fioriere ai davanzali** (`_window_flower_boxes`): cassette in doghe con zolla scura e
  teste di fiori, sotto le finestre sul lato strada di case e locanda. Allineate per
  costruzione alle finestre (`_window_spread` condiviso con `_windows`).
* **Portico della locanda**: panchina contro il muro accanto alla porta (lato destro) e barile
  accanto al montante sinistro, entrambi fuori dal corridoio d'ingresso e fuori dall'ala a L.
* **Lanterna sopra il portale della Sala del Consiglio**: mensola in ferro e lanterna che si
  accende al crepuscolo con il materiale condiviso `lantern` (lo stesso glow notturno gestito
  da `SkyRig`).
* **Secchio accanto al pozzo**: sulle pietre, fuori dal collider del pozzo (r 1,15).
* **Varietà delle chiome**: raggi di strato dei pini e corona/lobi delle querce ora passano da
  un piccolo jitter per albero (0.85–1.15×), così due alberi della stessa specie non hanno più
  la stessa silhouette.

### 2.4 Piccoli elementi ambientali

Due nuovi tipi in `VillageLayout` + `BuildingFactory`, entrambi **puramente decorativi**
(nessun collider, nessun ostacolo NPC):

* `flower_box` — fioriera a mezzabotte con cerchi in ferro, zolla e 7 fiori (palette esistente:
  `cloth_red`, `cloth_cream`, `leaf_bright`);
* `bench` — panchina in doghe con piedi in pietra e schienale inclinato (`stone_dark`,
  `timber_warm`, `plank`).

Varianti leggere aggiunte agli elementi esistenti: **cespugli fioriti** (variante 2, teste di
fiori nella palette tessile), **ciottoli** (sassi con scala < 0.55 diventano grappoli di tre
pietre invece di un masso in miniatura). Nessun nuovo pacchetto di asset, nessuna dipendenza:
tutto resta geometria procedurale e colori per vertice.

### 2.5 Composizione

Le aree aperte restano aperte: nessun oggetto nel campo di sosta del recinto, nella radura del
mercato o al centro della piazza. I punti di riferimento (pozzo, campanile, insegna della
locanda, stagno) non sono stati toccati; anzi la panchina della riva e la lanterna del
campanile li rafforzano come mete. Spazi percorribili: il corridoio di ogni porta (regola
seguente) e le carreggiate restano liberi per costruzione.

## 3. Regole che tengono il risultato credibile

1. **Corridoio della porta** (`VillageLayout._blocks_a_doorway`): il placer rifiuta ogni
   proposta cada dentro la striscia davanti all'ingresso di case, locanda e sala (±1,5 m +
   metà raggio dell'oggetto, fino a `footprint + 1,5 m`). La regola è nel placer, non nei
   singoli passi: vale per il bosco, lo scatter, i cortili e ogni passo futuro. Un test la
   ricalcola in modo indipendente dall'elenco pubblico dei placement.
2. **Niente duplicati identici**: scala, rotazione, tinte per vertice, jitter di corona e
   spaziatura irregolare del cordolo; le due panchine della piazza sono specchiari di
   composizione, non copie incollate.
3. **Niente intersezioni visibili o oggetti sospesi**: i placement passano dai controlli di
   sovrapposizione e di quota terreno già esistenti (`_placement_transform` usa
   `terrain.height_at`); le uniche "giunzioni" volute sono le fioriere sotto i davanzali.
4. **Vegetazione non invadente**: corridoi delle porte (1), esclusione dell'erba dai
   piedistalli solidi (2.2), carreggiate già protette da `ROAD_CLEARING_KINDS`.

## 4. Collisioni e navigazione

* **Collisioni giocatore**: invariate per gli edifici e per i prop solidi (casse, barili,
  cataste, carri, recinti, alberi). Le due novità decorative **non hanno collider**: non
  possono bloccare il giocatore. Nessun collider toccato, aggiunto o rimosso altrove.
* **Navigazione NPC**: il progetto non usa `NavigationRegion3D` (la camminabilità è la rete di
  waypoint di `NpcRouteGraph`, validata contro gli ostacoli di `VillageNpcPlaces`).
  `flower_box` e `bench` hanno raggio ostacolo **0** (`_obstacle_radius` di default): non
  deviano i percorsi e non possono renderli irraggiungibili. I nuovi alberi/massi rispettano
  lo stesso margine di sicurezza stradale dei precedenti (`ROAD_WIDTH * 0.5 + extent * 0.6`),
  che garantisce sempre il doppio del `NPC_RADIUS + EDGE_CLEARANCE` richiesto dai segmenti
  della rete: i bordi stradali restano validi per costruzione.
* **Corridoi delle porte liberi** migliorano anche gli anchor NPC di casa, che si calcolano
  davanti alla porta.
* Rischio residuo: qualche conettore casa→strada in più può essere rifiutato da un albero
  nuovo; la rete tenta fino a 24 connettori per luogo e la suite (`test_village_npc_places`)
  verifica che **ogni** luogo resti raggiungibile.

## 5. Ottimizzazioni

Nessuna nuova dipendenza, nessun asset esterno. Le tecniche restano quelle native già in uso:

* tutto il nuovo statico è **fuso** in `MeshBaker` (una mesh per materiale): bordi stradali,
  ninfee, ciottoli e vegetazione non aggiungono draw call oltre ai pochi materiali nuovi usati
  (`leaf_mid` nelle props, `cloth_*` nella vegetazione, `plank`/`lantern` negli edifici);
* l'erba resta **un `MultiMesh`** (1 draw call);
* niente LOD: la scena è già sotto il budget con un margine di ~30% (vedi sotto) e le nuove
  geometrie sono a basso poligono; un sistema LOD sarebbe costo senza beneficio su GTX 1060.

## 6. Controlli eseguiti

Vedi la sezione "Verifiche eseguite su questa fase" del README per la tabella completa con gli
strumenti e gli esiti. In sintesi:

* sintassi (`gdparse`), stile (`gdlint`, 0 problemi nuovi) e coerenza progetto
  (`tools/check_project.py`) eseguite su tutti gli script;
* regole di posizionamento stressate su **48 semi diversi** con un rispecchiamento fedele
  delle regole in Python (fuori repository): 0 sovrapposizioni, 0 oggetti in strada, 0 corridoi
  di porta ostruiti, 0 recinti sulla carreggiata, minimi garantiti di panchine/fioriere/cortili;
* suite headless di unità e integrazione eseguite su Godot 4.7.2: esiti e misure del budget
  nel README.

## 7. Cosa non è stato fatto (di proposito)

* Nessuna espansione geografica: la mappa ha lo stesso `half_extent`, le stesse tre strade,
  lo stesso stagno.
* Nessuna meccanica nuova, nessun oggetto interattivo, nessun sistema di crafting/decorazione.
* Nessun asset binario scaricato, nessun plugin.
* Le aree vuote con uno scopo (campo del recinto, radura del mercato, prati aperti) sono state
  **lasciate vuote**: la densità serve la composizione, non il horror vacui.
