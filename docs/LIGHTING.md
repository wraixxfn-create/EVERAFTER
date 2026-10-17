# Illuminazione e atmosfera

Questo documento descrive il pass di **illuminazione e atmosfera** sulle scene esistenti di
EVERAFTER: cosa non funzionava, cosa è stato cambiato e perché, e cosa resta per il futuro.
Non è una nuova scena e non è un nuovo sistema temporale: la mappa, i modelli, i controlli e le
meccaniche sono quelli di sempre, e il ciclo giorno/notte esistente
(`src/simulation/systems/day_cycle_system.gd`) è stato **migliorato, non duplicato**.

Il mapping simulazione -> luce vive in un unico nodo,
[`SkyRig`](../src/world/environment/sky_rig.gd), come da architettura: quel nodo è anche
l'aggancio previsto per un futuro sistema meteo.

---

## 1. Problemi reali riscontrati (prima degli interventi)

Analizzati sul codice e sui valori reali di scena, non a occhio:

1. **Luce uniforme per gran parte della giornata.** Il daylight factor saturava a 12° di
   elevazione solare: tra le 8:00 e le 16:00 energia e colore del sole erano *identici*. Il
   mondo non raccontava il passare del giorno.
2. **Notte troppo scura e senza direzione.** Di notte la luce solare restava accesa a energia
   minima **sotto l'orizzonte**: illuminava il mondo dal basso (sottofondi accesi, nessuna
   ombra leggibile) e il cielo notturno era quasi nero, con ambient e fill troppo deboli per
   sostenere le silhouette.
3. **Cielo scollegato dal terreno.** La foschia usava un colore piatto e non integrava il
   fondo dell'orizzonte con la volta celeste; l'emisfero "terra" del cielo procedurale era un
   marrone-grigio senza rapporto con il terreno; la banda orizzontale era troppo sottile e
   mostrava gradazioni (banding) nette.
4. **Ambiente freddo e uniforme.** L'ambient veniva solo dal cielo (blu): le ombre erano fredde
   e slavate, senza rimbalzo caldo dal terreno, e il rapporto luce/ombra era piatto.
5. **Due "soli" nel cielo.** La luce di riempimento aveva `sky_mode` di default
   (`LIGHT_AND_SKY`): contribuiva al cielo come un secondo disco luminoso.
6. **Superfici chiare sovraesposte.** Sole a 1.5 con `tonemap_white = 3.2` e glow con soglia
   bassa (1.15): l'intonaco chiaro col sole in faccia andava a martellare sulle alte luci e
   attivava il bloom.
7. **Assenza di profondità a distanza.** Solo foschia esponenziale: le colline lontane non
   "entravano" nel cielo e la valle non tratteneva una foschia d'aria.

## 2. La giornata di riferimento

Direzione luminosa coerente con una **giornata fantasy medievale**: luce chiave calda da est
a sud a ovest (il ciclo esistente), golden hour lunga ai due estremi, mezzogiorno chiaro e
neutro-caldo, notte fredda e leggibile con una luna fissa.

| Ora circa | Sole | Cielo | Foschia | Lettura |
| --- | --- | --- | --- | --- |
| 05:30 | orizzonte, oro | orizzonte caldo, zenith blu | scatter solare | alba lunga |
| 08:00 | 31°, caldo-neutro | blu pieno | leggera | mattino pieno |
| 12:00 | 62°, neutro-caldo | blu, orizzonte crema | minima | massimo contrasto |
| 17:30 | basso, oro | orizzonte caldo | scatter solare | pomeriggio dorato |
| 18:30 | sotto l'orizzonte | afterglow caldo (coda) | quieta | tramonto che sfuma |
| 20:30 | luna (54°, fissa) | blu notte, non nero | sottile | notte leggibile |
| 23:00 | luna piena | blu notte | sottile | silhouette + finestre accese |

Le curve chiave sono tre funzioni pure e testate di `SkyRig`:

* `horizon_glow(elevazione)` — l'accento caldo della golden hour: picco con il sole a ~6°,
  scompare verso +28°, e ha una **coda di afterglow** ~16° sotto l'orizzonte;
* `sun_warmth(elevazione)` — il calore del sole a **ogni** ora: a mezzogiorno neutro-caldo, in
  mattina e pomeriggio progressivamente più caldo, così la giornata non è una copia di sé
  stessa tra le 8:30 e le 15:30;
* `moon_weight(elevazione)` — la transizione luce solare -> luna: resta a 0 durante tutto il
  tramonto (la luce non deriva mai via dall'orizzonte mentre è visibile) e completa la rotazione
  ~14° sotto l'orizzonte, così di notte la luce non arriva mai dal basso.

## 3. Cosa fa cosa

* **Sole (chiave, unica ombra)** — energia 1.35 di giorno (intonaco chiaro ~0.88 di albedo sotto
  la spalla del filmic: luminoso, mai bruciato), 0.11 di notte come luna fissa a 54° di
  elevazione. Colore: `noon` caldo-neutro a mezzogiorno, progressivamente più caldo con il sole
  basso (`sun_warmth`), `golden` vicino all'orizzonte, `moon` freddo di notte.
  `light_angular_distance = 0.65` (PCSS) per penombre che si allargano con la distanza.
  Il disco del cielo procedurale segue la stessa luce: di notte diventa un disco lunare pallido,
  largo ~4° (era 7-33°: largo e spento).
* **Fill (senza ombre)** — lato anti-solare (azimuth sole + 180°) a 52° di elevazione: le facce
  in ombra ricevono luce leggibile senza appiattire le forme. Energia 0.20 di giorno, **0.36 di
  notte** (di notte è metà della luce disponibile). `sky_mode = LIGHT_ONLY`: non compare mai nel
  cielo.
* **Ambient** — sorgente cielo con `ambient_light_sky_contribution = 0.78` e colore di rimbalzo
  caldo: le ombre sono un mix cielo-blu + rimbalzo-terra, mai grigio piatto e mai nere.
  L'energia sale leggermente di notte (0.55) perché la radianza notturna è già bassa: è il
  "pavimento" anti-nero.
* **Cielo** — `ProceduralSkyMaterial` con palette a due estremi più la banda golden, curve
  (`sky_curve 0.12`, `ground_curve 0.15`) che allargano la fascia d'orizzonte, `use_debanding`
  contro il banding, e `ground_horizon_color` allineato all'orizzonte: nessuna cucitura tra
  cupola e colline.
* **Foschia** — esponenziale (0.0028 giorno / 0.0042 notte: una foschia, non latte), più:
  * `fog_aerial_perspective = 0.4` — la foschia lontana si tinge del cielo reale: le colline si
    dissolvono **dentro** l'orizzonte invece di appoggiarsi sopra;
  * `fog_height_density = 0.22` con `fog_height = 0` — foschia di quota sottile che si raccoglie
    nelle valli e dirada sulle colline (profondità, non effetto);
  * `fog_sun_scatter` animato fino a 0.42 solo con il sole sopra l'orizzonte: il sole che buca la
    foschia alla golden hour.
* **Tone mapping** — filmic invariato, `tonemap_white` 3.2 -> 3.8: spalla più morbida, alte luci
  che non si schiacciano. `ssao_light_affect = 0.0`: l'AO resta nelle ombre di contatto (dà
  "peso" a edifici e oggetti sul terreno) e non sporca le superfici al sole.
* **Glow** — valori precedenti conservati (screen blend, intensity 0.6, soglia 1.15): con il sole
  a 1.35 l'intonaco non supera più la soglia, quindi il bloom resta sulle finestre notturne e
  sui riflessi dell'acqua, dove serve.
* **Glow notturno delle finestre** — il sistema esistente (`VillageMaterials.apply_night_glow`)
  è conservato: scrive due float sui materiali condivisi e si innesta sul nuovo daylight curve.

## 4. Scelte di prestazione (GPU classe GTX 1060)

Ogni effetto è stato valutato sulla scena reale; incluso solo se migliorava il risultato:

| Effetto | Stato | Motivo |
| --- | --- | --- |
| Ombre direzionali (2 split, 128u) | tenuto | una sola ombra: il costo più alto che il rig può pagare |
| PCSS `light_angular_distance` 0.65 | incluso | penombre morbide = volume, costo per-pixel accettabile |
| SSAO | tenuto (valori prec.) | radicamento di oggetti e personaggi sul terreno |
| Glow screen | tenuto (valori prec.) | solo accenti, non bloom invasivo |
| Foschia esponenziale + quota + aerea + scatter | incluso | tutto nel pass della foschia, niente passate volumetriche |
| Foschia volumetrica | **esclusa** | prima cosa fuori budget su 1060 |
| SDFGI / SSIL / SSR | **esclusi** | costo sproporzionato per una scena di questa scala |
| Stelle / nuvole con texture | **esclusi** | il repo è asset-free (solo testo): niente texture, niente shader sky |
| Seconda luce con ombre | **esclusa** | raddoppierebbe il costo delle ombre |

## 5. Dove si toccano i valori

* **Curve e palette dinamiche**: `src/world/environment/sky_rig.gd` (tutte le costanti sono
  commentate con il proprio ruolo).
* **Valori statici dell'ambiente** (tone mapping, SSAO, glow, foschia statica, ambient):
  `src/world/scenes/main_world.tscn`, sub-risorse `Environment` e `ProceduralSkyMaterial`.
* **Sensibilità della curva di luce** (quanto dura la transizione del giorno):
  `DayCycleSystem.DAYLIGHT_SATURATION_ELEVATION_DEG` (`= 22°`, endpoint invariati: 0 a
  mezzanotte, 1 a mezzogiorno).
* **Contratto verificato**: `tests/unit/test_sky_rig.gd` fissa le gerarchie di energia, i pavimenti
  anti-nero, i limiti della foschia e il comportamento delle curve pure, così un cambiamento
  futuro non può riportare ombre nere o bloom invasivo senza far fallire un test.

## 6. Verifica

Eseguita con un build headless di **Godot 4.5-stable** (il target minimo dichiarato dal
progetto), più i controlli statici del repository:

* **Controlli statici** (`tools/check_project.py`, `gdparse`, `gdlint`): OK.
* **Test di unità** (`tests/run_tests.gd`): **1270 superati, 0 falliti** — inclusi
  `tests/unit/test_sky_rig.gd` (energie, pavimenti anti-nero, limiti della foschia, curve pure
  `horizon_glow`, `sun_warmth`, `moon_weight`).
* **Test di integrazione** (`tests/run_world_tests.gd`): **177 superati, 0 falliti** — incluso
  `TestWorldScene.check_lighting`: la scena reale viene percorsa nelle ore di mezzogiorno, golden
  hour, tramonto, notte fonda e alba (la luce non arriva mai dal basso, la notte non è nera, le
  finestre si accendono, la foschia resta leggera) e poi da **5 punti della mappa** (tre strade,
  la piazza e un punto in campagna) con il giocatore appoggiato al terreno.
* **Esecuzione del gioco**: la scena principale viene avviata e fatta girare (villaggio, NPC,
  economia, sociale) senza errori di script.
* **Verifica visiva**: **non eseguita**. L'ambiente di sviluppo non ha GPU né rasterizzatori
  software (i download del motore precompilato e di Mesa sono bloccati): la resa a schermo non
  può essere vista qui. La verifica è quindi **numerica ed eseguibile, non visiva**: i valori
  vanno giudicati a occhio su una macchina con GPU prima di considerare il pass definitivo.

Nota di compatibilità emersa durante la verifica: `building_factory.gd` e
`building_surface_details.gd` usavano inferenze di tipo (`var x := …` su iteratori non tipizzati)
che Godot 4.5 rifiuta, e su 4.5 il villaggio si costruiva **incompleto e silenziosamente** (niente
finestre, dettagli delle facciate, locanda o palazzo). Corretto con tipi espliciti: il progetto
gira ora davvero sul minimo dichiarato, non solo su 4.7.

## 7. Opportunità future (non implementate, di proposito)

Questo pass prepara la strada senza crearla: nessun nuovo sistema temporale è stato introdotto.

1. **Sistema meteo** — `SkyRig` è già il punto di aggancio previsto: pioggia/nebbia possono
   interpolare `FOG_DENSITY_*`, le palette del cielo e l'energia del sole senza toccare la
   simulazione. Il clock ha già il *seed* deterministico a portata di mano.
2. **UI dell'ora e velocità del giorno** — il ciclo è già parametrico
   (`logic_tick_seconds`, `time_scale_presets`): servono solo controlli HUD e un'opzione per
   bloccare l'ora (fotografia/debug).
3. **Stelle e luna con fasi** — con uno `ShaderMaterial` per il cielo (ancora asset-free) o
   `sky_cover` se il progetto accetterà texture; le fasi lunari possono derivare da
   `day_index` già salvato nei save.
4. **GI su preset alti** — SDFGI o probe baked potrebbero dare rimbalzo vero su GPU più grandi;
   il preset "alto" del futuro è il posto giusto, con la 1060 come base.
5. **Foschia volumetrica opzionale** — solo dietro preset di qualità: sulla scena attuale
   migliorerebbe la luce tra gli alberi, ma il budget non c'è.
6. **Ombre 4 split e distanze maggiori** — utili quando il villaggio crescerà oltre i ~130u
   di raggio utile.
7. **Palette HDR per l'acqua** — riflessi sky reali (SSR) sullo stagno dietro preset alto.

## 8. Invarianti da non rompere

* Una sola luce proietta ombre.
* Il Fill non deve mai tornare visibile nel cielo (`sky_mode = LIGHT_ONLY`).
* Le ombre non devono mai raggiungere il nero pieno: serve sempre un pavimento di ambient.
* Niente colori fluorescenti: i rossi/arancioni restano sotto la saturazione dei materiali del
  villaggio.
* Niente nuova scena, nessun nuovo autoload, nessun asset binario.
