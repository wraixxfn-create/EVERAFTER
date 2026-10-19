# EVERAFTER — Visual Polish 16: ricostruzione della vegetazione

Questo documento registra l'intervento **Visual Polish 16** sulla vegetazione del villaggio: alberi,
cespugli, fiori, massi ed erba. Descrive che cosa non funzionava, quale metodo è stato scelto, che
cosa è cambiato e che cosa è stato — e che cosa **non** è stato — verificato. **Nessun sistema di
gioco è stato toccato**: nessuna nuova meccanica, nessuna modifica a economia, NPC, salvataggi,
input o altezza del giocatore; il contratto di collisione (la `HeightMapShape3D` del terreno) resta
l'unica superficie su cui si cammina.

> Riferimenti: `src/world/environment/mesh_baker.gd` (tre primitive organiche nuove),
> `src/world/environment/vegetation_builder.gd` (alberi, cespugli, fiori, massi — riscritto),
> `src/world/environment/meadow_builder.gd` (nuovo: erba istanziata),
> `src/world/environment/village_layout.gd` (distribuzione: boschi, radure, cespugli, fiori),
> `src/world/environment/village_materials.gd` (una sola modifica: l'erba non è più un billboard),
> `src/world/environment/village_builder.gd` (dettaglio per distanza),
> `tests/unit/test_mesh_baker.gd`, `tests/unit/test_village_materials.gd`,
> `tests/unit/test_vegetation.gd` (nuovo), `tests/visual/vegetation_review.tscn` (nuovo).

---

## 1. Diagnosi — perché la vegetazione sembrava primitiva (`BEFORE`)

Il problema non era la **quantità** di alberi: era che ogni albero raccontava la stessa storia.
Tutta la vegetazione usciva da tre primitive:

1. **Tronchi cilindrici.** Un `add_cylinder` a raggio costante, con il fondo appoggiato a terra e la
   cima nascosta nella chioma. Da vicino un tronco così ha il profilo di un tubo: nessun
   rastremarsi, nessun flare radicale, nessun ginocchio. Da lontano il tronco era invisibile, quindi
   la chioma sembrava galleggiare.
2. **Chiome sferiche.** Una `add_sphere` UV per chioma: stesso raggio per ogni angolo, stessa
   latitudine per ogni anello. Anche variando scala e rotazione, la sagoma restava un cerchio
   perfetto: è il motivo per cui la linea degli alberi si leggeva come una fila di lecca-lecca.
3. **Pini a coni impilati.** Tre o quattro `add_cylinder` a raggio decrescente, uno sopra l'altro,
   senza rami e senza massa laterale. Da lontano il pino era un cono da cantiere; da vicino era
   evidente che i «piani» non si toccavano.

Cespugli ed erba avevano un difetto diverso e più grave ai bordi:

* i **cespugli** erano una o due sfere schiacciate, senza rametti, senza chiaroscuro interno e con
  la stessa altezza in ogni punto del villaggio;
* l'**erba** era una coppia di quad incrociati con una texture alpha. Il ritaglio si vedeva a ogni
  angolazione radente, le due metà si sovrapponevano in modo innaturale e il ventaglio di istanze
  ordinate produceva un tappeto a chiazze regolari.

Infine la **distribuzione** lavorava contro il modello: gli alberi erano un disco polare a densità
quasi costante (bordo circolare, spaziatura uniforme), i cespugli una collana a un solo raggio e i
fiori non esistevano come oggetto — erano solo qualche pixel di colore sul terreno.

## 2. Metodo — poche primitive nuove, riusate ovunque

Il vincolo del progetto è che il repository resti **di solo testo**: nessun plugin, nessuna mesh
importata, nessuna immagine, nessun asset di licenza incerta. Tutto deve essere procedurale e
deterministico. La risposta non è stata quindi «più alberi», ma **tre primitive organiche** dentro
il `MeshBaker` già esistente, riusate da ogni specie:

* **`add_limb(key, points, radii, sides, xform, tint, face_variation)`** — un tubo rastremato lungo
  una polilinea piegata. Cambia raggio punto per punto, quindi serve sia al tronco (con flare
  radicale e rastremazione verso la chioma) sia ai rami e alle radici. È la primitiva che elimina
  sia il cilindro sia il tronco invisibile.
* **`add_foliage_clump(key, radii, rings, segments, seed, xform, tint, flat_shading)`** — un
  ellissoide **lobato**: ogni vertice è spostato da una somma di sinusoidi periodiche nell'angolo e
  nella latitudine. Costo identico a una sfera della stessa risoluzione, sagoma diversa per ogni
  seme. È la primitiva che elimina la sfera perfetta.
* **`add_blade(key, height, base_width, tip_width, bend, xform, tint, root_shade)`** — una lama
  rastremata e piegata, due triangoli, normale **verso l'alto**. Serve ai fili d'erba, agli steli e
  alle foglie basse dei fiori. La normale verso l'alto è la scelta che permette di togliere la
  texture alpha: la lama è geometria opaca, non un ritaglio.

Le tre primitive riusano i materiali già in palette: **nessuna chiave nuova**, nessun nuovo draw
call, nessun nuovo materiale. Il conteggio dei materiali del villaggio resta sotto il tetto di 24
verificato da `test_village_art.gd`.

## 3. Interventi (`AFTER`)

### 3.1 Pini — tre sagome, non tre taglie

| Variante | Tronco | Piani | Ciuffi per piano | Profilo |
| --- | --- | --- | --- | --- |
| 0 — abete rosso | 2,35 m | 5 | 5 | cono pieno, spire in cima |
| 1 — pino silvestre | 3,20 m | 3 | 5 | tronco lungo e nudo, chioma a ombrello, rami visibili |
| 2 — mugo giovane | 1,45 m | 4 | 4 | basso e largo, quasi un cespuglio con il tronco |

Ogni piano è **una massa centrale più ciuffi radiali**: il ciuffo è un `add_foliage_clump` con l'asse
X locale puntato verso l'esterno, quindi è più lungo lungo il ramo che attraverso, e un piccolo roll
lo fa pendere come un ago di pino. La spirale in cima è un cono a cinque lati: chiude la sagoma senza
il coperchio piatto che tradiva la pila di cilindri. La variante 1 aggiunge tre rami nudi sotto
l'ombrello, che è ciò che distingue un pino silvestre da un abete a colpo d'occhio.

### 3.2 Querce — tronco che porta la chioma

Tre profili con altezze, estensioni e inclinazioni diverse (larga, alta e stretta, inclinata e
bassa). Il tronco è un `add_limb` piegato con flare radicale (×1,60) e tre **rametti di radice**
che affondano nel pendio: nascondono il punto in cui il tronco incontra il terreno, che una
circonferenza non può fare. Sopra, tre rami visibili (uno solo a distanza) terminano **dentro** la
chioma, così la massa è portata e non incollata. La chioma è un nucleo più lobi posizionati sulle
punte dei rami e poi su anelli irregolari; due rametti nudi escono dalla cima, perché una chioma che
finisce in una cupola pulita è il segno più evidente di un modello primitivo.

### 3.3 Betulle — la specie che prima era una quercia chiara

* **variante 0** — un fusto snello, corteccia chiara, chioma a velo;
* **variante 1** — **due fusti** dalla stessa radice, con chiome sfalsate;
* **variante 2** — betulla d'autunno, più alta, chioma sparsa e accento caldo (`leaf_autumn`).

Le tacche scure sulla corteccia sono due anelli bassi (`add_cylinder` a quattro lati, 16 triangoli
ciascuno): da vicino sono ciò che rende riconoscibile una betulla. La chioma è volutamente **a
vuoti** — quattro ciuffi più un ciuffo centrale, non una palla — perché una betulla in controluce si
legge dai buchi tra le foglie.

### 3.4 Cespugli

Quattro lobi (tre a distanza) con raggi indipendenti sui tre assi, più due rametti che escono dalla
massa e la staccano dalla sagoma di un cuscino. La **variante 2 fiorisce**: otto capolini piccoli in
`cloth_cream` / `cloth_red`, gli stessi colori di tende e insegne, quindi senza un materiale nuovo.
I cespugli non hanno collider: attraversarli è voluto, servono a rompere il bordo del prato e non a
fare da labirinto.

### 3.5 Fiori — un tipo di placement nuovo

`KIND_FLOWER_PATCH` è vegetazione a tutti gli effetti: viene costruita dal `VegetationBuilder`,
entra nei conti dei triangoli e passa dalle stesse regole di piazzamento di alberi e cespugli
(niente strade, niente corridoi delle porte, niente acqua). Ogni chiazza ha **sei steli** (quattro a
distanza) con un capolino sferico, una **rosetta di tre foglie basse** che la ancora a terra e, per
la variante margherita, un centro caldo. Le tre varianti usano `cloth_cream`, `cloth_red` e
`leaf_autumn`: tre accenti già in palette, zero materiali nuovi. Steli e foglie basse poggiano sui
verdi `leaf_mid` / `leaf_bright`, che scartano le facce posteriori: la lama viene quindi emessa due
volte con avvolgimento opposto (quattro triangoli). L'erba non paga questo costo, perché il suo
materiale è già double-sided.

### 3.6 Erba — da billboard a ciuffo

L'erba è l'unica parte **istanziata** della vegetazione, quindi vive in un file a parte,
`meadow_builder.gd`:

* il ciuffo è **cinque lame** rastremate e piegate (`add_blade`), dieci triangoli, **opache**, senza
  texture alpha e con `cull_mode = CULL_DISABLED` — è la geometria, non il ritaglio, a garantire che
  il ciuffo si veda da ogni lato;
* la distribuzione è a **due scale**: metà delle istanze si raccoglie in 260 ciuffi larghi 3,6 m,
  metà è un velo uniforme, così il prato ha radure e macchie e non un rumore regolare;
* il colore non è più un dado per lamina: è un **campo lento** (`_meadow_tint`) che mescola verde
  profondo, verde lussureggiante e oro secco, con un piccolo jitter per ciuffo. Da lontano si leggono
  i campi, da vicino le singole lame;
* vicino allo stagno i ciuffi crescono più alti (canne);
* le istanze non proiettano ombre (`SHADOW_CASTING_SETTING_OFF`): migliaia di lamine non devono
  entrare nella shadow map.

### 3.7 Distribuzione — il bosco, non un disco

Il `VillageLayout` è cambiato nello stesso passaggio, perché una geometria migliore piazzata male
resta un difetto visibile:

* **radure vere.** Tre aperture di 9 m di raggio dentro l'anello degli alberi, salvate in
  `forest_clearings` e verificate dal test. Nessun tronco, nessun cespuglio: sono i punti in cui si
  entra nel bosco invece di girarci attorno.
* **densità ondulata.** La distanza dal centro non è più un disco a densità costante: un'onda
  angolare lenta sposta il bordo, una seconda onda modula la densità. Spariscono sia il cerchio
  perfetto sia la spaziatura uniforme (il test misura il coefficiente di variazione della distanza
  dal vicino più prossimo).
* **specie a fasce.** Una terza onda decide la specie dominante per settore (pineta, querceto,
  betulle), con il 20 % di mescolamento alle cuciture. Prima la specie era un dado per albero.
* **raducole e nodi.** Tre boschetti compatti (3–5 alberi della stessa specie, ellittici) dentro
  l'anello, nove gruppi di cespugli, sedici cespugli singoli, quattordici nodi di alberi e massi
  dentro il villaggio: le distanze non sono più multipli di un passo.
* **verge stradale.** Un albero tiene 1,0 m in più dalla carreggiata rispetto agli altri oggetti:
  senza, la foresta si chiudeva sopra le strade e i sentieri smettevano di leggersi.
* **corridoio delle porte più lungo per gli alberi.** Un tronco a due metri di lato nasconde una
  porta anche quando non blocca il passaggio: gli alberi hanno 3,2 m di vista in più e 0,9 m di
  semilarghezza in più rispetto alle casse. I cespugli bassi mantengono il corridoio corto.
* **erba fuori dai manufatti.** L'erba evita impronte di case, banchi, casse, barili, cataste,
  staccionate, panchine, fioriere e chiazze di fiori.

### 3.8 Prestazioni — più carattere, non più triangoli

| Scelta | Effetto |
| --- | --- |
| Tre primitive nuove, nessun materiale nuovo | draw call invariate |
| Dettaglio per distanza (`needs_detail`) | solo gli alberi entro 44 m dal centro, o entro 6 m da una strada, ricevono chioma e rami pieni; il bosco di bordo usa una sagoma più povera ma ancora specifica per specie |
| Erba: 10 triangoli per ciuffo, una `MultiMesh` | una draw call, nessuna ombra, nessun alpha |
| Fiori e cespugli senza collider | nessun collider in più |

Non è stata aggiunta nessuna luce, nessuna ombra dinamica in più e nessun nodo per albero: la
vegetazione resta **fusa per materiale** in poche mesh, come prima. La stima statica del passaggio
(port Python delle regole di piazzamento, seed `20261019`, mappa 160 celle) dà **circa 45 000–55 000
triangoli** per tutta la vegetazione, fiori compresi. L'ultima misura reale dell'intera scena è
quella di Polish 15: **230 740 triangoli su 260 000**, con ~29 000 di margine; anche nell'ipotesi
peggiore della stima il totale resterebbe sotto il tetto. È una stima, non una misura: il numero
vero esce dal log della suite di integrazione (vedi §4.2 e §5).

## 4. Verifiche

### 4.1 Controlli statici

Eseguiti in questo ambiente:

```
python3 tools/check_project.py     → RESULT: OK
gdparse su tutti i file toccati    → OK
gdlint su vegetation_builder.gd / meadow_builder.gd / vegetation_review.gd → 0 problemi
```

`check_project.py` verifica i riferimenti `res://`, il cablaggio delle scene, i percorsi `$Nodo`
usati dagli script, le azioni di input e i `class_name` duplicati: è la rete che intercetta una scena
che non si apre, senza bisogno del motore.

### 4.2 Test headless — scritti, **non eseguiti**

Nuovo `tests/unit/test_vegetation.gd` (registrato in `tests/run_tests.gd`), che verifica:

* **determinismo** — due costruzioni con lo stesso seed producono la stessa sagoma;
* **varianti distinguibili** — le tre varianti di ogni specie differiscono per ingombro misurato
  sulla mesh fusa, non per commento;
* **tronco rastremato** — raggio di base almeno il doppio del raggio in cima;
* **chioma a più masse** — almeno quattro ciuffi;
* **dettaglio** — la versione a distanza costa meno ma non è vuota;
* **palette** — i fiori riusano tre accenti esistenti e non aggiungono materiali;
* **piazzamento** — foresta > 100 alberi, tutte e tre le specie presenti, verge stradale rispettata,
  nessun albero nel corridoio di una porta, tre radure davvero vuote, spaziatura irregolare
  (CV > 0,15), chiazze di fiori fuori dall'acqua;
* **collisioni** — ogni albero ha un cilindro che copre il proprio tronco, cespugli e fiori non
  bloccano il giocatore, i sassi piccoli nemmeno;
* **erba** — istanze > 500, ciuffo di 8–16 triangoli, materiale **opaco**, nessuna ombra;
* **budget** — la vegetazione intera resta sotto 90 000 triangoli.

E `tests/unit/test_mesh_baker.gd` / `test_village_materials.gd` sono stati estesi con i controlli
delle tre primitive nuove (avvolgimento delle facce, lobatura del ciuffo, lama a due triangoli) e
della lamina d'erba opaca.

> **Onestà sulla verifica.** In questo ambiente **non esiste un eseguibile Godot** e non è stato
> possibile scaricarne uno (GitHub Objects bloccato, nessun pacchetto npm/pip utilizzabile). I test
> qui sopra **non sono stati eseguiti**: sono stati scritti e verificati solo sintatticamente con
> `gdparse`, e le loro asserzioni sono state confrontate a mano con le API reali. Di conseguenza
> **non è stato possibile verificare a schermo** né le sagome né le collisioni né la navigazione:
> il §5 lo dichiara come limite, non come risultato.

### 4.3 Confronto visivo — `tests/visual/vegetation_review.tscn`

La scena costruisce il villaggio vero (stesso seed, stesso terreno), senza giocatore né NPC, e
propone cinque viste che corrispondono alle cinque domande dell'intervento:

1. **tronco di quercia a un braccio di distanza** — rastremazione, flare radicale, rami reali;
2. **chioma di pino da sotto, contro il cielo** — la sagoma è ancora un cono?
3. **cespuglio e chiazza di fiori all'altezza del ginocchio** — i dettagli si leggono?
4. **prato rasoterra** — ciuffi, forma della lama, colore a chiazze;
5. **linea degli alberi dal villaggio, a 55 m** — ripetizione e massa a distanza.

Tasti `1`–`5`, `F5` per l'ultima vista, rotella per la distanza, frecce per orbitare e alzare
l'inquadratura. All'avvio la scena stampa il censimento di specie e varianti e quanti esemplari
ricevono il dettaglio pieno, così un rieseguimento dice anche se il mix o il budget si sono mossi.

## 5. Limiti dichiarati

* **Il motore non è stato eseguito.** Nessuna immagine è stata prodotta, nessuna collisione è stata
  provata in gioco, nessun percorso NPC è stato attraversato. Tutto ciò che riguarda l'aspetto a
  schermo resta da confermare con la scena di review.
* **I numeri di triangoli sono stime statiche.** La cifra «~45 000–55 000» viene da un port Python delle
  regole di piazzamento e dei conteggi di primitive, non dal motore. La misura vera va letta dal log
  `[INFO] Budget measured:` della suite di integrazione.
* **La distribuzione è cambiata in modo visibile.** Chi confronta con una build precedente vedrà un
  bosco più aperto e meno circolare: è voluto, ma è anche un cambiamento di composizione, non solo
  di dettaglio.
* **I fiori sono vegetazione fusa, non decorazione.** Restano fuori dalle strade e dai corridoi
  delle porte, ma non hanno collider: attraversarli è previsto, come per l'erba.

## 6. File toccati

| File | Intervento |
| --- | --- |
| `src/world/environment/mesh_baker.gd` | `add_limb`, `add_foliage_clump`, `add_blade` e i loro helper |
| `src/world/environment/vegetation_builder.gd` | riscrittura: pini, querce, betulle, cespugli, fiori, massi |
| `src/world/environment/meadow_builder.gd` | **nuovo**: erba istanziata e campo di colore |
| `src/world/environment/village_layout.gd` | radure, densità ondulata, fasce di specie, nodi, fiori, verge e corridoi |
| `src/world/environment/village_materials.gd` | lama d'erba opaca (`CULL_DISABLED`, nessun alpha) |
| `src/world/environment/village_builder.gd` | `is_vegetation()` e dettaglio per distanza |
| `tests/unit/test_mesh_baker.gd` | test delle tre primitive |
| `tests/unit/test_village_materials.gd` | test della lamina opaca |
| `tests/unit/test_vegetation.gd` | **nuovo**: suite completa della vegetazione |
| `tests/unit/test_village_art.gd` | `flower_patch` tra i tipi costruiti |
| `tests/run_tests.gd` | registrazione di `TestVegetation` |
| `tests/visual/vegetation_review.gd` / `.tscn` | **nuovo**: scena di confronto a cinque viste |
