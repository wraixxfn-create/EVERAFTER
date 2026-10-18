# EVERAFTER — Visual Polish 07: rifinitura architettonica degli edifici

Intervento grafico sugli edifici procedurali già presenti. Posizioni, ID delle placement,
ruoli, gruppi della scena, collegamenti con gli NPC e palette condivisa sono rimasti invariati;
non sono stati aggiunti edifici, aree o sistemi di gioco.

## Audit e difetti rilevati

- Le facciate triangolari delle case e della locanda erano colorate come il tetto: il prospetto
  leggeva come un solido di tegole, non come intonaco sotto una copertura. La sala aveva lo
  stesso problema in pietra.
- Nelle case basse, una finestra frontale poteva cadere sull'asse della porta; cornici,
  persiane e fioriere invadevano il vano. La trave inferiore attraversava inoltre la soglia.
- Le travi diagonali laterali erano ruotate sull'asse Z: sporgevano dalla parete invece di
  seguire il piano della facciata.
- Le tettoie della locanda, delle case lunghe e dei banchi usavano una rotazione di imbardata
  dove serviva una pendenza: erano quasi piatte e ruotate nel piano.
- Il pozzo era chiuso da un cilindro pieno e da una corona circolare piena: la mesh dell'acqua
  restava nascosta sotto la pietra. I montanti del tetto erano inoltre dentro il bordo del
  bacino e non arrivavano alla linea di colmo.
- Il corpo della torre civica arrivava a quota 9, mentre la copertura iniziava a quota 8,4;
  parete, coronamento e tetto si attraversavano. Anche il collider della casa lunga non
  seguiva il suo ingombro reale.

## Interventi

### Facciate e struttura

- `MeshBaker.add_prism()` può ora separare la faccia del timpano dalla superficie delle falde.
  Il timpano delle case e della locanda usa l'intonaco già in palette, quello della sala usa la
  pietra; il bordo del tetto resta visibile come piccolo sporto. Le superfici continuano a essere
  aggregate per materiale.
- Il telaio ligneo mantiene montanti d'angolo e correnti superiori/inferiori; il corrente basso
  frontale è interrotto attorno alla porta. Le saette sono state orientate nel piano delle
  pareti laterali e spostate fuori dalla finestra. La casa a due piani riceve un solo marcapiano
  continuo, proporzionato alla facciata.
- Una posizione condivisa per finestra e fioriera tiene liberi stipiti, persiane e ingresso
  nelle facciate basse. Le altre aperture mantengono la distribuzione esistente.
- Comignoli con cappello in pietra e imbocco scuro del fumo; tettoie della locanda, della casa
  lunga e dei banchi con pendenza reale, senza cambiare gli ingombri principali.

### Fondamenta, ingressi e collocazione

- I vecchi blocchi isolati davanti alle porte sono stati sostituiti con due riser bassi, allineati
  alla sommità del plinto: casa, locanda e sala del consiglio. Sono geometria visiva senza
  collider e non restringono il corridoio d'ingresso né i percorsi.
- I pilastri della porta della sala sono stati allontanati quel tanto che basta a non coprire i
  bordi del portone.
- Il corpo della torre termina alla base del coronamento (8 m); tetto, corsi di pietra e
  collider sono stati riallineati a quella quota.
- I collider delle case ora seguono larghezza, profondità e altezza del rispettivo modello;
  quello del pozzo copre anche gli spigoli del nuovo bordo in pietra.

### Pozzo e banchi

- Il pozzo conserva il cilindro pieno solo come piede basso, sotto il livello dell'acqua. La
  sommità è ora una corona di blocchi separati, con apertura centrale leggibile; i due montanti
  poggiano a terra, fuori dal bordo del bacino, e raggiungono il colmo. Trave del verricello e
  tetto restano al loro posto relativo.
- La copertura in stoffa dei banchi è inclinata verso il bordo frontale; il bordo pendente
  rimane allineato ai montanti.

## Coerenza e costo

- Nessuna placement spostata; ID, nomi dei nodi di struttura e gerarchia `Village/Structures`
  invariati. Nessun nuovo `StaticBody3D` o materiale.
- Gradini, saette, coperture e pietre del pozzo vengono aggiunti alle mesh già aggregate per
  materiale; non creano un nodo o una draw call per singolo dettaglio.
- Nessun asset esterno, texture o licenza introdotti. Nessuna modifica a economia, NPC,
  salvataggi, layout, strade o aree di gioco.

## Verifiche e limiti residui

- Aggiunta `tests/unit/test_building_architecture.gd`: verifica i materiali e il winding dei
  timpani separati, le dimensioni dei collider delle case, la posizione sicura delle finestre e
  che nessuna superficie in pietra chiuda l'apertura centrale del pozzo.
- Eseguiti `python3 tools/check_project.py`, `gdparse` su tutti gli 85 script e `gdlint` sui
  file modificati: **OK**.
- `tools/run_checks.sh` rileva inoltre 12 problemi di stile in file non modificati (autoload,
  cronaca, persistenza, terreno, `village_builder` e un test della cronaca); i file toccati da
  questa fase non aggiungono errori di lint.
- La suite Godot headless/unità e quella d'integrazione **non sono state eseguite**: in questo
  ambiente non è disponibile un eseguibile Godot. Non è stato possibile ispezionare screenshot
  o camminare nel villaggio a distanza di gioco; la verifica visiva in editor resta da fare.
- Gli edifici non hanno interni: i portoni restano superfici chiuse e i collider principali
  continuano a bloccare il volume dell'edificio. Non è stato aperto un passaggio che farebbe
  entrare il giocatore in una struttura senza interno o navigazione. I gradini decorativi non
  introducono collisioni.

*EVERAFTER · Visual Polish 07 · 2026-10-18*
