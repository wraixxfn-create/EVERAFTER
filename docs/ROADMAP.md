# EVERAFTER — Roadmap

Fasi di sviluppo del progetto. Ogni fase è **autoconsistente**: alla fine di ogni fase il gioco si
avvia, i test headless passano e la documentazione è aggiornata. Nessuna fase lascia il progetto in
uno stato "metà simulazione, metà no".

Regole valide per tutte le fasi:

* ogni sistema nuovo arriva con test headless in `tests/unit/`;
* ogni sistema rispetta le regole di determinismo e di dipendenza di `docs/ARCHITECTURE.md`;
* nessuna API pubblica senza un utilizzatore reale;
* `bash tools/run_checks.sh` deve restare verde, e gli eventuali controlli saltati vanno dichiarati.

---

## Fase 0 — Fondazioni tecniche ✅ (completata, in revisione)

**Obiettivo**: base 3D funzionante, pulita e verificabile, con il tempo simulato separato dal
rendering.

Consegnato: progetto Godot 4, scena principale 3D, terreno procedurale con collisione, villaggio
provvisorio, esploratore in prima persona, pannello diagnostico, orologio deterministico, loop a
passo fisso, primo sistema (`day_cycle`), suite headless, verifiche statiche, documentazione.

Da verificare su una macchina con Godot installato (non eseguibile nell'ambiente di stesura):
esecuzione della suite headless, avvio del gioco, resa 3D, sensazione dei comandi.

---

## Fase 1 — NPC minimi (`src/npcs`) ✅ (implementata, in verifica)

**Obiettivo**: il mondo è abitato da persone che esistono anche quando nessuno le guarda.

Consegnato:

* `NpcRecord` (dati puri: id, nome, età, casa, lavoro, bisogni, obiettivo, attività, relazioni e
  ricordi iniziali) — nessun nodo.
* Bisogni primari (energia, fame, benessere) che evolvono a ogni minuto simulato, con soglie
  esplicite per mangiare, riposare e andare a dormire.
* Routine giornaliera a regole: lavoro nella propria fascia, sonno tra le 22:00 e le 06:00, pasti
  in locanda o al mercato se aperti (altrimenti dispensa di casa), riposo, tempo libero sociale.
* Spostamento continuo su una rete di waypoint costruita sulle strade reali del villaggio, con
  ostacoli verificati; nessun teletrasporto; luoghi irraggiungibili esclusi e stato `BLOCKED`
  con recupero.
* Integrazione con `SimulationLoop`: la simulazione avanza per tick, non per frame, e
  `Game.advance_simulation(n)` permette di far passare tempo senza disegnare nulla.
* Presentazione separata: capsule con nome solo entro `npc_view_distance`, pannello di selezione
  con nome, età, professione, attività, obiettivo, barre dei bisogni e riepilogo.
* Popolazione configurabile in un unico punto: `GameConfig.npc_population_size` (0..16, default
  10). Il roster contiene 16 abitanti fissi; `NpcRoster.build(n)` restituisce i primi `n`.

**Criteri di accettazione**: la popolazione configurata (default 10) viene simulata per un giorno
intero in headless, senza nodi, con esito deterministico a parità di stato iniziale; il giocatore li
vede muoversi nel villaggio; il pannello mostra l'abitante selezionato e continua a mostrarne i dati
anche quando è fuori portata visiva.

**Rischi residui**: il movimento non usa la navmesh di Godot ma una rete di waypoint costruita a
mano sulle strade; è verificabile e deterministica, ma non conosce il traffico o gli altri NPC.
Il costo per tick è lineare nella popolazione (10 record, nessuna allocazione di nodi) e va
misurato quando la popolazione crescerà.

## Fase 2 — Economia locale (`src/economy`) ✅ (implementata in `0.4.0-economy`)

**Obiettivo**: produrre, consumare, scambiare; la scarsità ha conseguenze sui bisogni degli
abitanti.

Consegnato in `0.4.0-economy`:

* **Risorse tipizzate intere non negative** (`ResourceType`: `food`, `wood`, `stone`, `coin`) con
  prezzi base documentati (`2, 3, 4, 1`) e soglie di carenza (`8, 4, 4, 6`).
* **Inventari atomici e convalidati** (`ResourceInventory`): magazzino collettivo del villaggio
  (`village`), sacche individuali degli abitanti (`npc_001` … `npc_016`) ed emporio finito del
  mercato (`market`). Tutte le operazioni non valide vengono rifiutate senza modifiche parziali né
  valori negativi.
* **Produzione legata al lavoro effettivo** (`EconomyRules`, `EconomySystem`):
  * *Agricoltore / raccoglitrice / pescatore / panettiera / locandiera* producono `Cibo`;
  * *Boscaiolo* produce `Legno`;
  * *Cavatore (addetto all'estrazione)* produce `Pietra`;
  * *Commerciante* facilita gli scambi tra sacche, magazzino ed emporio a prezzi base fissi senza
    creare ricchezza dal nulla.
  Se un lavoratore dorme, cammina, è esausto o ha la postazione non pronta, non produce.
* **Consumo alimentare e carenze**: ogni pasto consuma `1 Cibo`; quando il cibo scarseggia, i pasti
  non soddisfatti riducono il benessere e lasciano la fame alta (`>= 76`), senza mortalità né
  carestie irreversibili.
* **Progetti comunitari**: 4 progetti del villaggio che impiegano `Legno`, `Pietra` e `Moneta` per
  aumentare la resa produttiva o il benessere.
* **Pannello economico (`EconomyPanel`)**: mostra in tempo reale scorte, produzione/consumo del
  periodo, carenze, progetti e transazioni recenti leggendo direttamente `EconomySystem`.

**Funzionalità economiche future (non ancora implementate)**: prezzi dinamici guidati da domanda e
offerta, catene produttive multi-stadio, usura degli utensili, credito/debito e commercio tra più
insediamenti.

**Criteri di accettazione verificati**: simulazione multi-giorno deterministica e ripetibile in
headless, conservazione delle risorse verificata dai test (`TestEconomyInventory` e
`TestEconomySimulation`), assenza di valori negativi e corrispondenza esatta tra UI e stato.

## Fase 3 — Relazioni (`src/relationships`)

**Obiettivo**: le persone si conoscono, si fidano, litigano.

* Grafo di relazioni con tipo e intensità (conoscente, amico, rivale, familiare).
* Memoria individuale: gli eventi recenti influenzano la relazione.
* Formazione di famiglie e di piccoli gruppi per prossimità e interazioni ripetute.

**Criteri di accettazione**: relazioni che evolvono in modo deterministico su 30 giorni; test che
verificano simmetria/coerenza del grafo e assenza di relazioni orfane.

## Fase 4 — Società e politica (`src/society` o `src/simulation/systems`)

**Obiettivo**: emergono strutture sopra il singolo.

* Comunità e insediamenti come entità con confini e risorse condivise.
* Leadership, decisioni collettive, regole semplici (tasse, divieti, razionamento).
* Fazioni e conflitti non violenti prima, conflitti aperti poi.

**Criteri di accettazione**: una decisione collettiva cambia misurabilmente la simulazione
(consumi, prezzi, spostamenti) e il cambiamento è osservabile nei test.

## Fase 5 — Cronache (`src/history`)

**Obiettivo**: il mondo ricorda e racconta.

* Registro di eventi importanti con data simulata, attori e conseguenze.
* Consultazione in gioco (pannello o libro) e generazione di testo **deterministico** da template.
* Collegamento con i ricordi individuali della Fase 3.

**Criteri di accettazione**: dopo 30 giorni simulati esiste una cronaca leggibile e riproducibile,
identica a parità di seme.

## Fase 6 — Persistenza (`src/persistence`)

**Obiettivo**: salvare e ricaricare l'intera civiltà.

* Formato testo leggibile su `user://`, con `save_format_version`, checksum e campi opzionali.
* Salvataggio di clock, loop, tutti i sistemi, mondo e (se esiste) stato del giocatore.
* Slot multipli, salvataggio automatico periodico e all'uscita.
* Test di round trip per ogni sistema e test di caricamento di un salvataggio di versione precedente.

**Criteri di accettazione**: salvare, uscire, rientrare e continuare senza differenze rispetto a una
sessione unica (verificato confrontando lo stato dopo N tick).

## Fase 7 — Tempo trascorso in assenza del giocatore

**Obiettivo**: il mondo non si ferma quando il giocatore non c'è.

* All'avvio, calcolo del tempo trascorso e `SimulationLoop.run_ticks()` sul backlog, con un tetto
  massimo e una sintesi degli eventi invece di una simulazione completa tick per tick.
* "Riassunto del mondo" mostrato al rientro, coerente con la cronaca della Fase 5.

**Criteri di accettazione**: rientrare dopo 10 giorni reali produce un mondo plausibile in meno di
due secondi, con esito riproducibile.

## Fase 8 — IA generativa opzionale

**Obiettivo**: dialoghi e decisioni più ricche, **senza** che il gioco dipenda da servizi esterni.

* Interfaccia locale `DialogueProvider` con due implementazioni: template deterministici (default,
  offline) e provider esterno configurabile dall'utente (chiavi proprie, mai nel repository).
* Cache su disco delle risposte, fallback automatico e indicazione chiara in UI quando il provider
  esterno non è disponibile.
* Nessuna chiave segreta nel repository, nessuna chiamata di rete nel percorso di gioco predefinito.

**Criteri di accettazione**: con la rete disattivata il gioco è completo e identico a prima; con un
provider configurato, i dialoghi migliorano senza bloccare la simulazione.

## Fase 9 — Contenuti, arte, audio e rifinitura

**Obiettivo**: da prototipo a gioco presentabile.

* Asset 3D stilizzati al posto delle primitive, con LOD e atlanti di materiali.
* Audio ambientale e di interfaccia, illuminazione curata, cielo e meteo.
* UI reale (pannelli di NPC, economia, cronache) al posto del pannello diagnostico.
* Preset di export Windows, icone, pass di prestazioni su hardware di riferimento.

---

## Ordine consigliato e dipendenze

```
Fase 0 ──▶ Fase 1 ──▶ Fase 2 ──▶ Fase 4
             │           │
             └──▶ Fase 3 ┴──▶ Fase 5 ──▶ Fase 6 ──▶ Fase 7 ──▶ Fase 8 ──▶ Fase 9
```

Le Fasi 2 e 3 possono procedere in parallelo dopo la Fase 1. La Fase 6 (persistenza) va anticipata
se la simulazione diventa abbastanza grande da non poter essere ricostruita a ogni avvio.

## Definizione di "fatto" per ogni fase

1. Il gioco si avvia su Windows con Godot 4 stabile.
2. `bash tools/run_checks.sh` è verde e la suite headless è stata eseguita (non solo scritta).
3. I nuovi sistemi hanno test deterministici e nessuna dipendenza da nodi o scene.
4. `docs/ARCHITECTURE.md` descrive le scelte nuove; questo file è aggiornato.
5. Nessuna credenziale, nessun asset non licenziato, nessuna dipendenza non dichiarata.
