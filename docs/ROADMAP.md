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

## Fase 3 — Relazioni e memoria (`src/social`) 🔶 (prima versione in `0.5.0-social`)

**Obiettivo**: le persone si conoscono, si fidano, litigano, e lo ricordano.

Consegnato in `0.5.0-social` (il modulo si chiama `src/social/`, non `src/relationships/`: contiene
relazioni, interazioni e memoria, che sono un solo comportamento):

* **Grafo di relazioni con un solo proprietario** (`RelationshipGraph`), chiave canonica per coppia
  non ordinata, rifiuto esplicito di duplicati e di auto-relazioni, pulizia dei riferimenti a NPC
  inesistenti al caricamento. Il vecchio dizionario simmetrico dentro `NpcRecord` è stato rimosso:
  due copie dello stesso legame possono divergere.
* **Quattro attributi documentati** in `0..100`: familiarità e tensione condivise, fiducia e
  affinità direzionali (`trust_a/trust_b`, `affinity_a/affinity_b`), con guadagni a rendimenti
  decrescenti e un tetto giornaliero condiviso che impedisce la crescita illimitata.
* **Cinque interazioni a regole** (saluto, conversazione, cooperazione, aiuto, disaccordo) scelte
  da contesto, prossimità, attività, relazioni esistenti e scorte del villaggio. Nessun evento
  casuale privo di significato: se le condizioni non ci sono, non succede niente.
* **Registro eventi oggettivo** (`SocialEvent`) separato dalla **memoria soggettiva** (`NpcMemory`,
  con ruolo, fonte e confidenza pronte per una prospettiva incompleta), con capacità configurabile,
  regola di ritenzione per importanza e rilevanza, e nessuna eliminazione silenziosa dei ricordi
  importanti.
* **Una conseguenza verificabile**: la disponibilità a cooperare dipende dai ricordi (aiuto
  ricevuto, litigio recente), non dal testo.
* **Interfaccia sobria**: tre relazioni, tre ricordi e il motivo documentato dell'ultimo
  cambiamento nel pannello già esistente; nessun pannello nuovo.
* **Serializzazione pronta**: `SocialSystem.to_dict()` / `from_dict()` seguono la stessa
  convenzione degli altri sistemi, perché la Fase 6 li raccolga invece di duplicarli.

Ancora da fare in questa fase:

* Tipi di relazione espliciti (conoscente, amico, rivale, familiare) oggi derivati dai numeri.
* Formazione di famiglie e piccoli gruppi per prossimità e interazioni ripetute.
* Ricordi non sociali (luoghi, mestiere appreso) e memoria di lungo periodo consolidata.

**Criteri di accettazione**: relazioni che evolvono in modo deterministico su 30 giorni ✅ (40
giorni simulati in `TestSocialSimulation`, esito ripetibile); test che verificano coerenza del
grafo e assenza di relazioni orfane ✅ (anche dopo il caricamento di uno snapshot in un mondo più
piccolo); memoria entro i limiti configurati ✅; nessuna crescita illimitata di fiducia ✅.

## Fase 4 — Società e politica (`src/society` o `src/simulation/systems`)

**Obiettivo**: emergono strutture sopra il singolo.

* Comunità e insediamenti come entità con confini e risorse condivise.
* Leadership, decisioni collettive, regole semplici (tasse, divieti, razionamento).
* Fazioni e conflitti non violenti prima, conflitti aperti poi.

**Criteri di accettazione**: una decisione collettiva cambia misurabilmente la simulazione
(consumi, prezzi, spostamenti) e il cambiamento è osservabile nei test.

## Fase 5 — Cronache (`src/history`) ✅ (prima versione in `0.6.0-persistence`)

**Obiettivo**: il mondo ricorda e racconta.

* Registro di eventi importanti con data simulata, attori e conseguenze ✅
  (`ChronicleBook` + `ChronicleEntry` nel modulo `src/history/`).
* Consultazione in gioco (pannello accessibile con `C`) e generazione di testo deterministico
  da template ✅.
* Collegamento con i ricordi individuali della Fase 3 ✅ (`ChronicleWatcher` promuove i
  `SocialEvent` più importanti nella cronaca usando il contatore di ID come riferimento, così
  il catch-up a lotti non perde eventi intermedi).

**Limiti attuali**: non esiste ancora una narrazione stagionale o eventi narrativi casuali; le
voci sono registrate da regole numeriche (soglie di scorte, aiuti, progetti completati,
cambi di giorno, eventi di sistema).

**Criteri di accettazione**: dopo la simulazione esiste una cronaca leggibile e riproducibile
con voci reali della simulazione (produzione, carenze, aiuti, progetti), filtrabile per
categoria e giorno ✅.

## Fase 6 — Persistenza (`src/persistence`) ✅ (prima versione in `0.6.0-persistence`)

**Obiettivo**: salvare e ricaricare l'intera civiltà.

* Formato testo leggibile su `user://` (JSON), con `save_format_version` ✅. Nessun checksum
  in questa versione (il formato JSON + scrittura atomica sono già la salvaguardia principale;
  un checksum verrà aggiunto quando il formato si stabilizza).
* Salvataggio di clock, loop, tutti i sistemi (abitanti, economia, sociale), cronaca e watcher
  in un unico file ✅.
* Scrittura atomica (file `.tmp` + rename) e backup `.bak` del save precedente ✅.
* Salvataggio automatico ogni 12 ore simulate e all'uscita (notifica di chiusura della finestra)
  ✅; salvataggio/caricamento manuale dal pannello con conferma di sovrascrittura ✅.
* Gestione di file mancanti, corrotti e versioni non supportate con messaggi in italiano ✅.
* Test di round trip per tutti i sistemi e test di gestione dei file corrotti/versioni non
  supportate scritti ✅ (vedi `TestSaveManager`).

**Limiti attuali**: niente slot multipli in questa versione (un solo file di save); la versione
schema è `1` e non c'è ancora un migratore per le versioni future (il caricatore rifiuta le
versioni non corrispondenti invece di interpretarle).

**Criteri di accettazione**: salvare, uscire, rientrare e continuare senza differenze rispetto a
una sessione unica (verificato nei test di round trip; la verifica end-to-end su Godot è
documentata in `docs/ARCHITECTURE.md` come non eseguita in questo ambiente perché il motore non
è installato).

## Fase 7 — Tempo trascorso in assenza del giocatore ✅ (prima versione in `0.6.0-persistence`)

**Obiettivo**: il mondo non si ferma quando il giocatore non c'è.

* Calcolo del tempo trascorso dal timestamp reale salvato e `SimulationLoop.run_ticks()` sul
  backlog, con tetto massimo configurabile (default 10 giorni simulati) ✅.
* Avanzamento a batch (1 ora simulata per batch) con osservazione della cronaca ad ogni passo,
  non un ciclo unico da migliaia di tick in un frame ✅.
* Protezioni da orologio di sistema (timestamp futuro, riavvio rapido, chiamate ripetute) ✅.
* Voce in cronaca che riassume l'esito (compreso il caso di tetto raggiunto) ✅.

**Limiti attuali**: non c'è ancora una sintesi testuale separata oltre alla voce di cronaca
(nessun popup "bentornato" dedicato); l'avanzamento usa ancora la logica di `on_tick` per
ogni passo, quindi non è un modello aggregato: con il tetto di 10 giorni il tempo di
caricamento resta comunque entro ~2 secondi. Per periodi offline più lunghi servirà un modello
aggregato, documentato come lavoro futuro in `docs/ARCHITECTURE.md`.

**Criteri di accettazione**: rientrare dopo un periodo di assenza produce un mondo plausibile
e una voce in cronaca che lo descrive (i test verificano che le risorse restino non negative
dopo 5 giorni simulati di catch-up e che il tetto venga applicato correttamente).

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
* Audio ambientale e di interfaccia. Illuminazione diurna curata **fatta**
  ([`docs/LIGHTING.md`](LIGHTING.md)); restano meteo, stelle e GI su preset alti.
* UI reale (pannelli di NPC, economia, cronache) al posto del pannello diagnostico.
* Preset di export Windows, icone, pass di prestazioni su hardware di riferimento.

---

## Ordine consigliato e dipendenze

```
Fase 0 ──▶ Fase 1 ──▶ Fase 2 ──▶ Fase 4 ──▶ Fase 8 ──▶ Fase 9
             │           │
             └──▶ Fase 3 ┴──▶ Fase 5 ──▶ Fase 6 ──▶ Fase 7
                                         (oggi)
```

Le Fasi 2 e 3 hanno prodotto un'economia e un sistema sociale serializzabili; le Fasi 5 (cronache),
6 (persistenza) e 7 (avanzamento offline) sono state consegnate in questa iterazione come
prima versione `0.6.0-persistence`, rimanendo volutamente semplici (un solo slot di save,
catch-up con i tick normali entro un tetto, nessun modello aggregato). Le successive iterazioni
potranno approfondirle senza rompere il formato o aggiungere complessità non verificabile.

## Definizione di "fatto" per ogni fase

1. Il gioco si avvia su Windows con Godot 4 stabile.
2. `bash tools/run_checks.sh` è verde e la suite headless è stata eseguita (non solo scritta).
3. I nuovi sistemi hanno test deterministici e nessuna dipendenza da nodi o scene.
4. `docs/ARCHITECTURE.md` descrive le scelte nuove; questo file è aggiornato.
5. Nessuna credenziale, nessun asset non licenziato, nessuna dipendenza non dichiarata.
