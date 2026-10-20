# EVERAFTER — Visual Polish 19: composizione artistica e leggibilità del villaggio

Questo intervento migliora la **composizione d'insieme** della mappa: il rapporto tra
edifici, piazza, sentieri, vegetazione e terreno, visto dalla telecamera di gioco.
Non si aggiunge nessun elemento nuovo al vocabolario del mondo (niente castelli, niente
montagne): si riposizionano e si aggiungono elementi **esistenti** (alberi, cespugli,
bancarelle, panchine, fioriere, lampioni) e si correggono in modo limitato le regole
che piazzano lotti e vegetazione. Dimensioni e struttura funzionale della mappa
**non cambiano**: strade, piazza, stagno, pozzo, locanda, sala, tipi di edificio e
la loro disposizione ad anello restano quelli di prima.

> Riferimenti: `src/world/environment/village_layout.gd` (tutto), nuove asserzioni in
> `tests/unit/test_village_layout.gd`, nuova scena `tests/visual/composition_review.gd`
> / `.tscn`.

---

## 1. Metodo

La composizione non si giudica a occhio da un unico screenshot: si misura. Il layout è
dati puri e deterministici, quindi è stato portato fedelmente in Python (PCG32 incluso,
con la semantica esatta di `randf`/`randf_range`/`randi_range` di Godot 4.5) e
validato contro **tutte** le asserzioni di `tests/unit/test_village_layout.gd`: il port
riproduce lo stesso villaggio, placement per placement. Sul port si sono poi misurati,
da nove punti di osservazione realmente accessibili (spawn, fine di ogni strada a 30 e
45 m, riva dello stagno, bordo est della piazza):

* **visibilità dei punti di riferimento** — segmento occhio→punto di riferimento contro
  le casse di ogni elemento, da punti realmente accessibili (spawn, fine di ogni
  strada, riva dello stagno, bordi della piazza), nel cono visivo del giocatore;
* **settori vuoti del profilo del paese** — bucket angolari da 15° nella fascia
  12–48 m, dove un paese dovrebbe avere qualcosa in piedi;
* **vuoti involontari** — celle di prato a più di 9 m da qualsiasi elemento;
* **raggiungibilità NPC** — porto di `VillageNpcPlaces` + `NpcRouteGraph`, per
  dimostrare che i percorsi restano connessi;
* **invariabili di piazzamento** — sovrapposizioni, varchi stradali, corridoi delle
  porte, cancelli del recinto, a più semi e dimensioni di mappa.

Lo stesso port ha permesso di iterare le regole nuove e **misurare** il risultato
prima di scriverlo in GDScript; il GDScript modificato è stato poi ritrascritto in un
secondo port indipendente e confrontato placement per placement: identico.

## 2. Diagnosi (seed di gioco 20261016)

1. **La prima inquadratura nasconde il punto di riferimento più alto.** Dallo spawn
   (via sud-ovest, 22 m), la sala del consiglio e il suo campanile — la silhouette
   più alta del villaggio, 12 m — sono dietro il primo lotto di case della strada.
   Dalla fine di ogni strada, almeno un punto di riferimento risultava nascosto: 19
   viste bloccate in totale sui punti di osservazione misurati.
2. **Il mercato non esisteva come fila.** La bancarella di mezzo (64°) era a 16° da
   quella alleata (48°): 3,9 m al suolo, sotto i 4,4 m che due impronte da 2,4 m
   richiedono, quindi la regola delle sovrapposizioni l'aveva **scartata silenziosamente**.
   In gioco esistevano 2 bancarelle su 3: una accanto alla locanda e una sola,
   isolata, dall'altra parte della piazza.
3. **Lungo le strade mancavano le case.** Il primo lotto di ogni strada stava già
   a 16 m, proprio sul bordo della piazza: l'imbocco della strada si chiudeva in un
   muro di facciate invece di aprirsi sul square. Su via ovest la fortuna del seme
   aveva piazzato 4 cataste di legno di seguito: la strada leggeva come un legnaio,
   non come una via.
4. **Il cielo del paese aveva buchi.** Dalla piazza, 8 settori su 24 del profilo
   entro 48 m erano vuoti (nessun elemento alto): prati involontari dietro il paese,
   tra l'altro in direzione sud (195°) e nord-est (90°/135°).
5. **La piazza era sbilanciata.** Il settore civico (lato sala, 178°–252°) portava
   solo due panchine; tutti gli arredi del mercato stavano sul lato nord-est.
6. **Lo stagno non inquadrava la piazza.** Dalla riva, il pozzo e la locanda erano
   dietro una quercia sparsa casualmente esattamente sull'asse stagno→piazza.
7. **Lampioni persi.** Con gli altri spostamenti, tre candidati lampione cadevano
   nelle sovrapposizioni con i cortili: metà dell'illuminazione stradale spariva.

## 3. Interventi (tutti in `VillageLayout`)

### 3.1 Fila del mercato che esiste davvero

Le bancarelle stanno ora a 44°/r 15,5 e 63°/r 16,0: 19° di arco (5,4 m) le tiene
separate, e la seconda resta a 8,0 m dalla locanda (la regola ne chiede 7,7).
Tutte e tre piazzano, in due settori come voleva la correzione 11. Il centroid delle
bancarelle — da cui `VillageNpcPlaces` deriva l'ancoraggio `work_market` — si sposta
di conseguenza, in modo coerente, senza riferimenti hard-coded.

### 3.2 Imbocchi di strada aperti

* **Il primo lotto di ogni strada è una legnaia**, non una casa
  (`PLOT_MOUTH_YARD_DEPTH = 6` m dal punto di partenza dei lotti): il bordo del
  villaggio è un cortile, e una catasta (1,7 m) si vede oltre. Le case iniziano
  dal secondo lotto.
* **Il lato di partenza alternato è ora una scelta d'insieme** (`PLOT_START_SIDE`):
  sulle strade il cui approccio altrimenti murava la piazza (quella dello spawn e
  quella nord-est) il primo lotto sta sul lato esterno.
* **Niente cataste in serie** su una stessa strada: una legnaia ogni tanto legge
  come un cortile, quattro di seguito come un deposito.

### 3.3 Corridoi visivi composti (regole nuove, nello spirito di quelle esistenti)

Il piazzatore già protegge i corridoi delle porte; Polish 19 estende la stessa idea
a tre corridoroi di **sightline**, per vegetazione alta (alberi):

* **Vista pozzo–stagno** (`POND_VISTA_HALF_WIDTH = 5`): nessuna chioma entro 5 m
  dall'asse stagno→piazza, così la riva inquadra il square.
* **Vista delle strade** (`ROAD_VISTA_HALF_WIDTH = 4.5`): nessuna chioma entro 4,5 m
  dalla corda fine-strada→piazza, così ogni via legge come un corridoio che arriva
  al centro.
* **Sightline d'arrivo** (`ARRIVAL_CORRIDOR_HALF_WIDTH = 3.2` + 2,2 m di chioma):
  dai due punti di ogni strada dove la piazza si apre (22 m e 45 m), i segmenti
  verso pozzo, locanda, sala **e campanile** restano sgombri. La regola vive in
  `_add_placement`, quindi vale per bosco, groves interni, sparpagliamento e nodi:
  un albero che bloccherebbe un punto di riferimento dalla strada viene scartato,
  esattamente come un tronco in un corridoio di porta.

### 3.4 Nodi d'alberi composti nei settori vuoti

`VISTA_KNOTS`: cinque gruppi di due alberi (quercia/abete/betulla) nei settori che i
passaggi casuali lasciano vuoti — prato est (100°), prato sud-est (142°), prato sud
(222°), fianco ovest della sala (258°), bordo nord-ovest (335°). Sono collocati
**prima** del bosco e dello sparpagliamento, così la composizione deliberata vince il
 terreno e il caso riempie attorno. Ogni nodo prova un piccolo passo laterale se il
centro è occupato, perché lo sparpagliamento possiede la stessa fascia. I nodi stanno
tutti fuori dai corridoi di vista (la regola 3.3 li controlla: il membro del nodo
north-ovest che cade nel corridoio della locanda viene scartato, e va bene così).

### 3.5 Arco civico della piazza

Una panchina a 232° e due fioriere a 198°/244° vestono il settore tra la sala e
l'imbocco ovest: la piazza legge come square con un lato mercato e un lato civico.
Tutti e tre stanno tra le imbocature e fuori dal corridoio della porta della sala.

### 3.6 Lampioni resilienti

Se il cordolio di un lotto occupa il primo lato, il lampione prova il lato opposto;
se entrambi sono occupati, risale la strada a step di 4 m (senza consumare RNG, quindi
il flusso del seme è immutato) finché trova un cordolio libero. In più, il **primo
slot** di arredo stradale di ogni strada prova sempre un lampione: è la luce che
marca l'imbocco. Risultato: ogni strada conserva almeno un lampione a ogni seme
testato (prima, a seme 7, via 2 restava al buio).

## 4. Risultati misurati

| Misura | Prima | Dopo |
| --- | --- | --- |
| Viste di punti di riferimento bloccate (9 punti di osservazione, 35 viste nel cono visivo) | 19 | **7** (tutte canyon di strada realistici o prospettive in due tempi) |
| Settori vuoti del profilo paese (15°, r < 48 m) | 8, tutti involontari | 4, tutti intenzionali (assi strada, sagrato della sala, imbocco locanda) |
| Bancarelle piazzate | 2 (una scartata dal sovrapposizione) | **3** |
| Case | 12 | 11 (la legnaia d'imbocco costa un lotto; il minimo contrattuale è 6) |
| Lampioni | 6 | 6–8, almeno uno per strada a ogni seme |
| Alberi | 281 | 285 (i nodi aggiungono 10 alberi, i corridoi ne tolgono ~6) |
| Vuoto involontario più grande nella fascia villaggio | 92 m² | 14 m² |

Dalla spawn: pozzo, piazza, mercato e stagno inquadrati come prima, e ora anche la
sala e il campanile leggibili sopra i tetti. Da ogni fine strada: il campanile o la
sala visibili a 30 m. Dallo stagno: sala e campanile visibili, la piazza oltre la
riva. Dal bordo della piazza: tutti i punti di riferimento visibili.

## 5. Compatibilità funzionale (verificata)

* **NPC**: case, locanda, sala, pozzo e bancarelle non sono riferiti da script per
  posizione — `VillageNpcPlaces` deriva tutto dal layout a ogni avvio (case ordinate
  per distanza dalla piazza, ancoraggi ri-calcolati). Il port del grafo delle rotte
  conferma: **tutti i 19 luoghi raggiungibili, a ogni seme testato**, case distinte
  per i 10 abitanti.
* **Salvataggi**: `SaveManager` non persiste posizioni del mondo (solo simulazione,
  economia, relazioni, memoria, cronaca) — un vecchio salvataggio carica su un mondo
  nuovo senza rotture, come dopo ogni polish precedente.
* **Gioco**: strade, piazza, stagno, pozzo, dimensioni e tipi di edificio, recinto del
  campo con il suo varco, radici del terreno, collisioni, economia e simulazione
  **invariati**. I lotti strada si spostano di qualche metro e alternano il lato di
  partenza: sono asset puramente visivi con collider, ma tutto ciò che li riguarda
  (ancoraggi, percorsi) è derivato a runtime.
* **Prestazioni**: nessun nuovo materiale, mesh o draw call; solo riposizionamenti.
  Il budget triangoli della scena non si muove in modo misurabile (±10 alberi su
  ~290).

## 6. Verifiche

| Verifica | Esito |
| --- | --- |
| `python3 tools/check_project.py` | **OK** |
| `git diff --check` | **OK** |
| Asserzioni della suite unitaria (port Python fedele, 7 semi/mappe) | **tutte passano** |
| Nuove asserzioni compositive (fila di 3, imbocchi, sightline, nodi, lampioni) | **passano a ogni seme** |
| Grafo rotte NPC (port): luoghi irraggiungibili | **nessuno, a ogni seme** |
| Ritrascrizione del GDScript modificato: placements identici al port di design | **identici** |

Sono state aggiunte a `tests/unit/test_village_layout.gd`: tre bancarelle distanziate,
primo lotto legnaia per strada, nessuna chioma sui sightline d'arrivo e sull'asse
pozzo–stagno, almeno cinque alberi nei nodi composti, un lampione per strada.

**La suite headless e quella d'integrazione non sono state eseguite**: in questo
ambiente non c'è un eseguibile Godot e il repository non include binari. Le misure
sopra vengono dal port Python fedele (validato sulle asserzioni della suite), non dal
motore: non dichiaro verificati a runtime né il conteggio reale dei triangoli né la
resa visiva finale.

## 7. Revisione manuale

`tests/visual/composition_review.tscn` (oppure
`godot --path . res://tests/visual/composition_review.tscn`) costruisce il mondo
deterministico reale e mette il revisore su sei punti di osservazione accessibili:
`1` lo spawn e la prima inquadratura, `2` il bordo della piazza con orbita attorno
al pozzo, `3`–`5` la fine di ciascuna strada che arriva in paese, `6` la riva dello
stagno verso la piazza. Frecce per orbitare, rotella per la distanza. Il log stampa
il censimento degli arredi e il riepilogo del villaggio.

## 8. Limiti residui

* Gli occludimenti accettati (7) sono fisica di un paese vero: la fine di una strada
  è un canyon di case, e dall'angolo opposto dello stagno la locanda sta dietro una
  casa ad anello. Il campanile e la sala leggono oltre i tetti (sightline "solo
  cima") in ogni caso.
* I corridoi di vista proteggono gli alberi, non le case: un lotto strada resta un
  lotto strada, e da metà strada il paese alle spalle può coprire un fianco della
  sala. È il ritmo di un vicolo, non un difetto.
* Il port Python è fedele ma non è il motore: le misure di occlusione uscono casse
  approssimate (prismi e profili al contorno), non le mesh architettoniche vere.
* A seme 7 (mappa piccola) le strade sono corte e qualche slot di arredo in meno
  esiste; il lampione d'imbocco garantito copre comunque ogni strada.

## 9. File modificati e asset

| File | Intervento |
| --- | --- |
| `src/world/environment/village_layout.gd` | fila del mercato, arco civico, lotti strada (lato, legnaia d'imbocco, niente cataste in serie), corridoi di vista composti, nodi d'alberi, lampioni resilienti |
| `tests/unit/test_village_layout.gd` | nuove asserzioni compositive (ri-derivate dalla lista pubblica dei placement) |
| `tests/visual/composition_review.gd`, `.tscn` | scena di revisione a sei punti di osservazione |
| `docs/VISUAL_POLISH_19.md` | questo resoconto |
| `README.md` | indice dei documenti e sezione della fase |

Nessun modello, texture o altro asset binario è stato aggiunto; nessuna dimensione o
struttura funzionale della mappa è cambiata.

> Nota sulla numerazione: il repository contiene già `docs/VISUAL_POLISH_18.md`
> (alberi e passo umano). Questo intervento, puriché etichettato "Visual Polish 18"
> nel task di composizione, continua la serie documentale come **19** per non
> sovrascrivere il resoconto precedente.
