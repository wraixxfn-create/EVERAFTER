# Visual Polish 12 — ricostruzione degli edifici

## Audit e scelta degli interventi

| Tipologia esistente | Problema riscontrato | Intervento |
| --- | --- | --- |
| Casa piccola, variante 0 | Corpo pieno, aperture sovrapposte, annesso posteriore fuori collisione | Cottage a campate, involucro con aperture vere, timpano e tetto separati, ingresso a mensole |
| Casa alta, variante 1 | Scatola unica; abbaino collocato senza seguire la falda | Due piani distinti, sporto superiore di 10 cm sostenuto da mensole; eliminato l'abbaino incoerente |
| Casa lunga, variante 2 | Stessa costruzione allargata; annesso e portico fuori ingombro; scala applicata più volte | Corpo largo con colmo trasversale, tetto più compatto, ingresso senza pali sulla strada |
| Locanda | Ala composta da scatola/prisma, finestre nelle giunzioni, tettoia poco sostenuta | Due piani e ala bassa raccordata nel volume esistente, aperture escluse dai giunti, insegna sospesa con staffa |
| Municipio | Muratura piena, tetto parzialmente sepolto nella sommità della parete, campanile pieno | Facciate in pietra con aperture, contrafforti rastremati, tetto trasversale alla quota corretta, camera campanaria aperta sui quattro lati |
| Pozzo | Già ricostruito con corsi radiali, vera apertura e copertura sostenuta | Conservata la tipologia; beneficia della correzione delle primitive |
| Bancarelle | Struttura leggera appropriata, non abitazioni da rivestire | Conservati teli, banco e sostegni; corretti i volumi tramite il baker condiviso |

### Difetto nel generatore di base

`MeshBaker.add_box()` generava le sei facce **attraverso il centro** del parallelepipedo:
non aggiungeva l'offset della faccia lungo la normale. Il risultato era un incrocio di
rettangoli, non un volume chiuso. Era la causa di molti spigoli mancanti, fasce spurie e
giunti visivamente aperti, anche su travi e comignoli. Ora ogni faccia è sul bordo corretto.
Un test verifica che tutti i vertici di una scatola 2×4×6 siano veri vertici di contorno;
un controllo dei soli AABB non avrebbe rilevato il difetto precedente.

Corrette anche le normali dei tronchi di cono e le punte dei coni: il tetto del campanile
non contiene più triangoli di area zero. La correzione del baker è condivisa anche dagli
oggetti esistenti, senza cambiarne trasformazioni, ingombri nominali o collider.

## Kit geometrico comune

`src/world/environment/building_architecture.gd` sostituisce il vecchio percorso abitativo
di `BuildingFactory`, non vi aggiunge un secondo rivestimento:

- Basamento di 42 cm, corsi sfalsati con giunti e lastra di coronamento.
- Pareti spesse 22 cm, assemblate attorno ai rettangoli delle aperture. Niente muro pieno
  dietro vetri e porte. Spallette, architravi, davanzali e soglie hanno profondità reale.
- Montanti, piastre, correnti inferiori interrotti sulle porte, saette e mensole collegati
  alla struttura. Solai arretrati all'interno delle pareti, senza facce coplanari sull'intonaco.
- Porte a tavole incassate, bandelle e maniglia; vetri arretrati, crociere e scuri nel vano.
- Timpani alla faccia del muro, non sul bordo esterno dello sporto.
- Falde indipendenti con sezione chiusa e bordo smussato, corsi di copertura con giunti
  sfalsati, copricolmo, tavole di bordo, gronde e code dei puntoni. Tutto deriva dalla
  stessa equazione della pendenza, senza inclinazioni indipendenti che deformino i tetti.
- Camini che iniziano sotto l'intersezione col tetto, corsi e copertina con canna aperta.
- Municipio con campana sospesa dentro la camera aperta e guglia quadrangolare.

Le sezioni sagomate usano `MeshBaker.add_profile()`: estrusione chiusa di un poligono XY,
triangolazione delle testate e orientamento automatico anche per profili specchiati.
Non è un insieme di cubi ornamentali applicati al vecchio corpo pieno.

### Varianti e ingombri nominali (metri, prima della scala di placement)

| Variante | Corpo principale X×Z | Sommità pareti | Identità |
| --- | --- | --- | --- |
| Cottage | 4,4×4,0 | 3,07 | Un piano, timpano frontale, tegole calde |
| Casa alta | 4,4×4,0 | 4,62 | Due livelli, sporto su mensole, copertura in scandole |
| Casa lunga | 5,8×3,4 | 3,27 | Colmo trasversale, copertura in ardesia |
| Locanda | 8,2×5,6 | 5,42 | Due piani, ala laterale bassa e insegna |
| Municipio | 9,4×5,4 | 4,70 | Pietra, copertura trasversale e torre civica |

Non sono stati allargati strade, lotti o corridoi di ingresso. I vecchi annessi esterni
alle collisioni delle case sono stati rimossi. L'ala della locanda rimane nel relativo
volume di collisione esistente; il piccolo sporto delle coperture è intenzionale.

## Compatibilità e dipendenze

- Stessa API `build_structure()` / `bake_structure()` e stessi ID dei placement.
- Stesso nodo radice per edificio, mesh `Baked_<materiale>` e figlio `Collision`.
- `colliders_for()` invariato: quantità, dimensioni, offset, layer e forma delle collisioni
  precedenti conservati. Porte e finestre sono aperture della mesh, **non nuove entrate
  percorribili**; gli interni non sono una nuova funzionalità di questa revisione.
- Nessuna modifica a layout, quote dei lotti, punti d'accesso NPC, grafo dei percorsi,
  salvataggi, assegnazione delle abitazioni o interazioni.
- Scala applicata una sola volta dal kit, anche su locanda e municipio.
- Materiali e bagliore notturno riutilizzano `VillageMaterials`; nessun nuovo materiale,
  shader, texture o asset esterno. Geometria originale procedurale, nessuna licenza di
  risorse esterne da verificare o attribuire.
- Per avviare il mondo reale era necessaria una correzione minima preesistente in
  `VegetationBuilder._transform()`: accetta ora yaw/pitch/roll già passati dai suoi chiamanti,
  anziché fallire in compilazione. Nessun cambiamento a placement o collider vegetali.
- I runner attendono la registrazione degli autoload prima di caricare le dipendenze
  del mondo/SkyRig. Questo elimina i falsi errori `Game` non registrato all'avvio dei test.

## Verifica eseguita

Runtime disponibile tramite build Godot **4.7.2 WASM** ottenuta dal pacchetto npm
`@ringozz/godot-web-wasm32`, usata soltanto come strumento di verifica fuori dal repository.
Rendering reale WebGL 2 / Compatibility in Chromium con SwiftShader. Non è una verifica
su GPU nativa né una misura FPS del renderer Forward+.

- `tools/check_project.py`: **OK**.
- `gdparse`: **89 script analizzati**, OK.
- Suite mirata (`tests/run_building_tests.gd`): **99 controlli superati**.
- Suite unitaria completa (`tests/run_tests.gd`): **1582 controlli superati**.
- Mondo reale (`tests/run_world_tests.gd`): **179 controlli superati**, inclusi collisioni
  del giocatore, terreno, NPC, economia, socialità e illuminazione.
- Mondo di default: **227 mesh, 242384 triangoli, 352 collider**, sotto i limiti
  260 / 260000 / 900. **0 luoghi NPC irraggiungibili**.
- Geometria per variante: cottage 4420 triangoli / 9 mesh; casa alta 6436 / 9;
  casa lunga 4816 / 9; locanda 10832 / 12; municipio 9264 / 9.
- Test nuovi: normali e winding di tutte le facce, nessun triangolo degenere, vertici
  finiti, profili di tetto chiusi anche specchiati, raggi attraverso le aperture dei muri,
  scala lineare di tutti i componenti, nomi dei nodi e numero delle collisioni preservati;
  separazione verticale fra campana e colmo della navata.
- Ispezione WebGL delle cinque varianti da viste frontali, laterali e posteriori nella
  scena di revisione. Corretti i falsi volumi del baker, i piccoli conci terminali di
  dimensione negativa, le intersezioni dei solai e le finestre nel raccordo della locanda.
  La camera campanaria è stata rialzata sopra il colmo della navata: nessuna falda
  attraversa le aperture o la campana.
- Lint dei nuovi moduli, baker, factory e runner: OK. Il lint globale segnala ancora
  **20 problemi di stile preesistenti** in altri punti (anche nelle vecchie righe della
  vegetazione); non è stato effettuato un riordino cosmetico dell'intero progetto.
- Il renderer dummy segnala RID/ObjectDB ancora in uso alla chiusura del runner del
  mondo, come già documentato nel runner; i 179 controlli terminano con esito positivo.

### Riprodurre la revisione

```sh
godot --headless --path . --script res://tests/run_building_tests.gd
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_world_tests.gd
godot --path . res://tests/visual/building_review.tscn
```

La scena di revisione è isolata: non carica o modifica salvataggi. Tasti **1–5** per
cottage, casa alta, casa lunga, locanda e municipio; **frecce** per orbita/elevazione,
**rotella** per distanza; **F1** frontale a tre quarti, **F2** lato, **F3** retro a tre
quarti, **F4** vista alta. La scena principale e la camera del giocatore non cambiano.
