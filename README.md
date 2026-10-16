# EVERAFTER

Simulazione 3D di una civiltà persistente e autonoma, realizzata con **Godot 4** e **GDScript tipizzato**.

Il mondo è abitato da personaggi con identità, bisogni, professioni, obiettivi, relazioni e memoria.
Gli abitanti agiscono autonomamente, la società evolve e gli eventi lasciano conseguenze nel tempo.
Il gioco deve funzionare **offline**, senza servizi a pagamento e senza server obbligatori.

Questo repository contiene oggi la **Fase 0 — fondazioni tecniche**: un progetto Godot 4 pulito,
una scena 3D avviabile, un orologio di simulazione deterministico separato dal rendering,
un'interfaccia diagnostica minima e una base di test headless.

> Stato onesto del progetto: **non esistono ancora NPC, economia, relazioni, politica, cronache o
> salvataggi.** Sono progettati in [`docs/ROADMAP.md`](docs/ROADMAP.md), non implementati.

---

## 1. Requisiti

| Voce | Valore |
| --- | --- |
| Motore | **Godot 4.5 o superiore, build stabile** (consigliata: `4.7.2-stable`, l'ultima stabile al momento) |
| Sistema operativo | Windows 10/11 64-bit (target iniziale del progetto) |
| GPU | Classe NVIDIA GTX 1060 o superiore, con driver Vulkan aggiornati |
| RAM | 16 GB consigliati |
| Dipendenze esterne | Nessuna. Niente plugin, niente pacchetti, niente rete a runtime |
| Strumenti di sviluppo (opzionali) | Python 3 e `gdtoolkit` per i controlli statici |

Il progetto è **solo testo** (script, scene, risorsa di configurazione, documentazione): non ci sono
asset binari da scaricare. Una volta clonato, funziona senza connessione a Internet.

## 2. Aprire ed eseguire il progetto su Windows

1. Scarica Godot 4 stabile da <https://godotengine.org/download/windows/>
   (file `Godot_v4.x-stable_win64.exe.zip`; la versione `_console` è comoda per vedere i log).
2. Estrai l'archivio dove preferisci. Non serve installare nulla.
3. Avvia l'editor, premi **Import**, seleziona il file `project.godot` di questa repository
   e premi **Import & Edit**.
4. Al primo avvio Godot genera la cartella `.godot/` (cache locale, ignorata da git) e importa
   `icon.svg`. È normale e richiede pochi secondi.
5. Premi **F5** (oppure il pulsante ▶ in alto a destra): il progetto parte dalla scena principale
   `res://src/world/scenes/main_world.tscn`.

### Da riga di comando (senza aprire l'editor)

Apri un terminale nella cartella del progetto e usa l'eseguibile di Godot:

```bat
:: esegue il gioco
Godot_v4.7.2-stable_win64.exe --path .

:: esegue il gioco in una finestra senza bordi, utile per i test rapidi
Godot_v4.7.2-stable_win64.exe --path . --resolution 1600x900

:: esegue la suite di test headless (nessuna finestra, nessuna GPU necessaria)
Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/run_tests.gd

:: log dettagliato del motore
Godot_v4.7.2-stable_win64_console.exe --path . --verbose
```

Su Windows l'output su console è visibile solo con l'eseguibile `_console.exe`.

## 3. Controlli

| Input | Azione |
| --- | --- |
| `W` `A` `S` `D` o frecce | Muoversi |
| `Shift` | Correre |
| `Spazio` | Saltare |
| Mouse | Guardarsi attorno |
| Clic sinistro | Ricattura il mouse quando è stato liberato |
| `Esc` | Libera il mouse (per tornare all'editor o alla finestra) |
| `P` | Pausa / ripresa della simulazione |
| `+` / `-` | Aumenta / diminuisce la velocità della simulazione (x1, x3, x10) |
| `F1` | Nasconde / mostra il pannello diagnostico |

Tutti gli input sono mappati come **azioni** in `project.godot` (sezione `[input]`), quindi sono
rimappabili dall'editor senza toccare il codice.

## 4. Che cosa si vede avviando il gioco

* Un terreno collinare procedurale di 127 × 127 unità, con una piazza piatta al centro.
* Un villaggio provvisorio: un monumento centrale, 8 case, 24 alberi, tutti generati da primitive
  del motore (nessun asset esterno).
* Cielo procedurale, sole con ombre, nebbia leggera, tonemapping filmico.
* **Il sole si muove e il cielo cambia colore seguendo l'ora simulata**, non il tempo reale: è la
  dimostrazione visibile che la simulazione ha un orologio proprio.
* Il mondo inizia alle **07:00 del giorno 1** (`GameConfig.start_minute_of_day`), quindi il primo
  avvio avviene all'alba e non al buio.
* In alto a sinistra, il pannello diagnostico con: nome del progetto, **giorno simulato**, ora del
  mondo, contatore dei tick, velocità, fase del giorno, FPS e ultima riga di stato.

## 5. Struttura del repository

```
project.godot              configurazione del motore: scena principale, autoload, input, rendering
icon.svg                   icona provvisoria (vettoriale, senza dipendenze)
config/game_config.tres    valori di tuning modificabili dall'editor (GameConfig)
src/
  core/                    orologio simulato, configurazione, logging, singleton di coordinamento
    simulation_clock.gd      tempo simulato deterministico (1 tick = 1 minuto, 1440 tick/giorno)
    game_config.gd           risorsa di configurazione + validazione
    game_log.gd              logger minimale a livelli
    autoload/event_bus.gd    singleton "EventBus": segnali condivisi tra moduli
    autoload/game_root.gd    singleton "Game": possiede config e SimulationLoop
  simulation/              sistemi della civiltà (indipendenti dalla scena 3D)
    simulation_system.gd     contratto di ogni sistema
    simulation_loop.gd       fixed timestep, pausa, velocità, catch-up
    systems/day_cycle_system.gd   primo sistema reale: sole e fase del giorno
  world/                   mondo 3D
    scenes/main_world.tscn   scena principale
    main_world.gd            costruisce terreno e villaggio, mostra lo stato della simulazione
    terrain_generator.gd     height field deterministico (mesh + heightmap di collisione)
    prop_builder.gd          villaggio provvisorio da primitive
    player_explorer.gd       esploratore in prima persona
  ui/
    scenes/diagnostics_hud.tscn   pannello diagnostico
    diagnostics_hud.gd
tests/                     suite eseguibile headless (nessuna scena, nessuna GPU)
  run_tests.gd               runner (exit code 0/1, pronto per una CI)
  harness/test_harness.gd    micro harness di asserzioni
  unit/                      test di clock, loop, day cycle, terreno, configurazione
tools/
  check_project.py           verifiche statiche di coerenza del progetto (serve solo Python 3)
  run_checks.sh              esegue tutti i controlli disponibili
docs/
  ARCHITECTURE.md            scelte architetturali e regole di dipendenza
  ROADMAP.md                 fasi successive, criteri di accettazione, rischi
```

## 6. Controlli e verifiche

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
godot --headless --path . --script res://tests/run_tests.gd   # solo la suite di test
```

`tools/run_checks.sh` stampa chiaramente quali controlli sono stati **eseguiti** e quali sono stati
**saltati** perché lo strumento non è installato: non dichiara mai superato un test non eseguito.

### Verifiche realmente eseguite su questa fase

| Controllo | Strumento | Esito |
| --- | --- | --- |
| Sintassi di tutti i 20 script GDScript | `gdparse` (gdtoolkit 4.5.0) | **eseguito — OK** |
| Stile GDScript | `gdlint` (gdtoolkit 4.5.0) | **eseguito — 0 problemi** |
| Coerenza progetto: scena principale, autoload, `res://`, ext/sub resource, percorsi `$Nodo` degli script rispetto alle scene, azioni di input, `.gitignore` | `tools/check_project.py` | **eseguito — OK** |
| Suite di test headless (`tests/run_tests.gd`) | Godot 4 | **NON eseguita**: l'ambiente in cui è stata scritta questa fase non dispone dell'eseguibile Godot e non può scaricarlo |
| Avvio del gioco e resa 3D | Godot 4 | **NON eseguito**, per lo stesso motivo |

I test headless sono scritti e pronti: coprono orologio, loop a passo fisso, day cycle, generazione
del terreno e configurazione. Vanno eseguiti al primo avvio su una macchina con Godot installato
(comando qui sopra); l'esito va considerato parte della revisione di questa fase.

## 7. Limiti noti di questa fase

* Nessun NPC, bisogno, lavoro, inventario, prezzo, relazione, legge, fazione o cronaca.
* Nessuna serializzazione su disco: i metodi `to_dict()` / `from_dict()` esistono su clock, loop e
  sistemi, ma non c'è ancora un modulo `persistence` che li usi.
* Il terreno è un'unica mesh generata all'avvio (circa 16k vertici / 32k triangoli). Va bene per
  queste dimensioni; oltre serviranno chunk e streaming (in roadmap).
* Le case non hanno interni, porte apribili o percorsi: la collisione è una scatola.
* Gli alberi e gli oggetti non proiettano ombre morbide né hanno LOD: materiale piatto condiviso.
* L'IA generativa non è integrata e non è richiesta per giocare: arriverà come livello opzionale.
* Nessun preset di export: l'esportazione Windows verrà configurata quando ci saranno contenuti
  sufficienti da impacchettare.

## 8. Come contribuire / proseguire

1. Leggi [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) prima di scrivere codice: contiene le
   regole di dipendenza tra moduli e la convenzione sul determinismo.
2. Scegli la fase successiva in [`docs/ROADMAP.md`](docs/ROADMAP.md).
3. Ogni sistema nuovo arriva con: script tipizzato, test headless, riga di documentazione,
   nessuna API dichiarata ma non usata.
4. Prima di proporre una modifica: `bash tools/run_checks.sh` e, se Godot è disponibile,
   la suite headless.
