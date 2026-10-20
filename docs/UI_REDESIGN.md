# EVERAFTER — Ridisegno dell'interfaccia (UI 2.0)

Questo intervento non aggiunge funzionalità: **ridisegna da capo la presentazione dell'interfaccia**
(`src/ui/`) e ne corregge i difetti strutturali. Nessuna modifica a `src/npcs/`, `src/economy/`,
`src/social/`, `src/history/`, `src/persistence/`, alla scena 3D o al formato di salvataggio.

> Anteprima statica: [`docs/ui_preview.html`](ui_preview.html) (si apre in un browser, nessuna
> dipendenza). È un riferimento di *design*: la scena 3D sullo sfondo è un fondale stilizzato, non
> uno screenshot del motore.

---

## 1. Metodo e limiti dichiarati

**In questo ambiente non esiste un eseguibile Godot** (nessun `godot` in `apt`, nessun binario nel
repository, download bloccato). Di conseguenza:

* non sono stati catturati screenshot dal motore;
* nessuna delle suite headless è stata eseguita;
* la verifica è **statica**: `gdparse`/`gdlint` (gdtoolkit 4.5) su tutti gli script toccati e
  `python3 tools/check_project.py` (che confronta ogni `$Node/Path` degli script con l'albero dei
  `.tscn`, i `res://` e le azioni di input) — tutti verdi.

Il ridisegno è quindi verificato per *coerenza e compilabilità*, non per resa a schermo. Le scelte
estetiche sono descritte qui sotto in modo da poter essere corrette con un singolo file
(`ui_theme.gd`), senza toccare i pannelli.

---

## 2. Difetti individuati (prima del ridisegno)

1. **Pannelli a dimensione fissa con contenuto che li sfonda.** `NpcPanel` aveva un rettangolo
   `offset_bottom = 180` mentre una scheda completa (nome, tratti, obiettivo, tre barre, stato,
   legami, memoria) richiede ~600 px: il testo usciva **fuori** dal riquadro marrone, sopra la
   scena 3D. Lo stesso schema (rect fisso + contenuto variabile) era usato da `EconomyPanel`
   (`138→498`) e `DiagnosticsHud` (`16→264`), quindi bastava una riga di testo in più — o un font
   di sistema con metriche diverse — per rompere il layout.
2. **Palette “marrone su marrone + oro”.** Ogni superficie era lo stesso noce scuro
   (`0.08, 0.065, 0.055`) con bordo ottone a 0.86 di opacità e **doppio bordo** da 2 px sopra e
   sotto: quattro pannelli accostati diventavano un blocco unico, senza gerarchia.
3. **Tipografia rumorosa.** Titoli con finto grassetto (`variation_embolden = 0.22`), sezioni in
   oro a 12 px maiuscolo, corpo a 11–13 px e simboli decorativi sparsi (`◆ ◈ ❖ ▶`) usati come
   punteggiatura. Il risultato leggeva come “debug con un tema”, non come un prodotto.
4. **Densità senza respiro.** Separazioni da 3–6 px, righe di tabella da 13 px, cronaca in un unico
   `Label` colorato: nessuna gerarchia tra dato, etichetta e commento.
5. **Incoerenza tra i pannelli.** La mappa era disegnata a mano con `ThemeDB.fallback_font`, la
   diagnostica aveva un altro stile, il modal Cronache usava un altro raggio e un altro bordo: sei
   linguaggi visivi diversi nello stesso gioco.
6. **Aggiornamenti inutili ogni frame.** `WorldHud` ricostruiva le stesse stringhe 60 volte al
   secondo e `NpcPanel` ricreava gli `StyleBox` delle barre anche quando i valori non cambiavano.

---

## 3. Il sistema di design (`src/ui/ui_theme.gd`)

Quattro regole, applicate da tutti i pannelli:

* **Un inchiostro, un accento.** Superfici quasi nere calde (`BG_PANEL 0.055, 0.052, 0.047` a
  0.94), **un solo bordo da 1 px** (`BORDER_BRASS` a 0.17), ombra morbida da 12 px. L'oro
  (`TEXT_GOLD`, `TEXT_GOLD_DIM`) è riservato al nome del gioco, alle overline di sezione e al
  controllo a fuoco: non è più la cornice di ogni cosa.
* **La gerarchia la porta la tipografia.** Serif (`Constantia → Palatino → Georgia`) solo per
  titoli, nomi e numeri; sans umanista (`Segoe UI → Candara → Inter`) per il testo; **overline a
  10 px, maiuscolo, tracking 2 px** (`overline_font()`) per le sezioni. Niente grassetto finto:
  `variation_embolden` scende da 0.22 a 0.06.
* **Ritmo a 8 punti.** `GAP_XS/S/M/L/XL` = 4/8/12/16/24 e margine schermo 24: padding 16–18,
  separazioni 8–14, larghezze colonna 312 (sinistra) e 344 (destra).
* **Zero asset binari.** Come da `docs/ARCHITECTURE.md`, solo `SystemFont`, `FontVariation` e
  `StyleBoxFlat`.

Nuovi helper condivisi: `style_section_label`, `style_overline_label`, `style_body_label`,
`style_keycap` (i tasti nel banner comandi), `style_chip`/`style_neutral_chip` (pillole di stato),
`style_primary_button`, `make_rule_style`, `make_accent_row_style` (righe di cronaca con barra
colorata a sinistra) e lo stile delle scrollbar.

Colori semantici invariati nelle API (`color_for_energy/hunger/wellbeing/activity`) ma desaturati
per convivere sulla stessa schermata.

---

## 4. Interventi per pannello

### 4.1 `WorldHud` — una sola card, misurata sul contenuto

```
EVERAFTER
Giorno 1 · 09:24
[ Mattino ]  [ ×1 ]
Campi di Everafter
```

* Un'unica card in alto a sinistra (312 px) con titolo serif in oro, orologio serif grande, chip di
  fase e velocità, area in grigio caldo.
* **Altezza calcolata** (`_fit()`) da `get_combined_minimum_size()`: il testo non può più uscire dal
  pannello, qualunque font risolva il sistema.
* Banner comandi in basso con veri **keycap** (`F`, `C`, `P`, `+ −`, `M`), visibile solo a mouse
  libero; mirino centrale ridisegnato come anello sottile + punto, non più un glifo.
* `_process` aggiorna le etichette **solo quando il testo cambia** (giorno/ora, fase, velocità).

### 4.2 `EconomyPanel` — un registro, non una tabella di debug

* Intestazione overline `ECONOMIA`, sottotitolo a 11 px, filetto, poi quattro righe
  `risorsa · scorta · bilancio`; i numeri usano il serif a 17 px e i flussi restano verdi/ambra/rosa
  secondo il saldo.
* Carenze e progetti su due righe leggibili, cronaca degli scambi in 11 px, divisori sottili.
* **Gli identificatori pubblici e i formati di testo sono rimasti identici** (`"Carenze: …"`,
  `"Progetti: …"`, `"+prod / -cons"`, importi interi): l'integrazione `test_world_scene` continua a
  leggere gli stessi valori.
* Altezza calcolata dal contenuto e limitata allo spazio disponibile.

### 4.3 `NpcPanel` — scheda a colonna con dossier scorrevole

* Header `ABITANTI · 10`, selettore compatto (`Scegli un abitante…`), filetto, **nome serif 19**,
  riga professione/età/umore/turno a 11 px, attività come pillola colorata.
* **Bisogni sempre visibili** con barre da 6 px (prima 14 px) e valori allineati; **dossier**
  (indole, obiettivo, stato, legami, memoria) dentro uno `ScrollContainer` alto al massimo il 46%
  dello schermo.
* Senza selezione la card collassa in tre righe; con selezione cresce fino a un tetto calcolato,
  **mai oltre lo schermo**.
* Le stringhe esposte a `test_world_scene` (`get_displayed_name/activity/goal/summary/relations/
  memories`, `get_displayed_energy`) non cambiano; le barre si aggiornano solo quando i valori
  interi cambiano.

### 4.4 `SaveLoadPanel` — l'archivio del villaggio

* Modal 620×680 centrato, overline `ARCHIVIO DEL VILLAGGIO`, titolo serif, stato del salvataggio in
  grigio.
* Filtri con etichette overline, cronaca in **schede a due righe** (riassunto + `Giorno · ora ·
  categoria`) con barra colorata per categoria, pulsante primario `Salva adesso` in oro caldo.
* Lo sfondo del modal è più neutro e l'overlay più scuro, così il pannello si stacca dal mondo.

### 4.5 `DiagnosticsHud` — una placca tecnica

Titolo overline con build, filetto, righe in **monospace 11 px** (`Giorno`, `Ora`, `Tick`,
`Velocità`, `Fase`, `FPS`), stato in grigio. Larghezza 380, altezza misurata, in alto al centro
senza sovrapporsi agli altri pannelli.

### 4.6 `WorldMap` — stessa lingua degli altri pannelli

Card centrata con `StyleBoxFlat` arrotondato (non più `draw_rect` nudi), overline, titolo serif,
filetto, griglia a coordinate, marcatori con alone (player con anello e punto), legenda e chip
`M o Esc` per chiudere.

---

## 5. Regole di layout (per non ricadere nel problema 2.1)

1. Nessun pannello usa più un'altezza fissa: ogni card chiama `_fit()` in `_ready` (differito),
   quando il contenuto cambia e al `size_changed` del viewport.
2. Il contenuto lungo va in uno `ScrollContainer` con `custom_minimum_size.y` limitato a una
   frazione dello schermo.
3. Le posizioni sono ancore + margine 24 (`LEFT_COLUMN_STACK_TOP` per la seconda card di sinistra),
   non coordinate scritte a mano per ogni risoluzione.
4. Tutti i colori, i raggi e le spaziature vengono da `UiTheme`: cambiare il tema cambia l'intero
   gioco.

---

## 6. Verifiche eseguite

| Controllo | Esito |
| --- | --- |
| `gdparse` su `ui_theme.gd`, `world_hud.gd`, `economy_panel.gd`, `npc_panel.gd`, `save_load_panel.gd`, `diagnostics_hud.gd`, `world_map.gd` | OK |
| `gdlint` sugli stessi file | 0 problemi |
| `python3 tools/check_project.py` | `RESULT: OK` (nodi, `res://`, azioni, `.gitignore`) |
| Suite headless Godot | **non eseguita**: motore non disponibile in questo ambiente |
| Screenshot dal motore | **non acquisiti**: motore non disponibile in questo ambiente |

I formati di testo letti dai test di integrazione sono preservati, ma la suite va rieseguita su una
macchina con Godot prima del merge.
