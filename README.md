# EVERAFTER

Simulazione 3D di una civiltà persistente e autonoma, realizzata con **Godot 4** e **GDScript tipizzato**.

Il mondo è abitato da personaggi con identità, bisogni, professioni, obiettivi, relazioni e memoria.
Gli abitanti agiranno autonomamente, la società evolverà e gli eventi lasceranno conseguenze nel tempo.
Il gioco deve funzionare **offline**, senza servizi a pagamento e senza server obbligatori.

Questo repository contiene oggi la **fase Persistenza, cronache e avanzamento offline
(`0.6.0-persistence`)**, la prima versione verificabile in cui il mondo sopravvive alla chiusura
del gioco:

* villaggio 3D generato a codice, camminabile in prima persona, con terreno procedurale e ciclo
  giorno/notte;
* **10 abitanti** (numero configurabile) con nome, mestiere, bisogni, casa, posto di lavoro,
  routine giornaliera, **ciclo economico delle risorse** (`Cibo`, `Legno`, `Pietra`, `Moneta`),
  relazioni personali, cinque tipi di interazione sociale e memoria individuale limitata;
* **salvataggio versionato in JSON** su `user://`, scrittura atomica con backup, caricamento
  robusto contro file mancanti, corrotti o di versione non supportata;
* **cronaca del villaggio** (`ChronicleBook`) con voci strutturate, filtri per categoria e
  giorno, e politica di conservazione per importanza;
* **avanzamento offline** basato sul tempo reale trascorso, con limite configurabile,
  avanzamento a intervalli, protezione da orologio di sistema spostato e voce in cronaca.

> Stato onesto del progetto: **questa è la prima versione persistente e verificabile sulla quale
> costruiremo le fasi successive** (società e politica, dialoghi, contenuti). Esiste un
> salvataggio funzionante che conserva abitanti, risorse, relazioni, memoria e cronaca; non
> esiste ancora una simulazione aggregata per i periodi offline molto lunghi (oggi il catch-up
> avanza i tick della simulazione uno a uno, entro un tetto di sicurezza) e non c'è ancora una
> simulazione completa di civiltà con politica, fazioni, eventi narrativi. **Nessun modello
> linguistico e nessun servizio online**; il progetto funziona interamente offline. Prossime
> tappe in [`docs/ROADMAP.md`](docs/ROADMAP.md).

---

## 1. Requisiti

| Voce | Valore |
| --- | --- |
| Motore | **Godot 4.5 o superiore, build stabile** (verificata qui: `4.7.2-stable`) |
| Sistema operativo | Windows 10/11 64-bit (target iniziale del progetto) |
| GPU | Classe NVIDIA GTX 1060 o superiore, con driver Vulkan aggiornati |
| RAM | 16 GB consigliati |
| Dipendenze esterne | Nessuna. Niente plugin, niente pacchetti, niente rete a runtime, nessun asset binario |
| Strumenti di sviluppo (opzionali) | Python 3 e `gdtoolkit` per i controlli statici |

Il progetto è **solo testo**: script, scene, una risorsa di configurazione, documentazione. Ogni
mesh, materiale e colore è generato dal codice. Una volta clonato, funziona senza connessione.

## 2. Aprire ed eseguire il progetto su Windows

1. Scarica Godot 4 stabile da <https://godotengine.org/download/windows/>
   (file `Godot_v4.x-stable_win64.exe.zip`; la versione `_console` è comoda per vedere i log).
2. Estrai l'archivio dove preferisci. Non serve installare nulla.
3. Avvia l'editor, premi **Import**, seleziona il file `project.godot` di questa repository
   e premi **Import & Edit**.
4. Al primo avvio Godot genera la cartella `.godot/` (cache locale, ignorata da git). **È un passo
   obbligatorio**: contiene anche `global_script_class_cache.cfg`, senza il quale i `class_name`
   non vengono risolti e gli script non compilano.
5. Premi **F5** (oppure ▶ in alto a destra): il progetto parte dalla scena principale
   `res://src/world/scenes/main_world.tscn` e il giocatore compare sulla strada sud-ovest,
   rivolto verso la piazza.

### Da riga di comando (senza aprire l'editor)

Apri un terminale nella cartella del progetto. La prima volta genera la cache:

```bat
Godot_v4.7.2-stable_win64_console.exe --headless --path . --import
```

Poi:

```bat
:: esegue il gioco
Godot_v4.7.2-stable_win64.exe --path .

:: finestra più piccola, utile per i test rapidi
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900

:: suite di test headless di unità (nessuna finestra, nessuna GPU)
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd

:: suite di integrazione: avvia davvero la scena e interroga la fisica
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_world_tests.gd

:: interrompe il gioco dopo N frame (smoke test senza giocatore)
Godot_v4.7.2-stable_win64_console.exe --path . --quit-after 30
```

Su Windows l'output su console è visibile solo con l'eseguibile `_console.exe`.

## 3. Controlli

| Input | Azione |
| --- | --- |
| `W` `A` `S` `D` o frecce | Muoversi |
| `Shift` | Correre (5,6 m/s invece di 3,4 m/s di passo) |
| `Spazio` | Saltare (≈0,86 m: un gradino o un argine, non uno steccato) |
| Mouse | Guardarsi attorno |
| `Esc` | **Libera il mouse** (per raggiungere la finestra, l'editor, un secondo monitor) |
| Clic sinistro **oppure** `F` | **Riprende il controllo del mouse** |
| `P` | Pausa / ripresa della simulazione |
| `+` / `-` | Velocità della simulazione (x1, x3, x10) |
| `F1` | Mostra / nasconde il pannello diagnostico (nascosto all'avvio) |
| `C` | Apre il pannello **Cronache e salvataggio** (salva, carica, consulta la cronaca) |
| **Clic sinistro** (mouse catturato) | Seleziona l'abitante sotto il mirino e apre la sua scheda |
| **Clic sinistro** (mouse libero) | Seleziona l'abitante sotto il puntatore e cattura di nuovo il mouse |
| **Elenco "Abitanti"** | Sceglie un abitante dal pannello, anche se è lontano e non è disegnato |

Quando il mouse è libero, in basso allo schermo compare la scritta
*"Clic sinistro o F per riprendere il controllo"*: nessuno deve dover indovinare come si torna a
giocare. Perdendo il fuoco della finestra il mouse viene liberato automaticamente.

Tutti gli input sono mappati come **azioni** in `project.godot` (sezione `[input]`), quindi sono
rimappabili dall'editor senza toccare il codice.

### Salvataggio, caricamento e cronache

* Il gioco salva automaticamente ogni **12 ore simulate** e quando la finestra viene chiusa.
* Il pannello aperto con `C` permette di salvare e caricare manualmente. Prima di sovrascrivere
  un salvataggio esistente viene chiesta conferma.
* Il formato è **JSON leggibile** (`user://everafter_save.json`). Su Windows `user://` corrisponde
  a `%APPDATA%/Godot/app_userdata/EVERAFTER/` (o alla cartella dell'exe in caso di export
  self-contained).
* Quando si avvia il gioco e un salvataggio è presente, il mondo viene ricaricato al punto in
  cui era stato lasciato. Se è passato tempo reale dall'ultimo salvataggio, la simulazione
  avanza in modo controllato (default: massimo **10 giorni simulati** di catch-up per avvio) e
  l'esito viene annotato nella cronaca.
* La cronaca registra carestie, riprese dell'economia, aiuti tra abitanti, progetti comunitari
  completati, traguardi del giorno ed eventi di sistema. Le voci sotto l'importanza minima
  non sono conservate; quelle più importanti sono protette dalla cancellazione.
* I file corrotti o di versione non supportata vengono rifiutati con un messaggio invece di
  corrompere lo stato del mondo; il file `.bak` (`everafter_save.json.bak`) è una copia del
  salvataggio precedente come rete di sicurezza aggiuntiva.

## 4. Che cosa si vede avviando il gioco

Un villaggio di confine, al mattino del giorno 1 (ore 07:00 simulate):

* **Terreno** 159 × 159 unità (160 × 160 celle) con colline dolci generate da value noise
  deterministico. Le strade e le aree edificate perdono solo le ottave di dettaglio, non le
  colline: i percorsi sono camminabili senza che il paesaggio diventi una trincea piatta.
* **Piazza del Pozzo** lastricata al centro, con pozzo in pietra, tettoia e secchio, e una
  coroncina di blocchi di pietra che ne marca il bordo. Panchine verso il pozzo e fioriere
  negli angoli aperti, senza mai invadere le bocche delle strade.
* **13 case** con sagome diverse: cottage a un piano, case a due piani con tetto ripido, case
  lunghe con portico; intonaco chiaro o ocra, travi a vista, plinti in pietra, comignoli,
  finestre che si illuminano di notte, fioriere ai davanzali e piccoli cortili con casse,
  barili e cataste di legna sui fianchi (mai davanti alle porte).
* **Locanda del Cervo Bianco**: due piani, ala a L, portico su colonne, insegna appesa.
* **Sala del Consiglio** con campanile: l'edificio più alto del villaggio.
* **2 banchi del mercato** con tenda in tessuto e merci sul banco.
* **Tre strade** che escono dalla piazza verso il nord, il mercato e lo stagno, con lampioni,
  tratti di steccato, carri, casse, barili, cataste di legna e un cartello indicatore. I bordi
  delle strade sono segnati da pietre irregolari fuse nel terreno, con buchi dove i sentieri
  raggiungono le porte.
* **250+ alberi** di tre specie (quercia, pino, betulla), ognuna con **tre varianti** davvero
  diverse: abete rosso, pino silvestre e mugo; quercia larga, alta e inclinata; betulla snella,
  a due fusti e d'autunno. Gli alberi hanno un'altezza credibile accanto a un giocatore di 1,8 m
  (quercia 5–7 m, betulla 4–5,5 m, abete 5–6 m) e sono costruiti come una struttura con sopra le
  foglie: tronchi rastremati con flare radicale, rami primari e secondari, e chiome di molte masse
  piccole con sfumatura verticale. Le conifere sono **verticilli di aghi** (punte lunghe e corte
  alternate, che pendono dal cono interno), non pila di dischi; il pino silvestre è un tronco nudo
  con un ombrello di aghi sopra. Il bosco ha tre radure vere, specie a fasce e densità ondulata
  invece di un disco uniforme (Visual Polish 16 e 18).
* **Cespugli** a più lobi (alcuni fioriti), **chiazze di fiori** con steli e capolini in tre
  varianti, massi e ciottoli, e uno **stagno** con ninfee, riva con panchina, fioriere e sassi a
  nord-est. Alberi e cespugli stanno fuori dai corridoi delle porte e tengono una verge dalle strade.
* **3200 ciuffi d'erba** in un unico `MultiMesh`, quindi una sola draw call: ogni ciuffo è fatto di
  cinque lame rastremate e opache (niente texture alpha, niente billboard), distribuite a due scale
  e colorate da un campo lento che disegna i campi di verde e d'oro.
* **Cielo e luce** che seguono l'ora simulata, non quella reale: il sole si sposta, il cielo
  cambia colore, la nebbia si infittisce, le finestre e i lampioni si accendono al tramonto.
  È la dimostrazione visibile che la simulazione ha un orologio proprio.
* **Interfaccia** in alto a sinistra: nome del gioco, giorno simulato con l'ora, e il nome
  dell'area in cui ti trovi (8 aree: piazza, tre strade, stagno, locanda, sala del consiglio,
  bosco; fuori da tutte, "Campi di Everafter").

### Gli abitanti (novità di questa fase)

Nel villaggio vivono **10 abitanti iniziali**, configurabili in un solo punto
(`npc_population_size` in `config/game_config.tres`, da 0 a 16). Ognuno ha:

* un **ID stabile** (`npc_001` … `npc_016`), un nome e un'età adulta;
* **professione** (agricoltore, raccoglitrice, pescatore, panettiera, locandiera, boscaiolo,
  cavatore, mercante, cancelliera, tessitrice, …) e un **posto di lavoro** con un orario;
* una **personalità** numerica (diligenza, socievolezza, curiosità, calma);
* tre **bisogni** (energia, fame, benessere) che cambiano a ogni minuto simulato;
* una **casa** e una posizione sul terreno;
* un **obiettivo** e un'**attività** correnti, con un motivo leggibile;
* una riga di **background personale**, che il sistema sociale trasforma nel primo ricordo.

La giornata è regolata da regole esplicite e deterministiche: sveglia e sonno tra le 22:00 e le
06:00, turno di lavoro nella propria fascia, pasti quando la fame supera la soglia (locanda o
mercato se aperti, altrimenti la dispensa di casa), riposo quando l'energia scende, tempo libero
in piazza, alla locanda o allo stagno. Non ci sono numeri casuali: lo stesso stato iniziale e lo
stesso numero di tick producono lo stesso risultato su qualunque macchina.

Gli abitanti sono rappresentati da modelli procedurali articolati (`NpcVisualFactory` + `NpcPresenter`,
alti ~1,72 m in scala con le porte delle case da 1,85 m), con abiti, copricapi e accessori distinti per
mestiere, pose procedurali interpolate per attività e il nome sopra la testa. Le viste 3D
vengono create solo entro `npc_view_distance` (70 unità, configurabile) e distrutte quando
si allontanano: **la simulazione non si ferma mai** per un NPC non disegnato. Il pannello a
destra resta compatto finché non si seleziona un abitante e, alla selezione, mostra la scheda
completa (nome, età, professione, indole, attività, obiettivo, tre barre dei bisogni, riepilogo,
tre relazioni principali e tre ricordi). Si può selezionare cliccando l'abitante oppure scegliendo
il nome dall'elenco: l'elenco funziona anche per chi è fuori portata visiva.

Il pannello e le capsule leggono soltanto i record; non li modificano. La simulazione vive in
`src/npcs/`, `src/economy/` e `src/social/` e non conosce né la scena 3D né l'interfaccia.

### Economia locale e ciclo delle risorse (novità di questa fase)

Il modulo `src/economy/` collega in modo deterministico il lavoro degli abitanti alle risorse della
comunità:

* **Quattro risorse intere non negative** (`ResourceType`): **Cibo** (`food`, prezzo base `2`),
  **Legno** (`wood`, prezzo base `3`), **Pietra** (`stone`, prezzo base `4`) e **Moneta** (`coin`,
  unità `1`).
* **Inventari convalidati** (`ResourceInventory`): magazzino collettivo del villaggio (`village`,
  scorte iniziali configurabili: `24 Cibo`, `12 Legno`, `10 Pietra`, `60 Moneta`), sacche
  individuali degli abitanti (`npc_001` … `npc_016`, `4 Moneta` iniziali) ed emporio di scambio del
  mercato (`market`, scorte finite). Nessuna operazione può portare una risorsa sotto zero o
  modificare parzialmente lo stato in caso di errore.
* **Produzione legata al lavoro reale**: un lavoratore accumula progresso produttivo (`+1` minuto
  lavorato per tick) **solo** mentre si trova fisicamente nel proprio luogo di lavoro con
  `Activity.WORKING`, prerequisiti della postazione soddisfatti (`workplace_prerequisites`), fame
  `< 92` ed energia `> 5`:
  * **Agricoltore** (`farmer`): `60` min lavorati → `+3 Cibo` (`+2 Moneta` di compenso dalla cassa
    comune);
  * **Raccoglitrice / Pescatore / Panettiera** (`forager`, `fisher`, `baker`): `60` min lavorati →
    `+2 Cibo` (`+1 Moneta`);
  * **Locandiera** (`innkeeper`): `75` min lavorati → `+2 Cibo` (`+1 Moneta`);
  * **Boscaiolo** (`woodcutter`): `60` min lavorati → `+2 Legno` (`+2 Moneta`);
  * **Cavatore / addetto all'estrazione** (`quarry_worker`): `60` min lavorati → `+2 Pietra`
    (`+2 Moneta`);
  * **Commerciante** (`merchant`): ogni `60` min lavorati al mercato facilita gli scambi tra sacche
    individuali, magazzino del villaggio ed emporio a prezzi base fissi, **senza mai creare risorse
    o moneta dal nulla**.
* **Consumo alimentare e carenze**: ogni pasto (`Activity.EATING` o razione serale delle `19:00`)
  consuma `1 Cibo` (dalla sacca personale o dal magazzino del villaggio, versando `2 Moneta` alla
  cassa comune se disponibili). Se il cibo è esaurito (`0 Cibo`), il pasto fallisce senza portare le
  scorte in negativo, registra una carenza, riduce il benessere (`-4,5` immediati e deriva negativa)
  e impedisce alla fame di scendere sotto `76,0`, **senza introdurre mortalità né carestie
  irreversibili**.
* **Progetti comunitari**: `Legno`, `Pietra` e `Moneta` vengono impiegati in progetti del villaggio
  (*Rinforzo del Granaio Comune*, *Cavalletto della Segheria*, *Armatura del Banco di Pietra*,
  *Manutenzione del Pozzo*) che migliorano la resa produttiva (`+1` per lotto) o il benessere.
* **Pannello economico** (`EconomyPanel`, a sinistra sotto `WorldHud`): mostra scorte disponibili,
  produzione e consumo del periodo (`+prod / -cons`), stato dei progetti, carenze attive e ultime
  transazioni importanti leggendo direttamente `EconomySystem`.

### Relazioni, interazioni e memoria (novità di questa fase)

Il modulo `src/social/` dà agli abitanti una vita sociale **persistente e deterministica**. Nessun
modello linguistico, nessun servizio online: ogni comportamento nasce da regole numeriche scritte
in `social_rules.gd`, leggibili e verificate dai test.

**Relazioni** (`SocialRelationship`, una per coppia di ID). La coppia è *canonica*
(`npc_001|npc_002`, IDs ordinati) e `RelationshipGraph` rifiuta i duplicati: due abitanti non
possono avere due relazioni tra loro. Tutti i valori sono interi `0..100`:

| Valore | Di chi è | Che cosa significa |
| --- | --- | --- |
| `familiarity` | **condiviso** | quanto si conoscono (0 estranei, 100 una vita insieme) |
| `tension` | **condiviso** | quanto è teso il rapporto (0 sereno, 100 ostilità aperta) |
| `trust_a` / `trust_b` | **direzionale** | quanto A si fida di B e viceversa: possono differire |
| `affinity_a` / `affinity_b` | **direzionale** | quanto A vuole bene a B e viceversa |

Ricevere aiuto alza **la propria** fiducia in chi aiuta, non quella di chi aiuta: per questo la
fiducia e l'affinità hanno due valori e la familiarità e la tensione uno solo.

**Due freni contro la crescita illimitata.** Ogni guadagno positivo passa da
`SocialRelationship`, che applica (1) **rendimenti decrescenti**: il passo è scalato per lo spazio
rimasto al tetto (`scaled_gain(90, 10) = 1`, `scaled_gain(100, 10) = 0`); (2) un **tetto
giornaliero** (`social_daily_gain_cap`, default `14`): la somma di fiducia, affinità e familiarità
concesse a una coppia in un giorno simulato non supera quel valore, qualunque sia il numero di
interazioni. I peggioramenti non sono limitati: un litigio fa sempre danno.

**Cinque interazioni**, scelte da contesto e mai a caso (ordine di priorità fisso):

| Interazione | Condizioni | Effetti principali |
| --- | --- | --- |
| **Disaccordo** | stesso posto di lavoro, entrambi al lavoro, carenza di cibo nel villaggio, almeno uno con fame `>= 72`, calma media `< 70` | tensione `+14`, fiducia `-6`, affinità `-7`, benessere `-2,0` |
| **Aiuto** | luogo che serve cibo, uno senza razione o con fame `>= 78`, l'altro sazio e con cibo davvero disponibile | familiarità `+8`, fiducia **solo di chi riceve** `+9`, affinità `+6` a entrambi, benessere `+2,5` a chi riceve / `+0,5` a chi aiuta |
| **Cooperazione** | entrambi al lavoro nello stesso posto | accettata: familiarità `+5`, fiducia `+5`, affinità `+4`, benessere `+0,8`; rifiutata: tensione `+8`, affinità di chi rifiuta `-4` |
| **Conversazione** | stesso luogo sociale, familiarità `>= 20` | familiarità `+4`, fiducia `+2`, affinità `+4`, benessere `+0,3` |
| **Saluto** | stesso luogo sociale, familiarità `< 20` | familiarità `+6`, affinità `+2` |

I numeri della colonna di destra sono quelli **nominali**, definiti dalle costanti di
`SocialRules`: l'effetto realmente applicato passa dai due freni descritti sopra e viene registrato
in `SocialEvent.effects`, quindi la scheda dell'abitante mostra il valore vero e non quello della
tabella. Un litigio, un aiuto o una cooperazione tra sconosciuti valgono di più della ripetizione
dello stesso gesto tra persone che si frequentano da mesi.

Un'interazione avviene solo se i due sono **nello stesso luogo**, a distanza
`<= social_interaction_radius` (3,2 unità), **non stanno dormendo, camminando o recuperando da un
percorso bloccato**, e non hanno già interagito da meno di `social_cooldown_ticks` (45 minuti
simulati). Al massimo `2` interazioni per tick: la folla non genera rumore e il registro resta
leggibile.

**Eventi oggettivi** (`SocialEvent`): id univoco (`evt_000042`), tipo, esito, tick, giorno, minuto,
luogo, IDs dei partecipanti, chi ha iniziato, descrizione sintetica, importanza `0..100` e gli
effetti realmente applicati. Il registro è limitato (`social_event_log_limit`, default 160): esce
prima l'evento meno importante e la rimozione di un evento importante viene contata e registrata
nel log. È la materia prima della cronaca futura.

**Memoria individuale** (`NpcMemory` dentro `MemoryBook`): id univoco (`mem_000107`), proprietario
(di chi è il ricordo), tipo, riferimento all'evento, giorno, partecipanti, luogo, ruolo
(`ricevuto` / `offerto` / `rifiutato` …), descrizione sintetica **dal punto di vista del
personaggio**, importanza, `source` (`diretto` / `raccontato`) e `certainty`. Gli ultimi due campi
esistono già, sempre `diretto` / `100` in questa fase: sono il punto d'aggancio per dare in futuro
a un NPC una visione parziale di un evento a cui ha assistito solo a metà.

* **Limiti configurabili**: `social_memory_capacity` (default 24 ricordi per abitante) e
  `social_memory_importance_floor` (default 12). Un saluto (importanza 6) **non viene proprio
  memorizzato**: esiste l'evento, non il ricordo.
* **Regola di selezione**: `retention_score = importanza * 3 + 2 * giorni_di_freschezza` (finestra
  di 6 giorni). Quando il libro è pieno esce il punteggio più basso; l'importanza domina, la
  freschezza serve solo a rompere i pareggi.
* **Niente scompare in silenzio**: ogni rimozione è contata (`evicted_count`), quelle di ricordi con
  importanza `>= 75` sono contate a parte (`evicted_protected_count`) e scritte nel log, e avvengono
  solo se non c'è altro da eliminare. L'evento resta comunque nel registro oggettivo: dimenticare è
  una proprietà del personaggio, mai del mondo.
* **Un ricordo non è la verità**: lo stesso aiuto produce due ricordi diversi (importanza `58` per
  chi lo riceve, `40` per chi lo offre, ruoli e testi diversi) che puntano allo stesso evento.

**Conseguenze reali.** Una cooperazione avviene solo se chi riceve la proposta è disponibile, e la
disponibilità è calcolata da `SocialRules.cooperation_willingness()`: `50` di partenza, `+0,4` per
punto di fiducia sopra 50, `+0,2` per punto di affinità sopra 50, `-0,6` per punto di tensione,
**`+14` se ricorda un aiuto ricevuto da quella persona**, **`-18` se ricorda un litigio degli
ultimi 3 giorni** (soglia `55`). Con fiducia 60 e affinità 50 la stessa coppia rifiuta a `54` e
accetta a `68` dopo un aiuto memorizzato: la memoria cambia un comportamento, non solo un testo.
Cooperazione, aiuto e litigio muovono anche `needs.wellbeing`, quindi l'effetto è visibile nello
stato della simulazione e non solo nel registro.

**Pannello.** La scheda dell'abitante (`NpcPanel`) mostra tre relazioni principali
(nome, etichetta derivata dai numeri, fiducia, familiarità), la riga *"Ultimo cambiamento"* con il
motivo documentato e il giorno dell'evento, e tre ricordi rilevanti. Nessun numero in più, nessun
pannello nuovo: le stesse righe che il sistema produce, lette direttamente da esso.

### Costo misurato della scena

L'ultima misura reale è quella di **Visual Polish 15**, letta dal log della suite di integrazione
(`--script res://tests/run_world_tests.gd`). La suite stampa i tre numeri a ogni esecuzione, così la
cifra non invecchia in silenzio:

```
[INFO] Budget measured: 175 meshes, 230740 triangles, 346 colliders (limits 260 / 260000 / 900)
```

| Voce | Valore misurato (Polish 15) |
| --- | --- |
| Mesh / draw call (villaggio + terreno) | **175** |
| Triangoli totali | **230.740** (limite 260.000) |
| Collider statici | **346** (limite 900) |
| Materiali distinti | **≤ 24** (verificato da `test_village_art.gd`) |
| Istanze d'erba | 3.200 (`GRASS_COUNT`), 1 draw call, nessuna ombra |

**Nota onesta (Visual Polish 16).** La vegetazione è stata ricostruita in questa fase, ma **la scena
non è stata rieseguita**: l'ambiente di verifica di questo passaggio non ha un eseguibile Godot
(GitHub Objects bloccato, nessun pacchetto npm/pip utilizzabile) e il repository non include binari.
Il budget non è quindi stato rimisurato qui; il margine della misura precedente è di ~29.000
triangoli, e la nuova vegetazione non dovrebbe consumarne di più (tre primitive al posto di
cilindri e sfere, dettaglio pieno solo entro 44 m dal centro o lungo le strade, erba di dieci
triangoli per ciuffo). Una stima statica — un port Python delle regole di piazzamento e dei
conteggi per primitiva, non il motore — dà circa **45.000–55.000 triangoli** per tutta la
vegetazione, fiori compresi. La cifra definitiva resta quella che stamperà la suite.

Per confronto: una casa "a primitive" sarebbe circa 15 nodi e 15 draw call; qui l'intera foresta
ne costa una manciata, perché `MeshBaker` fonde per materiale.

## 5. Struttura del repository

```
project.godot                  scena principale, autoload, input, rendering
icon.svg                       icona provvisoria (vettoriale, senza dipendenze)
config/game_config.tres        valori di tuning modificabili dall'editor
src/
  core/                        orologio simulato, configurazione, logging, singleton
    simulation_clock.gd          tempo simulato deterministico (1 tick = 1 minuto)
    game_config.gd               risorsa di configurazione + validazione
    game_log.gd                  logger minimale a livelli
    autoload/event_bus.gd        singleton "EventBus": segnali condivisi tra moduli
    autoload/game_root.gd        singleton "Game": possiede config e SimulationLoop
  simulation/                  sistemi della civiltà (indipendenti dalla scena 3D)
    simulation_system.gd         contratto di ogni sistema
    simulation_loop.gd           fixed timestep, pausa, velocità, catch-up
    systems/day_cycle_system.gd  sole e fase del giorno
  npcs/                        simulazione degli abitanti (pura logica, nessun nodo)
    npc_personality.gd           tratti numerici 0..100
    npc_needs.gd                 energia, fame, benessere; pressione e serializzazione
    npc_place.gd                 luogo logico: tipo, posizione, orari, cibo
    npc_place_registry.gd        indice dei luoghi e ricerche deterministiche
    npc_record.gd                stato di un abitante: identità, spazio, obiettivo, background
    npc_roster.gd                tabella fissa di 16 abitanti, nomi stabili
    npc_route_graph.gd           rete di waypoint su strade e luoghi, con ostacoli reali
    npc_simulation_system.gd     macchina a stati delle routine, movimento, bisogni
  economy/                     economia locale e ciclo delle risorse (pura logica, nessun nodo)
    resource_type.gd             tipi di risorsa (cibo, legno, pietra, moneta), prezzi e soglie
    resource_inventory.gd        inventario intero non negativo con operazioni atomiche
    economy_transaction.gd       registro tipizzato delle transazioni e dei rifiuti
    economy_rules.gd             regole di produzione, prerequisiti, progetti e riepiloghi
    economy_system.gd            sistema economico deterministico (produzione, consumo, scambi)
  social/                      relazioni, interazioni e memoria (pura logica, nessun nodo)
    social_relationship.gd       una coppia di IDs: valori condivisi e direzionali, freni di crescita
    relationship_graph.gd        proprietario unico delle relazioni, chiavi canoniche, niente orfani
    social_event.gd              evento oggettivo: attori, giorno, luogo, importanza, effetti
    npc_memory.gd                un ricordo: proprietario, importanza, ruolo, riferimento all'evento
    memory_book.gd               archivio limitato dei ricordi con regola di selezione
    social_interaction.gd        dati di lavoro di una singola interazione
    social_rules.gd              tutte le regole e le soglie, funzioni pure
    social_system.gd             sistema deterministico: prossimità, scelte, effetti, registro
  world/                       mondo 3D
    scenes/main_world.tscn       scena principale
    main_world.gd                radice di composizione: terreno, villaggio, abitanti, spawn
    terrain_generator.gd         height field deterministico (mesh + heightmap di collisione)
    player_explorer.gd           esploratore in prima persona (CharacterBody3D)
    npcs/
      village_npc_places.gd      dal piano del villaggio ai luoghi della simulazione
      npc_visual_factory.gd      rig procedurale articolato, abiti di mestiere e pose
      npc_presenter.gd           viste 3D, transizioni di posa, selezione con raycast, culling
    areas/area_registry.gd       regioni nominate, pura dati
    environment/
      village_layout.gd          il piano del villaggio: strade, lotti, pesi del terreno
      village_materials.gd       palette unica e materiali condivisi
      mesh_baker.gd              fonde primitive in una mesh per materiale
      building_factory.gd        case, locanda, sala, pozzo, banchi, oggetti
      vegetation_builder.gd      alberi, cespugli, fiori e massi (mesh fuse)
      meadow_builder.gd          erba istanziata: ciuffi e campo di colore (Polish 16)
      ground_surfaces.gd         pavimentazione della piazza e delle strade (Polish 15)
      paving_textures.gd         texture procedurali di acciottolato e sterrato
      village_builder.gd         assembla il villaggio: mesh, collider, acqua
      sky_rig.gd                 sole, cielo, nebbia, bagliore notturno
  ui/
    ui_theme.gd                  tema medievale condiviso (palette, tipografia, stili, tooltip)
    scenes/world_hud.tscn        interfaccia discreta: titolo, giorno, fase, velocità, area
    world_hud.gd
    scenes/diagnostics_hud.tscn  pannello diagnostico centrato (F1)
    diagnostics_hud.gd
    scenes/npc_panel.tscn        scheda dell'abitante selezionato (compatta a riposo)
    npc_panel.gd
    scenes/economy_panel.tscn    pannello economico del villaggio
    economy_panel.gd
    save_load_panel.gd           pannello Cronache e salvataggio (C)
tests/
  run_tests.gd                 runner di unità (exit code 0/1)
  run_world_tests.gd           runner di integrazione (avvia la scena, interroga la fisica)
  harness/test_harness.gd      micro harness di asserzioni
  unit/                        clock, loop, day cycle, terreno, config, layout, aree,
                               materiali, baker, arte e architettura edifici, dati NPC, roster,
                               aspetti visivi NPC/UI (test_npc_visuals), rete di percorso,
                               simulazione NPC, luoghi del villaggio, inventari/transazioni,
                               economia simulata, relazioni e memoria
                               (test_social_relationships, test_social_simulation), illuminazione
                               (test_sky_rig), geometria della pavimentazione
                               (test_ground_surfaces), vegetazione e distribuzione
                               (test_vegetation)
  integration/
    test_world_scene.gd        scena, terreno vs fisica, collisioni, budget, abitanti,
                               selezione, pannello NPC, pannello economico, strato sociale,
                               illuminazione oraria e tour della mappa
    test_paved_surfaces.gd     la pavimentazione esiste, è testurizzata e segue il suolo
  visual/paving_review.tscn    scena di confronto della piazza e delle strade (tasti 1–5)
  visual/vegetation_review.tscn scena di confronto di alberi, cespugli, fiori ed erba (tasti 1–5)
tools/
  check_project.py             verifiche statiche di coerenza del progetto (solo Python 3)
  run_checks.sh                esegue tutti i controlli disponibili
docs/
  ARCHITECTURE.md              scelte architetturali e regole di dipendenza
  LIGHTING.md                  illuminazione e atmosfera: problemi, valori, budget, futuro
  WORLD_DETAIL.md              densità ambientale e dettagli del mondo: interventi, regole
  NPC_AND_UI_POLISH.md         rifinitura visiva di NPC, pose procedurali e interfaccia (Polish 05)
  BUILDING_POLISH_07.md         rifinitura architettonica degli edifici procedurali (Polish 07)
  TERRAIN_POLISH_06.md         terreno e paesaggio: palette, bordi, rilievo (Polish 06)
  VISUAL_POLISH_11.md          audit strutturale del villaggio (Polish 11)
  VISUAL_POLISH_12.md          ricostruzione degli edifici (Polish 12)
  VISUAL_POLISH_13.md          tetti e silhouette architettoniche (Polish 13)
  VISUAL_POLISH_14.md          paesaggio modellato: rilievo, spalle stradali, orizzonte (Polish 14)
  VISUAL_POLISH_15.md          strade curve, piazza composta e superfici calpestabili (Polish 15)
  VISUAL_POLISH_16.md          ricostruzione della vegetazione: alberi, cespugli, fiori, erba (Polish 16)
  VISUAL_POLISH_18.md          alberi ricostruiti (verticilli, scheletro + foglie) e movimento rallentato (Polish 18)
  ROADMAP.md                   fasi successive, criteri di accettazione, rischi
```

## 6. Renderer e prestazioni

**Renderer scelto: `forward_plus`** (con MSAA 3D 2x, una sola luce con ombre a 128 m, penombre
PCSS, tonemapping filmico con spalla morbida, SSAO e glow attivi e misurati, foschia leggera a
costo fisso — mai volumetrica — `Camera3D.far = 420`).

Motivazione:

* una GTX 1060 gestisce Vulkan senza problemi; con 145 draw call e ~150k triangoli la scena è
  molto al di sotto di ciò che mette in difficoltà quella scheda a 1080p;
* `forward_plus` offre gli strumenti di debug migliori e resta il percorso più mantenuto del
  motore, quindi è la scelta più stabile su cui costruire le fasi successive;
* la compatibilità è gestita a livello di impostazione, non di codice: se un driver Vulkan dà
  problemi si passa a `mobile` o `gl_compatibility` in *Project Settings → Rendering → Renderer →
  Rendering Method*. **Nessuna riga di codice dipende dal renderer scelto.**

Regole di costo applicate nel codice, non solo dichiarate:

1. **una mesh per materiale** (`MeshBaker`): un villaggio di centinaia di solidi diventa 145 draw
   call invece di migliaia;
2. **una palette condivisa** (`VillageMaterials`): ≤ 24 materiali per tutto il villaggio, con
   variazione cromatica affidata ai colori per vertice;
3. **erba in `MultiMesh`**, senza ombre proiettate;
4. **una sola mappa d'ombre**: la luce di riempimento (`Sky/Fill`) non ne ha ed è esclusa dal
   cielo (`SKY_MODE_LIGHT_ONLY`);
5. **atmosfera a costo fisso**: SSAO e glow con valori misurati, foschia esponenziale + di quota +
   prospettiva aerea + scattering solare; **niente nebbia volumetrica** (primo effetto fuori
   budget su GTX 1060);
6. un test (`PerformanceBudget`) fallisce se draw call, triangoli o collider superano il budget:
   il costo non può raddoppiare di nascosto.

## 7. Controlli e verifiche

### Con solo Python 3 (nessun motore necessario)

```bash
python3 tools/check_project.py            # coerenza di percorsi, scene, nodi, azioni di input
pip install gdtoolkit                     # opzionale: parser e linter GDScript
gdparse $(find src tests -name '*.gd')    # sintassi GDScript
gdlint src tests                          # stile
```

### Con Godot installato

```bash
bash tools/run_checks.sh                              # esegue tutto ciò che è disponibile
godot --headless --path . --script res://tests/run_tests.gd
godot --headless --path . --script res://tests/run_world_tests.gd
```

`tools/run_checks.sh` stampa chiaramente quali controlli sono stati **eseguiti** e quali sono stati
**saltati** perché lo strumento non è installato: non dichiara mai superato un test non eseguito.

### Verifiche eseguite su questa fase

Il motore **Godot 4.7.2-stable** è stato compilato dai sorgenti in questa sessione (build headless
`linuxbsd`, senza X11, Wayland né driver grafici) e usato per eseguire davvero entrambe le suite.
Nessun numero qui sotto è stimato.

| Controllo | Strumento | Esito |
| --- | --- | --- |
| Sintassi di tutti i 69 script GDScript di `src/` e `tests/` | `gdparse` (gdtoolkit 4.5.0) | **eseguito — OK** |
| Stile GDScript | `gdlint` (gdtoolkit 4.5.0) | **eseguito — 0 problemi** |
| Coerenza progetto: scena principale, autoload, `res://`, ext/sub resource, percorsi `$Nodo` degli script rispetto alle scene, azioni di input, `.gitignore` | `tools/check_project.py` | **eseguito — OK** |
| Suite di unità headless (`tests/run_tests.gd`) | Godot 4.7.2 headless | **eseguito — 1162 passati, 0 falliti, 0 saltati** |
| Suite di integrazione (`tests/run_world_tests.gd`) | Godot 4.7.2 headless | **eseguito — 113 passati, 0 falliti, 0 saltati** |
| Resa visiva su GPU (come *appare* il villaggio e come si muovono le capsule) | — | **NON eseguita**: l'ambiente di verifica non ha GPU. Geometria, materiali e collisioni sono verificati; l'immagine finale no |
| Prova su Windows con Godot desktop, selezione col mouse e pannello | — | **NON eseguita**: da fare in revisione |

`bash tools/run_checks.sh` esegue tutti e cinque i controlli e termina con
`All executed checks passed.` (in questa sessione: 1162 + 113 asserzioni, zero errori di script).
Di queste, **268 sono nuove** e riguardano solo relazioni, interazioni e memoria: 251 nelle due
suite di unità (126 in `test_social_relationships.gd`, 125 in `test_social_simulation.gd`) e 17
nella sezione `check_social` dell'integrazione. Le cifre sono state misurate disattivando le suite
sociali e ripetendo l'esecuzione (918 → 1162 unità, 96 → 113 integrazione), non contate a mano.

I controlli statici non sostituiscono l'esecuzione: coprono sintassi, stile, percorsi delle risorse
e coerenza dei nodi, non il comportamento. La suite di unità contiene le prove di determinismo,
bisogni, routine, movimento continuo e luoghi; la suite di integrazione contiene le prove di
selezione, pannello e simulazione senza viste.

```bash
bash tools/run_checks.sh
```

Che cosa copre davvero la suite di integrazione, perché è la parte che conta:

* **terreno visto = terreno camminato**: 196 raggi verso il basso confrontano la superficie fisica
  (`HeightMapShape3D`) con `TerrainGenerator.height_at()`; lo scarto massimo ammesso è 5 cm ed è
  risultato ~0. Questo è il test che avrebbe preso subito il bug di winding della fase precedente.
* **il giocatore sta in piedi**: dopo 45 frame di fisica `is_on_floor()` è vero e il centro della
  capsula è a una mezza altezza dal terreno.
* **il giocatore non affonda**: su 120 frame ulteriori la distanza minima dal terreno resta
  positiva.
* **i muri fermano il giocatore**: `PhysicsServer3D.body_test_motion()` con la **capsula reale del
  giocatore** contro una casa vera; la corsa si interrompe ben prima dei 12 metri richiesti.
* **il giocatore non esce dal mondo**: la posizione è limitata ai bordi del terreno.
* **budget**: draw call, triangoli e collider restano entro i limiti dichiarati (il conteggio
  esclude le capsule degli abitanti, che sono viste temporanee).
* **abitanti** (`check_npcs`): la popolazione segue `npc_population_size`, gli ID sono unici e i
  nomi stabili; i bisogni evolvono con `Game.advance_simulation()`; con `render_distance` a 0
  nessuna capsula è disegnata eppure i record continuano a cambiare; la selezione dal presenter
  arriva al pannello, che mostra nome, attività, obiettivo, barre e riepilogo del personaggio
  scelto; un ID inesistente viene rifiutato senza cambiare la selezione.
* **strato sociale** (`check_social`): il sistema è registrato in `Game` e non pilotato dalla scena;
  ogni relazione unisce due abitanti esistenti e nessuna coppia è duplicata; due giorni simulati
  producono eventi i cui attori esistono tutti; il registro eventi e i ricordi restano entro i
  limiti configurati; `validate()` resta pulito; il pannello mostra le stesse righe che produce il
  sistema (relazioni, motivo dell'ultimo cambiamento, ricordi).

### Difetti reali trovati eseguendo il motore in questa fase

1. **Una funzione duplicata che solo il motore vede.** `social_system.gd` conteneva due volte
   `get_last_tick()`: `gdparse` e `gdlint` passavano entrambi, perché la sintassi è valida, mentre
   il motore rifiutava l'intero script con *"Function has the same name as a previously declared
   function"*. La conseguenza a catena è doppia: `SocialSystem` non si compila e il runner, che
   chiama `quit()` solo alla fine di `_initialize()`, resta appeso per sempre invece di uscire con
   un errore. Corretto rimuovendo il duplicato. È la seconda volta che succede in questo progetto
   (vedi la fase precedente, `npc_route_graph.gd`): **i controlli statici non sostituiscono
   l'esecuzione**.
2. **Riferimenti pendenti dopo un caricamento.** `SocialSystem.from_dict()` puliva relazioni e
   ricordi che puntavano ad abitanti inesistenti, ma non gli eventi: caricando il salvataggio di un
   mondo da 6 abitanti in un mondo da 2, `validate()` segnalava 3 eventi con attori sconosciuti.
   Ora `_drop_dangling_events()` li elimina al caricamento, li conta in `dropped_event_count` e lo
   scrive nel log. Il test `_test_load_drops_unknown_references` copre esattamente questo caso.
3. **Due aspettative di test sbagliate, non il codice.** (a) Il tetto giornaliero di crescita è un
   **budget condiviso** tra familiarità, fiducia e affinità: un test si aspettava `+8` di affinità
   dopo aver già concesso `+10` di fiducia nello stesso giorno, e il valore corretto era `+4`. (b)
   `strength()` di una relazione senza fiducia né affinità è pari alla sola familiarità, non
   maggiore. In entrambi i casi il comportamento era quello progettato e documentato: sono stati
   corretti i test, e il vincolo del budget condiviso è ora scritto nella documentazione della
   classe.

### Difetti reali trovati eseguendo il motore nella fase economia (`0.4.0-economy`)

1. **Un errore di parsing che solo il motore vede.** `npc_route_graph.gd` conteneva
   `var current := queue.pop_back()`: `pop_back()` restituisce un `Variant` e Godot tratta
   l'inferenza da `Variant` come errore, quindi il motore rifiutava l'intero script (e a cascata
   `NpcSimulationSystem`, `Game` e la scena). `gdparse` e `gdlint` non lo segnalano, perché la
   sintassi è valida: è la prova che i controlli statici non sostituiscono l'esecuzione. Corretto
   con un tipo esplicito.
2. **Uno steccato tagliava la strada dei campi.** Il recinto del paddock attraversava la strada
   sud-ovest con un box di collisione di 3 m: il giocatore non poteva raggiungere i campi e il
   grafo dei percorsi segnalava `work_field` come irraggiungibile. Il layout ora lascia un cancello
   aperto sulla carreggiata, e `test_village_layout` verifica che nessuno steccato la ostruisca.
3. **Precedenza degli operatori in una stringa di log.** `_build_summary()` concatenava due
   stringhe e applicava `%` solo alla seconda: all'avvio il motore stampava
   "String formatting error". Ora la stringa viene composta prima di essere formattata.
4. **Il runner di integrazione non poteva nominare gli autoload.** Il suo script è compilato prima
   che `Game` e `EventBus` esistano: i riferimenti statici fallivano e la scena si costruiva a
   metà (niente giocatore, niente presentatore, niente pannello). Ora il modulo di test viene
   caricato a runtime dopo il primo frame e l'autoload è risolto tramite l'albero.
5. **`null` in `ARRAY_INDEX`.** Il conteggio dei triangoli del budget chiamava `is_empty()` su
   `null` per le mesh non indicizzate, generando un errore di script a ogni superficie. Corretto:
   il conteggio ora include anche quelle superfici.

### Difetti reali trovati eseguendo il motore nelle prime fasi (villaggio e NPC)

La fase precedente dichiarava i test "scritti ma non eseguiti". Eseguendoli sono emersi tre bug
(riguardano il terreno e il loop del tempo, non gli abitanti):

1. **`SimulationClock.to_string()` non veniva mai chiamata.** In GDScript il metodo virtuale è
   `_to_string()`; un metodo chiamato `to_string()` non sovrascrive nulla. Ora corretto, e il test
   confronta la stringa formattata, quindi la regressione non può tornare.
2. **Il terreno aveva il winding invertito**: tutte le normali puntavano verso il basso. Misurato
   sul motore: Godot 4.7.2 ricava la normale di un triangolo `(a, b, c)` come `(c − a) × (b − a)`.
   Con il back-face culling attivo il suolo sarebbe sparito visto dall'alto. Corretto, e coperto da
   `tests/unit/test_mesh_baker.gd` e dai raggi della suite di integrazione.
3. **Un test del loop chiedeva l'impossibile**: `update(0.25)` a velocità x4 pretende 20 tick, ma
   il guard `max_steps_per_frame = 12` (giustamente) li limita, e l'accumulatore in virgola mobile
   perde il ventesimo tick. Il test ora usa un `tick_seconds` potenza di due e un tetto esplicito,
   e verifica il guard come comportamento proprio.

## 8. Limiti noti di questa fase

* **Economia locale a prezzi base fissi**: sono implementati inventari, produzione da lavoro,
  consumo alimentare, scambi tramite mercante e progetti comunitari; **non** esistono ancora prezzi
  dinamici da domanda/offerta complessa, prestiti, debito, tassazione o mercati multi-insediamento.
* **Sistema sociale minimo, nessuna società**: esistono relazioni a coppie, cinque interazioni e
  una memoria individuale limitata. **Non** esistono famiglie, gruppi, fazioni, reputazione
  pubblica, politica, leggi o cronache consultabili: un evento sociale resta un dato strutturato,
  non un racconto.
* **Le interazioni non spostano nessuno**: avvengono dove la routine ha già portato i due abitanti
  e cambiano fiducia, affinità, tensione e benessere; non cambiano ancora la destinazione di un
  abitante. La memoria influenza la disponibilità a cooperare, non la scelta del luogo.
* **Nessuna prospettiva incompleta attiva**: `source` e `certainty` esistono in ogni ricordo, ma in
  questa fase valgono sempre `diretto` e `100`. Un personaggio non può ancora ricordare male, né
  sapere qualcosa per sentito dire.
* **Il registro eventi non è una cronaca**: è limitato, ordinato e serializzabile, ma non esiste
  ancora un pannello o un libro per leggerlo in gioco (Fase 5).
* **Il runner headless resta appeso se una suite non compila**: `quit()` viene chiamato solo alla
  fine di `_initialize()`, quindi un errore di parse in una suite lascia il processo in attesa
  invece di uscire con codice 1. Va aggiunto un watchdog nel runner.
* **Nessun interno**: le case sono volumi chiusi con una scatola di collisione. Porte e finestre
  sono dettagli di superficie, non aperture.
* **Persistenza v1**: esiste un modulo `persistence/` che salva/carica tutto lo stato in JSON su
  `user://` con scrittura atomica; c'è anche l'avanzamento offline con tetto e la cronaca
  accessibile dal pannello (`C`). Non esistono ancora slot multipli o un migratore di formato.
* **La resa visiva non è stata vista su GPU in questa iterazione.** Geometria, materiali e illuminazione sono costruiti
  con criterio e verificati strutturalmente, ma l'aspetto finale va giudicato a schermo. Il pass
  di illuminazione/atmosfera (`docs/LIGHTING.md`) ha una verifica numerica eseguibile (curve,
  energie, arco delle ore da più punti della mappa) ma **nessuna verifica visiva**: va controllato
  a occhio su una macchina con GPU.
* Il terreno è un'unica mesh generata all'avvio (25.600 vertici). Oltre queste dimensioni serviranno
  chunk e streaming (in roadmap).
* Alberi e oggetti non hanno LOD: a 145 draw call non serve, ma andrà rivisto se il mondo cresce.
* L'IA generativa non è integrata e non è richiesta per giocare.
* Nessun preset di export: l'esportazione Windows verrà configurata quando ci saranno contenuti
  sufficienti da impacchettare.

## Verificare il salvataggio su Windows

Una sequenza consigliata per provare che il salvataggio funzioni davvero con l'eseguibile
Godot per Windows (`Godot_v4.x-stable_win64.exe`):

1. Avvia il gioco con `Godot_v4.x-stable_win64_console.exe --path .` e lascia avanzare la
   simulazione per almeno un minuto (simulato) — puoi accelerare con `+`/`-`.
2. Premi `C` per aprire il pannello Cronache e salvataggio; verifica che compaia "Nessun
   salvataggio presente". Premi "Salva adesso" e conferma.
3. Chiudi la finestra: all'uscita il gioco salva di nuovo (l'autosave sovrascrive
   tranquillamente il file).
4. Riapri il gioco. All'avvio il salvataggio deve venir caricato automaticamente; il giorno
   e l'ora nel corner in alto a sinistra devono essere quelli del salvataggio, non il giorno 1
   alle 07:00 di un mondo nuovo. Premi `C` per verificare la data/orario nel pannello.
5. Prova l'avanzamento offline: salva, chiudi il gioco, aspetta alcuni minuti reali (o cambia
   temporaneamente l'orologio di sistema **in avanti** di un'ora), riapri: il mondo deve essere
   andato avanti e la cronaca deve contenere una voce "Sei tornato dopo …".
6. Prova la gestione dei file corrotti: apri `%APPDATA%/Godot/app_userdata/EVERAFTER/`, apri
   `everafter_save.json` con un editor di testo, corrompi una riga a caso, salva e riavvia. Il
   gioco deve avvisare che il file è illeggibile e partire con un mondo nuovo invece di
   bloccarsi.
7. Premi "Nuovo mondo" per eliminare il salvataggio e ricominciare da capo.

Il file `everafter_save.json.bak` nella stessa cartella dev'essere una copia leggibile del
salvataggio precedente.

## 9. Come contribuire / proseguire

1. Leggi [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) prima di scrivere codice: contiene le
   regole di dipendenza tra moduli e la convenzione sul determinismo.
2. Scegli la fase successiva in [`docs/ROADMAP.md`](docs/ROADMAP.md).
3. Ogni sistema nuovo arriva con: script tipizzato, test headless, riga di documentazione,
   nessuna API dichiarata ma non usata.
4. Prima di proporre una modifica: `bash tools/run_checks.sh`. Una modifica che tocca mondo,
   terreno o giocatore deve mantenere verde anche `tests/run_world_tests.gd`.

## Visual Polish 12 — edifici ricostruiti

Le case esistenti, la locanda e il municipio usano ora un kit geometrico condiviso con
pareti spesse e aperture reali, telai portanti, falde chiuse, gronde e colmi distinti.
Collisioni, ID, percorsi e interazioni rimangono compatibili. Audit delle tipologie,
misure e risultati dei test in [`docs/VISUAL_POLISH_12.md`](docs/VISUAL_POLISH_12.md).

Per confrontare le cinque varianti senza toccare i salvataggi:
`godot --path . res://tests/visual/building_review.tscn` (1–5: edificio, F1–F4: viste).
Test strutturali mirati: `godot --headless --path . --script res://tests/run_building_tests.gd`.

## Visual Polish 14 — paesaggio modellato

Il terreno non è più una "pelle tesa" sopra un'onda: l'algoritmo esistente è stato esteso con
un'armatura a scala ampia (dorsali e valli), micro-rilievo dei campi, creste rocciose con
affioramenti, spalle stradali digradanti, un bordo dell'orizzonte non più rettilineo e piazzole
livellate sotto ogni edificio. Un nuovo `TerrainRelaxer` limita il salto massimo tra celle sul
terreno aperto e fonde le piazzole, sulla **stessa griglia** letta dalla mesh e dalla
`HeightMapShape3D`: la forma cambia, il contratto tra ciò che si vede e ciò che si cammina no.
Misure, prima/dopo e limiti dichiarati in [`docs/VISUAL_POLISH_14.md`](docs/VISUAL_POLISH_14.md).

Verifiche: `tests/unit/test_terrain_relaxer.gd` (nuovo), `test_terrain_generator.gd` esteso e
`check_terrain_shape` nella suite di integrazione.

## Visual Polish 15 — strade, piazza e superfici calpestabili

Piazza e strade non sono più solo colore dipinto sulla griglia del terreno: un sottile strato
pavimentato (`GroundSurfaces`, nuovo) segue la stessa altezza della `HeightMapShape3D`, con
cordoli inclinati sul pendio, bordi irregolari e una transizione pietra → terra → erba affidata
ai colori per vertice. Le tre strade sono ora curve continue invece di spezzate a 17 m; la piazza
ha un bordo non circolare, un marciapiede di ghiaia e campiture leggibili attorno al pozzo.
Le superfici non aggiungono collider: il giocatore continua a camminare sul heightmap, quindi
pendenze, accessi, porte e percorsi NPC restano identici. Due sole draw call e poche migliaia di
triangoli, con texture procedurali (nessuna immagine nel repository).
Misure, difetti corretti e verifiche in [`docs/VISUAL_POLISH_15.md`](docs/VISUAL_POLISH_15.md).

Confronto a occhio senza toccare i salvataggi:
`godot --path . res://tests/visual/paving_review.tscn` (1–5: viste dalla camera di gioco).
