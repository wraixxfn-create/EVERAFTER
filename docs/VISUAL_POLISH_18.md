# EVERAFTER — Visual Polish 18: alberi, e un passo da umani

Questo intervento rifà gli alberi una seconda volta e rallenta il movimento del giocatore. La
geometria del terreno, la distribuzione della vegetazione, le collisioni dei tronchi, l'economia, la
simulazione e gli NPC **non cambiano**.

> Riferimenti: `src/world/environment/mesh_baker.gd` (nuova primitiva `add_frond_ring`, sfumatura
> verticale dei ciuffi), `src/world/environment/vegetation_builder.gd` (alberi riscritti),
> `src/world/player_explorer.gd` e `src/core/game_config.gd` / `config/game_config.tres`
> (velocità e salto), `tests/unit/test_mesh_baker.gd`, `tests/unit/test_vegetation.gd`,
> `tests/visual/vegetation_review.gd` (inquadrature).

---

## 1. Diagnosi — perché gli alberi «facevano schifo»

Polish 16 aveva già eliminato cilindri e sfere perfette, ma la **costruzione** dell'albero era
ancora sbagliata: una chioma era composta da **due o tre masse grandi** appoggiate in cima a un
palo. Da lì nascono i tre difetti che si vedono a occhio nudo:

1. **Chiome-masso.** Una quercia aveva `clumps = 6` ciuffi da ~2,2 m × 1,55 m sopra un tronco di
   2,15 m: il risultato è un sasso verde su un bastone, non una chioma, perché le masse sono più
   grandi dei rami che dovrebbero portarle e non hanno nessun vuoto interno.
2. **Conifere a dischi.** Un abete era una pila di 5 piani, ognuno un anello di ciuffi schiacciati
   attorno a una massa centrale: da lontano si legge il profilo a «torta a strati», e i piani non
   si toccano.
3. **Scala sbagliata.** L'abete era alto 2,35 m e il mugo 1,45 m: più bassi delle case del
   villaggio. Il pino silvestre aveva un tronco nudo di 3,2 m con una chioma larga 1,55 m, cioè un
   ombrello troppo piccolo per il tronco.

Il movimento lavorava contro lo stesso problema: 5 m/s di passo e 9 m/s di corsa con un salto di
1,84 m fanno sembrare il villaggio una pista, e ogni casa una scala da saltare.

## 2. Metodo

Il vincolo resta lo stesso: **solo testo**, nessuna mesh importata, nessuna texture, tutto
procedurale e deterministico, tutto fuso per materiale. La differenza è che ora la vegetazione non
è più «un insieme di solidi appoggiati», ma **una struttura con sopra delle foglie**:

* i rami si costruiscono prima (`add_limb`: tronco rastremato con flare radicale, primari,
  secondari, rametti nudi);
* le foglie sono **molte masse piccole** distribuite secondo una spirale a angolo aureo sui rami e
  dentro la chioma, con dimensioni vicine tra loro e sovrapposizione parziale;
* ogni massa ha una **sfumatura verticale** (parte alta illuminata, sotto in ombra), perché una
  chioma fatta di trenta masse resta un volume solo se la luce ha dove andare;
* le conifere non sono più piani sovrapposti ma **verticilli di aghi**: un anello di punte che
  pendono da un cono interno pieno, con punte lunghe e corte alternate.

## 3. Interventi

### 3.1 Nuova primitiva: `MeshBaker.add_frond_ring()`

Costruisce un verticillo di conifera in un colpo solo:

* `segments` punte attorno all'asse; **una lunga e una corta alternate** (`short_ratio`), così il
  bordo è una stella e non un disco;
* ogni punta pende di `drop` sotto il centro del verticillo, cioè i rami **si incurvano verso il
  basso** come in un abete vero;
* il cono interno chiude il verticillo attorno al tronco, e la faccia inferiore è chiusa e più
  scura: guardando l'albero dal basso non si vede il cielo attraverso;
* i triangoli sono avvolti con un risolutore esplicito (`_add_oriented_triangle`), perché con il
  bordo sotto il centro un ventaglio ingenuo si sarebbe girato dall'altra parte.

Costo: **sei triangoli per segmento** (quattro facce, corona e sottofaccia). Un verticillo a 12
segmenti costa 72 triangoli e sostituisce tre o quattro ciuffi sferici.

### 3.2 `add_foliage_clump()` con sfumatura verticale

Un parametro nuovo, `vertical_shade` (0–0.6), scrive un gradiente nel colore dei vertici
normalizzato sul raggio verticale del ciuffo: la cima si schiarisce, il fondo si scurisce. È
l'unica modifica alla primitiva esistente e non cambia né topologia né normali.

### 3.3 Conifere — tre sagome diverse

| Variante | Altezza | Costruzione |
| --- | --- | --- |
| 0 — abete rosso | 5,0–5,6 m | 6 verticilli sovrapposti a 12 punte, aghi quasi fino a terra, punta a ciuffi decrescenti |
| 1 — pino silvestre | 4,2–4,8 m | tronco nudo per metà altezza, 4 rami esposti con nuvole piatte di aghi sopra |
| 2 — mugo | 1,9–2,3 m | 6 verticilli corti e larghi, profilo a cupola cespugliosa |

Il pino silvestre è il caso in cui la differenza si legge a colpo d'occhio: **non** è un abete più
magro, è un tronco con un ombrello sospeso.

### 3.4 Querce — prima lo scheletro, poi le foglie

Tronco rastremato a quattro punti con flare radicale e tre contrafforti; cinque rami primari che
salgono dentro la chioma; un secondario per primario (solo a dettaglio pieno); due rametti nudi in
cima. Le foglie sono **35 masse piccole** a dettaglio pieno (`_add_leaf_bunch`: 3 per punta
primaria, 1–2 per punta secondaria, 6–9 interne e una corona di masse in cima), ciascuna larga
0,85–1,2 m, non una palla da 2,2 m. La corona in cima serve: senza, un albero visto dal sentiero è
un ombrello largo, piatto e vuoto al centro.

| Variante | Tronco | Ingombro (larghezza × altezza) | Carattere |
| --- | --- | --- | --- |
| 0 — larga | 2,70 m | 5,8 × 6,5 m | il riferimento, chioma larga e piena |
| 1 — alta | 3,30 m | 4,9 × 7,1 m | tronco lungo, chioma alta e più stretta |
| 2 — inclinata | 2,20 m | 6,3 × 5,9 m | gettata di lato, bassa e larghissima, quella sotto cui ci si ripara |

Le misure sono l'ingombro reale della geometria generata (media su otto semi), non i parametri
del profilo: la chioma sborda sempre di una massa oltre il ramo più lungo.

### 3.5 Betulle — un velo, non una palla

Tronco bianco rastremato (0,15 m → 0,07 m), cinque rami ascendenti dal tronco superiore e 4–5
grappoli di foglie **con vuoti in mezzo**, così in controluce si legge il cielo tra le foglie. Le
tacche scure sulla corteccia non sono più anelli cilindrici attorno al tronco (sembravano un
bozzo) ma due **tasselli piatti** appoggiati sulla superficie. La variante a due fusti ha il secondo
tronco sfalsato e una chioma più bassa; quella d'autunno resta l'unico accento caldo della linea
degli alberi.

### 3.6 Cespugli

Sei lobi (tre a distanza), raggi indipendenti sui tre assi, due rametti che escono dalla massa. La
variante fiorita resta quella di Polish 16 (capolini in `cloth_cream` / `cloth_red`), con la
sfumatura verticale nuova.

### 3.7 Prestazioni — il dettaglio si paga abbassando il raggio

Le chiome nuove costano più triangoli per albero di quelle vecchie, quindi il budget è stato
ripagato dall'altro lato:

* `DETAIL_RADIUS` scende da **44 m a 22 m**: il dettaglio pieno resta nel villaggio e lungo le
  strade, mentre il bosco di bordo usa una sagoma povera ma ancora specifica (4 verticilli invece
  di 6, 6 segmenti invece di 12, un grappolo per punta invece di due o tre).
* Le masse-foglia usano **2 anelli** invece di 3: sono piccole, la differenza non si vede, il
  costo scende di due terzi (10 triangoli contro 30 per massa).

Stima statica (conteggio per primitiva sulle regole di piazzamento del seed `20261019`, non una
misura del motore): quercia a dettaglio pieno ≈ 810 triangoli, abete ≈ 505, pino silvestre
≈ 620, betulla ≈ 590 (1.180 la variante a due fusti); le stesse specie a distanza ≈ 170–270
(abete 170, betulla 185, pino silvestre 230, quercia 265). Il bosco di bordo, che è quasi tutto
oltre i 22 m, resta la voce più pesante: con ~270 alberi a distanza e una ventina a dettaglio
pieno nel villaggio l'ordine di grandezza è **75.000–90.000 triangoli** per tutta la vegetazione
(erba compresa), cioè al limite del tetto di 90.000 della suite e dentro il margine della scena
(230.740 su 260.000 misurati in Polish 15). Per questo la versione a distanza è stata alleggerita
apposta: tronco a 4 lati, rami a 3 lati, verticilli a 5 segmenti, due ciuffi di punta. Se la
misura reale sfora, le leve sono `DETAIL_RADIUS` (22 → 18) e i segmenti della versione lontana,
non la geometria vista da vicino.

### 3.8 Movimento — passo e salto da persona, non da veicolo

| Parametro | Prima | Ora |
| --- | --- | --- |
| Passo | 5,0 m/s | **3,4 m/s** |
| Corsa (`Shift`) | 9,0 m/s | **5,6 m/s** |
| Spinta del salto | 6,0 m/s (≈1,84 m di altezza) | **4,1 m/s (≈0,86 m)** |
| Accelerazione / decelerazione | 45 / 32 | **32 / 26** |

Con la gravità del progetto (9,8 m/s²) il salto dura 0,84 s e supera un dislivello di 0,86 m:
si sale su un gradino, su un argine o su un masso basso, non su uno steccato. L'accelerazione più
bassa fa sì che il cambio di direzione non sia uno scatto. I valori sono sia nei default del
codice sia in `config/game_config.tres`, quindi restano modificabili dal file di configurazione
senza toccare la scena.

## 4. Verifiche

| Verifica | Esito |
| --- | --- |
| `python3 tools/check_project.py` | **OK** |
| `gdparse` su tutti gli script modificati | **OK** |
| `gdlint` sui file modificati | **0 problemi** |
| `git diff --check` | **OK** |

Sono stati aggiunti controlli per: numero di triangoli del verticillo (sei per segmento),
avvolgimento di **tutte** le facce compresa la sottofaccia, assenza di triangoli degeneri,
alternanza delle punte lunghe/corte sul bordo, determinismo del seme, gradiente verticale del
ciuffo (cima più chiara del fondo), altezza plausibile degli alberi (3–6,5 m a scala 1) e numero di
masse della chioma (≥ 6).

**La suite headless e quella d'integrazione non sono state eseguite**: in questo ambiente non c'è
un eseguibile Godot e il repository non include binari. Non dichiaro quindi verificati a runtime né
il conteggio reale dei triangoli né la resa visiva finale: le immagini di progetto sono state
verificate con un rasterizzatore software separato (non parte del repository), non con il motore.

## 5. Revisione manuale

`tests/visual/vegetation_review.gd` è stato riallineato alle nuove altezze:

* `1` quercia da distanza ravvicinata (soggetto a 2,6 m, camera a 8 m): tronco, rami, masse;
* `2` abete da sotto, camera ad altezza occhio a 9 m: i verticilli sono pieni o si vede il cielo?
* `3` cespuglio e chiazza di fiori a ginocchio;
* `4` prato a livello del suolo;
* `5` linea degli alberi a 30 m.

Frecce per orbitare, rotella per la distanza. Il log stampa la conta per specie/variante e quanti
alberi sono a dettaglio pieno, così un rerun dice subito se il mix o il budget si sono mossi.

## 6. Limiti residui

* Le conifere sono ancora low-poly: un verticillo a 12 segmenti ha 12 punte, e da due metri si
  contano. Non è una promessa di fotorealismo, è una silhouette leggibile.
* Le masse-foglia a due anelli hanno un profilo più «a diamante» di quelle a tre: a distanza non
  si nota, a un metro sì. Il costo è la ragione della scelta.
* Il conteggio dei triangoli è una **stima** finché la suite non gira su una macchina con Godot;
  se sfora, la leva più rapida è `DETAIL_RADIUS` (24 → 20) e non la geometria.
* La collisione dei tronchi è invariata (cilindri fissi per specie): con i tronchi nuovi i raggi
  restano coperti, ma un albero inclinato ha il collider verticale come prima.
