# EVERAFTER — Rifinitura visiva di NPC e interfaccia (Visual Polish 05)

Questo documento registra l'analisi e gli interventi di rifinitura visiva effettuati sulla
rappresentazione 3D degli abitanti (`src/world/npcs/`) e sull'interfaccia utente (`src/ui/`).
**Nessuna logica di simulazione, ID, professione, bisogno, relazione, memoria o formato di
salvataggio è stata alterata**: i moduli `src/npcs/`, `src/economy/`, `src/social/`,
`src/history/` e `src/persistence/` restano invariati.

---

## 1. Problemi reali individuati prima dell'intervento

### 1.1 Personaggi 3D (`src/world/npcs/npc_presenter.gd`)

1. **Geometria provvisoria "a pillola" e scala fuori proporzione rispetto al villaggio.**
   Ogni abitante era rappresentato da un'unica `CapsuleMesh` monocromatica alta `1,70 m` con una
   sfera per la testa centrata a `1,88 m` e una calotta di capelli fino a `2,14 m` (`NameLabel`
   a `2,35 m`). Poiché le porte delle case (`BuildingFactory._build_house`) sono alte `1,85 m` e
   il giocatore è alto `1,80 m`, ogni abitante appariva come un cilindro fluttuante alto più di
   due metri, più alto degli stipiti delle porte e privo di gambe, braccia, spalle o calzature.
2. **Assenza di distinzione visiva tra i mestieri oltre al colore base.**
   Tutte le 16 professioni del roster (`farmer`, `innkeeper`, `merchant`, `clerk`,
   `quarry_worker`, `forager`, `fisher`, `weaver`, `woodcutter`, `baker`, `farmhand`,
   `archivist`, `potter`, `cook`, `shepherd`, `gardener`) condividevano la stessa identica
   silhouette (capsula + anello marrone + sfera). Da media distanza era impossibile distinguere
   un boscaiolo da una cancelliera o una panettiera da un pescatore.
3. **Posa rigida e rotazioni istantanee.**
   Durante il cammino la capsula traslava sul terreno senza oscillazione degli arti e ruotava di
   scatto (`node.rotation.y = atan2(...)` in un singolo frame). Durante le attività (`WORKING`,
   `EATING`, `SOCIALIZING`, `RESTING`, `SLEEPING`, `IDLE`, `BLOCKED`) il modello rimaneva
   completamente immobile nella stessa posa verticale.
4. **Indicatore di selezione pieno e poco leggibile.**
   `SelectedRing` utilizzava una `CylinderMesh` piena (un disco giallo piatto sotto i piedi, non
   un anello forato) e `NameLabel` mostrava soltanto il nome con lo stesso colore sia per gli
   abitanti selezionati sia per quelli non selezionati.

### 1.2 Interfaccia e HUD (`src/ui/`)

1. **Assenza di stato della simulazione e mirino in `WorldHud`.**
   `WorldHud` mostrava solo titolo, giorno/ora e area: premendo `P` (pausa) o `+`/`-` (velocità
   `x1`, `x3`, `x10`) non compariva alcun indicatore visivo nell'HUD principale. Inoltre, con il
   mouse catturato in prima persona mancava un mirino centrale (`Crosshair`) per puntare gli
   abitanti, mentre con il mouse libero il suggerimento in basso era testo nudo senza sfondo,
   poco leggibile contro il cielo o i lastricati chiari.
2. **`NpcPanel` occupava l'intera altezza destra dello schermo anche senza selezione.**
   Il pannello aveva un'altezza fissa di `708 px` (`offset_top = 18`, `offset_bottom = 726` su
   una finestra `1600×900`) anche all'avvio quando nessun abitante è selezionato, coprendo un
   quarto della scena 3D con righe vuote (`"—"`, barre a zero). Inoltre la voce `0` del menu a
   tendina (`Selector`) era disabilitata, impedendo di chiudere/deselezionare la scheda.
3. **`EconomyPanel` privo di gerarchia cromatica sui flussi e sulle carenze.**
   L'etichetta `ShortagesLabel` aveva sempre lo stesso colore ambra anche quando recitava
   *"Carenze: Nessuna carenza attiva"*, facendola sembrare un avviso d'errore permanente, mentre
   le scorte in esaurimento non cambiavano colore nella tabella e i testi secondari a `11 px`
   risultavano troppo piccoli.
4. **`SaveLoadPanel` e `DiagnosticsHud` con controlli di default e sovrapposizioni.**
   `SaveLoadPanel` usava pulsanti e menu a tendina con il tema grigio predefinito del motore;
   `DiagnosticsHud` (`F1`) non aveva alcuno `StyleBoxFlat` ed era posizionato a `(16, 16)`,
   sovrapposto esattamente a `WorldHud` e `EconomyPanel`.

---

## 2. Interventi sui personaggi (`NpcVisualFactory` + `NpcPresenter`)

### 2.1 Proporzioni coerenti con il mondo (`NpcVisualFactory`)

* **Altezza base riportata a `1,72 m`** (`BASE_HEIGHT = 1.72`), in scala con il giocatore
  (`1,80 m`), le porte delle case (`1,85 m`), le panchine (`0,56 m`) e i banchi del mercato
  (`1,05 m`).
* **Variazione individuale deterministica (`stature_scale_for`)**: derivata dall'hash stabile di
  `record.id` e dall'età (`[0.96..1.04]` in altezza, `[0.95..1.05]` in corporatura), mantenendo
  sempre le suole degli stivali ancorate a `y = 0,0`.
* **Rig procedurale articolato (`BodyRig`)**:
  * `LeftLeg` e `RightLeg` (imperniati alle anche a `y = 0,72 m`): coscia con brache in tessuto
    (`hose_cloth`), stivale in cuoio scuro (`boot_dark`) e punta del piede orientata lungo `-Z`;
  * `TorsoPivot`: gonnellino della tunica svasato (`TunicSkirt`), busto (`Torso`) nel colore del
    mestiere, colletto/scollo (`Collar`), cintura in cuoio (`Belt`) con fibbia in ottone
    (`BeltBuckle` sul fronte `-Z`), nodo `OutfitDetail` per abiti e accessori di mestiere;
  * `LeftArm` e `RightArm` (imperniati alle spalle a `y = 1,27 m`): manica superiore, avambraccio
    (rimboccato per i mestieri manuali, a manica lunga per i ruoli civici) e mano (`Hand`);
  * `HeadPivot`: collo, testa ovale (`Head`), ponte del naso e occhi sul fronte `-Z` per rendere
    immediatamente leggibile la direzione dello sguardo, calotta di capelli + volume sulla nuca
    (`HairBack`) + chignon/raccolto (`HairBun`, con chioma grigio-argento per gli abitanti più
    anziani ≥ 55 anni) e nodo `Headgear`.

### 2.2 Differenze visive tra le professioni

Ogni professione del catalogo (`NpcRoster` + `EconomyRules`) combina un **taglio d'abito**, un
**copricapo** e un **accessorio di lavoro** distinti:

| Gruppo di mestieri | Professioni (`profession_id`) | Abito (`OutfitDetail`) | Copricapo (`Headgear`) | Accessorio / Zaino |
| --- | --- | --- | --- | --- |
| **Campi e orti** | `farmer`, `farmhand`, `gardener` | Tunica da campo con pettorina e maniche rimboccate | Cappello di paglia a tesa larga con fascia | Bisaccia delle sementi al fianco |
| **Bosco e pascolo** | `forager`, `shepherd`, `healer` | Mantellina corta sulle spalle (`ShoulderCape`) | Cappuccio a punta in panno | Cesto di vimini sulla schiena / fagotto |
| **Stagno** | `fisher` | Gilet impermeabile color ardesia (`WorkVest`) | Cappello da pescatore a tesa spiovente | Nassa di vimini per il pescato |
| **Locanda e forno** | `innkeeper`, `baker`, `cook` | Grembiule intero in lino chiaro (`ApronBib` + `ApronSkirt`) | Toque bianca da fornaio (`baker`, `cook`) o fazzoletto annodato (`innkeeper`) | Canovaccio e scarsella alla cintura |
| **Legno e pietra** | `woodcutter`, `carpenter`, `quarry_worker`, `miner`, `blacksmith` | Imbracatura/corpetto da fatica in cuoio (`LeatherVest`) | Berretto di lana (`woodcutter`) o fascia da lavoro in cuoio (`quarry_worker`) | Fascina di legna (`TimberPack`) o telaio porta-pietre (`StonePack`) |
| **Bottega d'arte** | `potter`, `weaver` | Casacca/tabarro da artigiano con bordatura | Basco morbido inclinato (`ArtisanBeret`) | Anfora in terracotta (`potter`) o rotolo di stoffa (`weaver`) |
| **Mercato e consiglio** | `merchant`, `clerk`, `archivist` | Pellegrina drappeggiata (`CivicMantle`) con fermaglio in ottone (`BrassBrooch`) | Chaperon con spilla (`merchant`) o birretta da cancelliere (`clerk`, `archivist`) | Custodia dei registri in cuoio e borsa delle monete |

Tutte le mesh primitive e i materiali sono istanziati una sola volta in `NpcVisualFactory` e
condivisi fra tutti gli abitanti visibili, mantenendo il costo sulla GPU trascurabile.

### 2.3 Pose procedurali, transizioni e limiti dichiarati

* **Limite architetturale dichiarato con onestà**: come stabilito in `docs/ARCHITECTURE.md`
  (regola 7: *niente asset binari nel repository*), il progetto non include modelli 3D `.glb`/`.fbx`
  con `Skeleton3D` o clip `AnimationPlayer`.
* **Sistema procedurale implementato**: `NpcPresenter` interpola ad ogni frame con `lerpf`
  (`POSE_BLEND_SPEED`) e `lerp_angle` (`TURN_SPEED`) le rotazioni dei pivot articolati
  (`LeftLeg`, `RightLeg`, `TorsoPivot`, `LeftArm`, `RightArm`, `HeadPivot`) in base a
  `NpcRecord.activity` e alla velocità reale di spostamento:
  * `WALKING`: passo alternato di gambe e braccia in controfase, leggero bob verticale e
    inclinazione del busto;
  * `WORKING`: busto flesso in avanti e movimento ritmico coordinato delle braccia;
  * `EATING`: braccio destro che si solleva periodicamente verso il volto e leggero cenno del
    capo;
  * `SOCIALIZING`: oscillazione espressiva delle braccia e rotazione del capo da conversazione;
  * `RESTING` / `SLEEPING`: postura raccolta con capo reclinato e respiro lento;
  * `IDLE` / `BLOCKED`: respiro leggero e rotazione d'osservazione del capo.
* **Selezione nel mondo 3D**: `SelectedRing` utilizza ora una vera `TorusMesh` forata doppia in
  oro luminoso + un indicatore a diamante sopra il capo (`SelectionBeacon`) con pulsazione
  morbida; quando un abitante è selezionato, compare sotto il nome anche `RoleLabel`
  (`"Mestiere · Attività"`).

---

## 3. Interventi sull'interfaccia (`UiTheme` + pannelli `src/ui/`)

1. **Tema medievale condiviso (`src/ui/ui_theme.gd`)**:
   * Palette coerente con i materiali del villaggio: fondo legno di noce scuro
     (`Color(0.08, 0.065, 0.055, 0.90)`), bordi in ottone antico (`BORDER_BRASS`), titoli oro
     pergamena (`TEXT_GOLD`), testo avorio caldo (`TEXT_PARCHMENT`) e colori semantici per stati
     positivi (`TEXT_GOOD`), avvisi (`TEXT_WARN`) e criticità (`TEXT_CRITICAL`).
   * Tipografia basata su `SystemFont` + `FontVariation` (font con grazie per i titoli, sans
     umanista ad alta leggibilità per tabelle e registri), senza introdurre binari nel repository.
   * Stili completi per `Button`, `OptionButton`, `PopupMenu`, `TooltipPanel` e `HSeparator`.
2. **`WorldHud` (`src/ui/world_hud.gd`, `src/ui/scenes/world_hud.tscn`)**:
   * Aggiunta la riga di stato con `PhaseBadge` (fase del giorno) e `SpeedBadge` (`▶ x1`,
     `▶▶ x3`, `▶▶▶ x10` oppure `⏸ IN PAUSA` evidenziato in ambra).
   * Aggiunto un discreto mirino centrale (`Crosshair`, `❖`) visibile quando il mouse è catturato
     per facilitare la selezione degli abitanti in prima persona.
   * Il banner inferiore dei comandi (`Hint`) è ora racchiuson in uno `StyleBoxFlat` leggibile su
     qualunque sfondo.
3. **`EconomyPanel` (`src/ui/economy_panel.gd`, `src/ui/scenes/economy_panel.tscn`)**:
   * Larghezza compattata (`356 px`, allineata a `WorldHud`), testi portati a dimensioni
     leggibili (`12–14 px`), marcatori visivi per risorsa (`◆ Cibo`, `◆ Legno`, `◆ Pietra`,
     `◈ Moneta`) e tooltip esplicativi con prezzo base e soglia di carenza.
   * Colorazione dinamica: le scorte sotto soglia diventano ambra (o cremisi a `0`), i flussi
     `+prod / -cons` riflettono il saldo netto e `ShortagesLabel` è verde salvia quando non vi
     sono carenze attive.
4. **`NpcPanel` (`src/ui/npc_panel.gd`, `src/ui/scenes/npc_panel.tscn`)**:
   * **Modalità compatta quando nessun abitante è selezionato**: le sezioni di dettaglio vuote
     vengono nascoste finché non si seleziona un abitante, liberando la visuale destra della
     scena 3D; selezionando la prima voce dell'elenco è ora possibile chiudere la scheda.
   * **Scheda personaggio arricchita**: colore del mestiere su `ProfessionLabel`, umore e fascia
     oraria del turno, riga `TraitsLabel` con i quattro tratti della personalità, colore dinamico
     di `ActivityLabel` e delle barre `EnergyBar`, `HungerBar`, `WellbeingBar` con tooltip sulle
     soglie reali della simulazione.
5. **`SaveLoadPanel` e `DiagnosticsHud`**:
   * `SaveLoadPanel` applica `UiTheme`, racchiude le voci della cronaca in un riquadro interno
     con bordo sinistro colorato per categoria e dota ogni pulsante e filtro di tooltip.
   * `DiagnosticsHud` (`F1`) è stato spostato in alto al centro (`anchor_left = 0.5`) e dotato di
     `StyleBoxFlat`, eliminando la sovrapposizione con `WorldHud` ed `EconomyPanel`.
