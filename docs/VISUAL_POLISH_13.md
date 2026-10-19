# EVERAFTER — Visual Polish 13: Tetti credibili e silhouette architettoniche

Questo documento descrive l'intervento **Visual Polish 13**, focalizzato sulla ricostruzione procedurale delle coperture architettoniche, dei raccordi strutturali e delle silhouette dei tetti di tutti gli edifici del villaggio senza modificare layout urbano, collisioni o funzionalità di gioco.

---

## 1. Diagnosi geometrica preliminare (`BEFORE`)

L'analisi dei mesh generati in `BuildingArchitecture` e `BuildingFactory` (verificata sia tramite ispezione del codice sia tramite estrazione e rendering 3D multi-angolo delle 7 tipologie strutturali e delle viste del villaggio) ha evidenziato limiti geometrici strutturali nelle coperture precedenti:

1. **Falde ridotte a griglie di box piatti uniformi (`BuildingArchitecture._roof_pair`)**:
   - Ogni falda era composta da un profilo base sottile e da una griglia uniforme di `rows × cols` box identici (`s_h = 0.048 m`) con minime variazioni di tinta (`±0.035`), producendo superfici percepite a media distanza come piani colorati quasi piatti, prive di distinzione morfologica tra tegole in terracotta (`roof_tile`), scandole in legno (`roof_shingle`, `roof_moss`) e lastre in ardesia (`roof_slate`).
2. **Assenza di sottogronda, banchine, grondaie, scossaline e falde svasate (bell-cast)**:
   - I travetti sporgevano senza banchina d'appoggio (wall plate) sulla muratura, senza tavolato d'intradosso (soffit planking), senza canale di gronda e senza lo svaso terminale di gronda (*bell-cast kick*) tipico dei tetti vernacolari.
3. **Timpani e frontoni spogli e privi di carpenteria di colmo**:
   - I timpani (`_facade`) presentavano solo un montante verticale centrale senza catena (tie-beam), saette (collar struts), prese d'aria a gelosia (louvered attic vents), teste d'arcareccio sporgenti (purlin tails), mantovane modanate (bargeboard + weather-fillet) o pennacchi/pinnacoli d'apice.
4. **Tetti privi di abbaini (dormers) e silhouette ripetitive**:
   - Nessuna abitazione e neppure il Municipio (`KIND_HALL`) o la Locanda (`KIND_INN`) possedeva abbaini a doppia falda, lasciando le lunghe falde della Casa Lunga (`variant 2`), della Locanda e del Municipio monotone.
5. **Comignoli privi di grembiule inclinato (saddle flashing) e di canne fumarie**:
   - `_chimney` era un semplice parallelepipedo verticale con anello piatto, privo di raccordo inclinato lungo la pendenza della falda e privo di torrini/mitre fumarie superiori.
6. **Guglia della torre campanaria (`_belfry`) ridotta a un cono singolo**:
   - La copertura della torre civica usava un unico tronco piramidale ottagonale senza mensole lapidee di coronamento, senza ordini sovrapposti di lastre d'ardesia e senza lucernari (lucarnes).
7. **Pozzo centrale (`BuildingFactory._build_well`) e Banchi del mercato (`_build_stall`)**:
   - Il tetto del pozzo usava un prisma pieno di scandole (`add_prism("roof_shingle", ...)`) che chiudeva i timpani sopra la vasca anziché mostrare una capriata aperta (*open king-post truss*), mentre i listelli terminali sporgevano incrociati oltre il colmo.
   - Il tendone dei banchi del mercato era una lastra piatta attraversata dai montanti anteriori e posteriori (visibili come quadrati scuri sulla faccia superiore del telo) e priva di telaio ligneo di supporto.

---

## 2. Soluzione procedurale riusabile (`RoofArchitecture`)

È stato introdotto il modulo procedurale riusabile `src/world/environment/roof_architecture.gd` (`class_name RoofArchitecture`), progettato con parametri espliciti e guardie geometriche (`sanitize_spec`) contro dimensioni degenerate:

- **Guardie e vincoli proporzionali (`sanitize_spec`)**:
  - `span` e `length` vengono vincolati a `>= 1.2 m`.
  - La freccia (`rise`) rispetto alla luce (`span`) viene mantenuta nell'intervallo coerente `[span * MIN_PITCH_RATIO, span * MAX_PITCH_RATIO]` (`MIN_PITCH_RATIO = 0.24`, `MAX_PITCH_RATIO = 0.95`), evitando tetti piatti o cuspidi degenerate al variare delle dimensioni dell'edificio.
  - Gli sbalzi di gronda (`overhang_eave`) e di timpano (`overhang_front`, `overhang_back`) vengono limitati proporzionalmente alla semiluce e alla lunghezza del corpo di fabbrica.
- **Struttura portante di falda e contatto tetto-parete (`_build_slope_structure`)**:
  - Profilo chiuso di falda con letto d'ombra arretrato + tavolato d'intradosso in legno caldo (`plank`) visibile dal basso sotto gli sbalzi.
  - Banchina lignea (`timber` wall plate) all'imposta della muratura per generare un netto incasso d'ombra tra parete e sottogronda.
  - Travetti di gronda (`rafter tails`) cadenzati, fascia frontale, canale di gronda in legno o pietra scura e svaso terminale (*bell-cast kick*) sulla prima fila di gronda.
- **Coperture differenziate per stile costruttivo (`_build_slope_courses`)**:
  - **Tegole in terracotta (`style = "tile"`)**: corsi sovrapposti con letto d'ombra scuro, tegole piane sfalsate e nervature longitudinali di coppi a rilievo (`coppi` barrel ribs) fino alla gronda, con colmo a coppi embricati e selle di malta.
  - **Scandole lignee / copertura muschiosa (`style = "shingle" | "moss"`)**: corsi sovrapposti di scandole spaccate a larghezza e spessore variabili con giunti verticali sfalsati, variazioni cromatiche controllate per seme (`seed_val`) e cavalieri di colmo incrociati (*crossed timber ridge riders*).
  - **Lastre d'ardesia (`style = "slate"`)**: grandi lastre rettangolari sfalsate a giunto stretto con fascia marcapiano chiara a mezza falda (`belt_row`) e cresta di colmo in pietra scura (`stone_dark`).
- **Timpani, colmi, abbaini, pensiline e comignoli**:
  - `_build_gable_end`: catena d'imposta, monaco centrale (king-post), saette diagonali, feritoia di ventilazione del sottotetto, teste d'arcareccio sporgenti con modiglioni, mantovana a doppio ordine e finale d'apice (ligneo per gli edifici a graticcio, lapideo per il Municipio).
  - `build_gable_dormer`: abbaino a doppia falda posizionato a mezza falda, completo di guance intonacate, stipiti lignei, finestra vetrata con traversini, davanzale in pietra e tettoia in scala con colmo dedicato.
  - `build_entry_hood`: pensilina d'ingresso con scossalina in pietra scura incassata nella parete, trave banchina, saette diagonali, fascia di gronda e corsi di copertura coordinati al tetto principale.
  - `build_chimney`: canna fumaria che si innesta nella falda con grembiule/scossalina inclinata in pietra scura e ferro (*stepped stone saddle flashing*), fusto in conci di pietra stratificati, collarino modanato, coronamento differenziato (`crown_style = 0, 1, 2`: torrini cilindrici in terracotta/ferro o cappa lapidea a due falde su pilastrini) e bocche superiori.
  - `build_belfry_spire`: guglia ottagonale a 3 ordini sovrapposti (*lapped slate tiers*) su mensole lapidee, con 4 lucernari cardinali (*lucarnes*) e croce apicale con segnavento in ferro battuto.

---

## 3. Variazioni controllate e interventi per tipologia (`AFTER`)

1. **Case del villaggio (`BuildingArchitecture._house`, varianti `0`, `1`, `2` + `placement.id` hash)**:
   - **Cottage (`variant 0`)**: tetto a pendenza vivace (`span = 4.4 m`, `length = 4.0 m`, `eave_y = 3.07 m`, `rise = 2.05 * pitch_scale`), tegole in terracotta, scandole o copertura muschiosa secondo `placement.id`, comignolo e abbaino sul versante opposto.
   - **Casa a due piani (`variant 1`)**: falda ripida nord-europea (`span = 4.4 m`, `length = 4.0 m`, `eave_y = 4.62 m`, `rise = 2.20 * pitch_scale`), abbaino di sottotetto e comignolo alto sul versante opposto.
   - **Casa lunga (`variant 2`)**: corpo trasversale (`5.8 × 3.4 m`, `eave_y = 3.27 m`, `rise = 1.85 * pitch_scale`) con copertura in ardesia, scandole o muschio, abbaino singolo o doppio (`twin_dormers`) sulla falda principale verso strada e comignolo arretrato.
2. **Locanda (`BuildingArchitecture._inn`)**:
   - Copertura principale in scandole lignee (`span = 8.2 m`, `length = 5.6 m`, `eave_y = 5.42 m`, `rise = 3.25 m`) con due abbaini simmetrici a mezza falda e grande comignolo a doppia canna.
   - Ala cucina laterale (`2.8 × 3.2 m`) in tegole di terracotta con scossalina in pietra contro la parete ovest della locanda (`gable_front = false`), travetti di sottogronda e comignolo dedicato.
3. **Municipio e Torre Civica (`BuildingArchitecture._hall` e `_belfry`)**:
   - Copertura della navata in lastre d'ardesia lungo l'intero corpo di `9.4 m` (`span = 5.4 m`, `eave_y = 4.7 m`, `rise = 2.48 m`), raccordata alla parete est della torre campanaria tramite scossalina inclinata in pietra scura (*saddle flashing collar*) ben al di sotto della cella campanaria aperta (`y = 7.75 m`).
   - Coppia di abbaini istituzionali sulla falda verso la piazza (`dz = -1.4, 1.9`) e comignolo civico con cappa in pietra sul versante opposto.
   - Guglia campanaria ottagonale a 3 ordini sovrapposti (`base_y = 9.5 m`, `base_radius = 2.48 m`, `total_height = 2.65 m`) con 4 lucernari cardinali e pinnacolo in ferro battuto.
4. **Pozzo centrale (`BuildingFactory._build_well`)**:
   - Sostituito il prisma pieno del timpano con una vera **capriata aperta a monaco centrale** (`open_truss = true`: catena, monaco, saette diagonali e arcarecci) lasciando libera la visuale attraverso il tetto del pozzo; copertura in scandole a corsi sovrapposti con cavalieri di colmo incrociati.
5. **Banchi del mercato (`BuildingFactory._build_stall`)**:
   - I montanti lignei si innestano ora in un **telaio perimetrale di banchine e travetti inclinati** sotto il telo, eliminando la compenetrazione dei pali attraverso la superficie superiore del tendone; il telo è suddiviso in teli cuciti con nervature in legno e mantovana anteriore e laterale festonata.

---

## 4. Budget prestazionale e verifiche automatiche

Tutti i limiti di budget e i test geometrici/funzionali del progetto sono pienamente rispettati:

| Metrica | Prima (`HEAD`) | Dopo (`Visual Polish 13`) | Limite di budget |
| :--- | :---: | :---: | :---: |
| Materiali condivisi nel villaggio | 19 | **19** | `<= 24` |
| Mesh per edificio (`variant 0..4`) | `9 / 9 / 9 / 12 / 9` | **`9 / 9 / 9 / 12 / 9`** | `<= 12` |
| Mesh totali nel mondo (`MainWorld`) | 227 | **227** | `<= 260` |
| Triangoli totali nel mondo (`MainWorld`) | 212 910 | **252 958** | `<= 260 000` |
| Collider totali nel mondo (`MainWorld`) | 352 | **352** | `<= 900` |

- `tools/check_project.py`: **OK**
- `gdlint` / `gdformat --check`: **OK (0 warning / 0 errori)**
- `res://tests/run_building_tests.gd`: **133 / 133 test superati**
- `res://tests/run_tests.gd`: **1616 / 1616 test superati**
- `res://tests/run_world_tests.gd`: **179 / 179 test superati**
