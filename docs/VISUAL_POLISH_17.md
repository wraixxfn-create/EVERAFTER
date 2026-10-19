# EVERAFTER — Visual Polish 17: rocce, massi e integrazione del paesaggio

Intervento mirato sulle rocce già presenti nella mappa: massi sparsi, gruppi di ciottoli sulla riva e affioramenti sulle pendenze. La geometria della mappa e il contratto mesh/collisione del terreno non cambiano. Non sono stati modificati economia, risorse, simulazione o sistemi degli NPC.

## Diagnosi

Le pietre usavano tre linguaggi diversi ma tutti troppo primitivi: alcuni massi erano ellissoidi lobati derivati dalla primitiva della vegetazione, gli affioramenti erano sfere UV schiacciate e i ciottoli del laghetto erano box bassi. Anche quando il colore era corretto, questi profili tendevano a sembrare forme appoggiate sopra il prato, con basi pulite e orientamento indipendente dalla pendenza.

## Intervento

### Geometria e varianti

`MeshBaker.add_rock()` costruisce ora una mesh chiusa a cinque anelli: piede largo e interrato, spalla sfaccettata e sommità troncata. Tre profili deterministici danno una lastra bassa, un masso più alto e una forma oblonga. Ogni seed varia entro limiti espliciti il numero di lati (6–8), la fase, il raggio e il lieve spostamento della sommità. Gli angoli dei vertici restano ordinati; le fasce hanno quote monotone e i due tappi chiudono la mesh. Non si usano perturbazioni non vincolate.

- Costo: **60–80 triangoli per pietra**, con normali per faccia e variazione cromatica leggera.
- Le pietre non riutilizzano più né una sfera né un cubo come silhouette.
- `VegetationBuilder.rock_dimensions()` definisce tre proporzioni leggibili rispetto a un personaggio: lastra larga e bassa, spalla più alta e masso oblungo. La scala resta quella già assegnata dai placement.
- I piccoli sassi diventano gruppi irregolari di 3–4 elementi; i massi maggiori hanno un corpo principale, una scheggia sovrapposta e, occasionalmente, una seconda scheggia. Le sovrapposizioni intenzionali nascondono le cuciture, mentre ogni base parte sotto il livello del terreno.

### Contatto e composizione

- `TerrainGenerator._surface_normal_at()` calcola la normale del **medesimo triangolo** usato da `height_at()` e dalla `HeightMapShape3D`.
- I massi decorativi e i ciottoli della riva orientano la mesh sulla normale locale, campionano l’altezza esatta e penetrano nel terreno con il bordo inferiore. Gli affioramenti ricevono una o due schegge sul lato di valle; ogni scheggia ricampiona quota e normale nel proprio punto.
- I gruppi d’affioramento mantengono distanza da edifici, vegetazione, strade e stagno. Restano decorativi e senza collider.
- I box della riva sono stati sostituiti da sassi sfaccettati bassi, interrati e orientati alla sponda. Non viene aggiunta una collisione al bordo dell’acqua.
- La normale della mesh decorativa non è usata per ruotare il collider preesistente dei massi grandi: il suo ingombro, offset e yaw restano invariati. I ciottoli piccoli e gli affioramenti continuano a essere attraversabili.

### Transizione con il suolo e materiali

- `TerrainGenerator` dipinge un alone morbido di terra compatta e ghiaia intorno ai placement di tipo roccia. Una variazione deterministica rompe il bordo; vicino all’acqua il colore vira lievemente al muschio. L’alone è attenuato su strade, piazza e fondazioni.
- I cordoli e i nastri di pavimentazione già presenti restano quelli di Visual Polish 15: seguono la pendenza e hanno già varchi e margini irregolari. La nuova sfumatura si raccorda al loro terreno senza spostare bordi, allargare percorsi o cambiare collider.
- L’alone cambia **solo i colori dei vertici**. Non sposta il terreno, non altera `HeightMapShape3D`, pendenze, strade o collisioni.
- Si riusano `rock` e `rock_wet` già in palette; nessun materiale o asset esterno nuovo. La pietra asciutta resta opaca (`roughness 0.94`); la pietra umida è appena meno ruvida (`0.82`), senza diventare lucida. Le tinte per faccia restano moderate e dentro la palette esistente.

## Prestazioni e compatibilità

- Le rocce restano fuse per materiale nei mesh già presenti (`Props` e `Vegetation`): nessun nodo o draw call per singolo masso, nessuna texture, shader, particella o luce aggiunta.
- Il contributo geometrico per roccia è limitato a 60–80 triangoli per pezzo; composizioni e ghiaioni condividono gli stessi due materiali.
- Nessuna modifica a `terrain_seed`, dimensioni/altezza della mappa, risorse, economia, input, salvataggi, sistemi degli NPC o regole di placement. Nessuna nuova collisione.

## Verifiche

Eseguite nell’ambiente di lavoro:

| Verifica | Esito |
| --- | --- |
| `python3 tools/check_project.py` | **OK** |
| `gdparse` su tutti i 101 script GDScript | **OK** |
| `gdlint` sui file modificati | **OK** |
| `git diff --check` | **OK** |

Sono stati aggiunti controlli per winding, triangoli degeneri, chiusura/ingombro della roccia, variazione dei seed, budget per cluster, normali e ancoraggio al terreno, alone cromatico senza variazione delle altezze, clearances dalle strade e conservazione esatta del collider esistente. La suite headless e quella d’integrazione **non sono state eseguite**: in questo ambiente non è installato l’eseguibile Godot. Di conseguenza non dichiaro verificati a runtime né il totale effettivo dei triangoli né l’assenza visiva di compenetrazioni o ostacoli in movimento.

Per la revisione manuale in Godot 4.5+, aprire `tests/visual/rock_review.tscn` (oppure avviare con `godot --path . tests/visual/rock_review.tscn`). `1` inquadra l’affioramento più ripido, `2` la riva, `3` il masso placement più grande; frecce per orbitare e rotella per la distanza. La scena usa il terreno e il villaggio deterministici, senza NPC o sistemi di gioco.

## Limiti residui

- Il terreno resta una griglia a celle da 1 m con colore per vertice: la sfumatura di ghiaia è intenzionalmente larga e stilizzata, non una maschera ad alta risoluzione; erba e pietre molto piccole possono ancora incontrarsi vicino al bordo.
- Le pietre sono low-poly senza texture di albedo o normal map; la variazione dipende da silhouette, normali e vertex color.
- Gli affioramenti sono limitati a un massimo di 18 gruppi e possono essere meno numerosi se una zona è occupata. La scena di review stampa il conteggio reale all’avvio.
- Serve ancora una verifica visiva e di movimento nel motore per confermare, sulla build effettiva, che nessuna base sporga, che non ci siano sovrapposizioni evidenti e che le collisioni esistenti non chiudano un passaggio.

## File modificati e asset

| File | Intervento |
| --- | --- |
| `src/world/environment/mesh_baker.gd` | nuova primitiva chiusa `add_rock()` a profili stratificati e variazione limitata |
| `src/world/environment/vegetation_builder.gd` | massi e ciottoli procedurali, tre proporzioni e gruppi; collider grande invariato |
| `src/world/environment/village_builder.gd` | riva sfaccettata, affioramenti inclinati al terreno e schegge a valle; nessun collider aggiunto |
| `src/world/terrain_generator.gd` | normale triangolare esatta e alone cromatico del terreno, solo visivo |
| `src/world/environment/village_materials.gd` | roughness della pietra umida portata a 0.82 |
| `tests/unit/test_mesh_baker.gd` | winding, facce degeneri, interramento, variazione cromatica e seed |
| `tests/unit/test_vegetation.gd` | proporzioni, budget, clearance, contatto col suolo e collider invariato |
| `tests/unit/test_terrain_generator.gd` | normali triangolari, alone e invariabilità delle altezze |
| `tests/unit/test_village_materials.gd` | confronto roughness pietra asciutta/umida |
| `tests/integration/test_world_scene.gd` | censimento entro il budget visuale degli affioramenti e verifica che non aggiungano collider |
| `tests/visual/rock_review.gd`, `tests/visual/rock_review.tscn` | scena di revisione manuale a tre viste |
| `docs/VISUAL_POLISH_17.md` | questo resoconto e i limiti verificati |

Nessun modello, texture o altro asset binario è stato aggiunto.