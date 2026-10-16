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

## Fase 1 — NPC minimi (`src/npcs`)

**Obiettivo**: il mondo è abitato da persone che esistono anche quando nessuno le guarda.

* `NpcRecord` (dati puri: id, nome, età, casa, lavoro, stato corrente) — nessun nodo.
* Bisogni primari (riposo, cibo, socialità) come valori che crescono con i tick.
* Una routine giornaliera semplice: dormire, lavorare, mangiare, socializzare, con fasce orarie.
* Spostamento grezzo: posizione logica sul terreno + cammino verso un obiettivo; la rappresentazione
  visiva è un segnaposto (capsula o `MultiMesh`).
* Integrazione con l'orologio: i comportamenti cambiano con l'ora del giorno.

**Criteri di accettazione**: 20 NPC simulati per un giorno intero in headless, senza nodi, con esito
deterministico a parità di seme; il giocatore li vede muoversi nel villaggio; il pannello mostra il
numero di abitanti.

**Rischi**: costo per tick se lo stato è frammentato in oggetti; si mitigano tenendo i dati in array
paralleli o in un unico `Dictionary` per NPC e misurando il tempo di tick.

## Fase 2 — Economia minima (`src/economy`)

**Obiettivo**: produrre, consumare, scambiare; la scarsità ha conseguenze.

* Risorse tipizzate (cibo, legname, pietra, manufatti) e inventari per NPC e per magazzini.
* Produzione legata al lavoro svolto nella routine della Fase 1.
* Scambio diretto e prezzi derivati da domanda/offerta locale (nessun RNG nei prezzi).
* Conseguenze visibili: carestia, scorte esaurite, NPC che cambiano mestiere.

**Criteri di accettazione**: 30 giorni simulati in headless riproducibili, con bilancio delle
risorse verificato da un test (nulla creato o distrutto senza una causale registrata).

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
