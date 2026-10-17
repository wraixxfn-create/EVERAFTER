class_name SaveManager
extends RefCounted
## Reads and writes versioned save files for the simulation.
##
## Responsibilities:
## * Own the single save format (`save_format_version` from `GameConfig`).
## * Serialize the clock, loop config, every registered system (NPCs, economy,
##   social), the chronicle book and the chronicle watcher snapshots into one
##   JSON document on `user://` (the only Godot path that works reliably in
##   an exported build on Windows, macOS and Linux).
## * Write atomically: write to a temporary file, flush, then rename over the
##   real save path. A failure mid-write never destroys the previous save.
## * Keep a small backup (`.bak`) of the previous save as a second safety net.
## * Load safely: reject missing/corrupt/version-mismatched files with
##   human-readable messages and leave the world in the "new world" state.
## * Track the wall-clock time of the last save so the offline progress
##   system can compute elapsed real time.
##
## The manager does NOT tick and does NOT decide when to save; that is the
## caller's job (the `Game` autoload + UI). It only provides a small, pure,
## easily tested surface.
##
## Why JSON:
## * Text, diffable, inspectable with any editor.
## * Godot 4 has `JSON.parse_string` / `JSON.stringify` built in, and the
##   project's `JsonCodec` helper turns Vector2/Color/packed arrays into
##   JSON-safe dictionaries.
## * Schema evolution is explicit via `save_format_version`; future formats
##   can migrate or refuse to load cleanly.
## * Binary blobs give no advantage at the current world size (<200 KB).
##
## Unit tests: `tests/unit/test_save_manager.gd`.

const TAG := "SaveManager"

## Increment when the on-disk schema changes. Load must refuse earlier
## versions that cannot be migrated.
const SUPPORTED_FORMAT_VERSION := 1

const DEFAULT_SAVE_FILE := "everafter_save.json"
const TMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"
## Cap for the recorded real-time timestamp: any value more than this many
## seconds into the future is treated as clock-manipulation and clamped.
const FUTURE_TOLERANCE_SECONDS := 5 * 60

## Errors returned by [method save_to_file] and [method load_from_file].
enum Error {
	OK = 0,
	FILE_NOT_FOUND = 1,
	READ_FAILED = 2,
	NOT_JSON = 3,
	NOT_OBJECT = 4,
	VERSION_MISSING = 5,
	VERSION_UNSUPPORTED = 6,
	CONTENT_MISSING = 7,
	SYSTEM_LOAD_FAILED = 8,
	WRITE_FAILED = 9,
	RENAME_FAILED = 10,
	WORLD_NOT_READY = 11,
}

var save_directory: String = "user://"
var save_filename: String = DEFAULT_SAVE_FILE
var config: GameConfig = null

## References to the systems that own the simulation state. The manager
## never constructs them: they are injected after the world builds.
var loop: SimulationLoop = null
var npc_system: NpcSimulationSystem = null
var economy_system: EconomySystem = null
var social_system: SocialSystem = null
var chronicle_book: ChronicleBook = null
var chronicle_watcher: ChronicleWatcher = null

## Populated after a save/load; surfaced to the UI so the user can see when
## the last save was written. Unix seconds, 0 if never saved.
var last_save_real_time: int = 0
var last_save_simulated_day: int = 0
var last_save_simulated_time_text: String = ""
var last_load_status: String = ""
## Number of NPC records at the moment of saving. Used to build the right
## roster size when loading (avoids loading a 16-NPC save into a world that
## has been configured with a smaller population, which would lose records).
var last_save_population: int = 0


func _init(game_config: GameConfig) -> void:
	config = game_config


# --- public API --------------------------------------------------------------


## Returns the full path to the primary save file (inside [member save_directory]).
func save_path() -> String:
	return _join_path(save_directory, save_filename)


func backup_path() -> String:
	return save_path() + BACKUP_SUFFIX


func tmp_path() -> String:
	return save_path() + TMP_SUFFIX


## True when a save file exists on disk.
func has_save_file() -> bool:
	return FileAccess.file_exists(save_path()) or FileAccess.file_exists(backup_path())


## The population size stored in the save (if any). Returns 0 when no save
## exists or the population field is missing.
func read_saved_population() -> int:
	var text := _read_text_file(save_path())
	if text.is_empty():
		text = _read_text_file(backup_path())
	if text.is_empty():
		return 0
	var decoded := _safe_parse(text)
	if decoded == null or typeof(decoded) != TYPE_DICTIONARY:
		return 0
	var d: Dictionary = decoded as Dictionary
	var version := int(d.get("save_format_version", 0))
	if version != SUPPORTED_FORMAT_VERSION:
		return 0
	return int(d.get("population", 0))


## Writes the current simulation state to disk. Returns [constant Error.OK]
## on success or one of the other error codes on failure. On failure the
## previous save is preserved.
func save_to_file() -> int:
	if not _ready_to_save():
		GameLog.error(TAG, "salvataggio impossibile: sistemi non pronti.")
		return Error.WORLD_NOT_READY
	var data := _build_save_dictionary()
	var json_text := JsonCodec.to_json(data)
	if json_text.is_empty():
		GameLog.error(TAG, "codifica JSON fallita.")
		return Error.WRITE_FAILED
	# Atomic write: tmp -> rename.
	if not _write_text_file(tmp_path(), json_text):
		GameLog.error(TAG, "impossibile scrivere il file temporaneo.")
		return Error.WRITE_FAILED
	# Move current save to .bak (best-effort; absence of .bak is not fatal).
	if FileAccess.file_exists(save_path()):
		DirAccess.remove_absolute(backup_path())
		DirAccess.rename_absolute(save_path(), backup_path())
	if not DirAccess.rename_absolute(tmp_path(), save_path()):
		GameLog.error(TAG, "impossibile sostituire il salvataggio precedente.")
		return Error.RENAME_FAILED
	last_save_real_time = _real_now_seconds()
	last_save_simulated_day = loop.clock.get_display_day()
	last_save_simulated_time_text = loop.clock.get_time_text()
	last_save_population = npc_system.get_record_count()
	GameLog.info(
		TAG,
		"salvataggio scritto su %s (giorno %d %s)."
		% [save_path(), last_save_simulated_day, last_save_simulated_time_text]
	)
	return Error.OK


## Loads the save from disk and pushes its state into the already-built
## world systems. The systems must already be constructed and registered in
## [member loop] (i.e. the world scene must have finished `_ready`). Returns
## a tuple of (error_code, message). On error the world state is untouched.
func load_from_file() -> Array:
	if loop == null or npc_system == null or economy_system == null or social_system == null:
		return [Error.WORLD_NOT_READY, "Sistemi non pronti per il caricamento."]
	var primary_ok := FileAccess.file_exists(save_path())
	var path := save_path()
	if not primary_ok:
		if FileAccess.file_exists(backup_path()):
			path = backup_path()
			GameLog.warning(TAG, "file principale mancante, uso il backup.")
		else:
			return [Error.FILE_NOT_FOUND, "Nessun salvataggio trovato."]
	var text := _read_text_file(path)
	if text.is_empty():
		return [Error.READ_FAILED, "Impossibile leggere il salvataggio."]
	var decoded := _safe_parse(text)
	if decoded == null or typeof(decoded) != TYPE_DICTIONARY:
		return [Error.NOT_JSON, "Il file non e' un JSON valido."]
	var data: Dictionary = decoded as Dictionary
	var version_val: Variant = data.get("save_format_version", null)
	if version_val == null:
		return [Error.VERSION_MISSING, "Salvataggio senza versione: impossibile caricarlo."]
	var version := int(version_val)
	if version != SUPPORTED_FORMAT_VERSION:
		return [
			Error.VERSION_UNSUPPORTED,
			"Versione del salvataggio non supportata (attesa %d, trovata %d)."
			% [SUPPORTED_FORMAT_VERSION, version],
		]
	var content: Variant = data.get("content", null)
	if typeof(content) != TYPE_DICTIONARY:
		return [Error.CONTENT_MISSING, "Contenuto del salvataggio mancante."]
	var err := _validate_content(content as Dictionary)
	if err != Error.OK:
		return [err, "Lo stato salvato non e' coerente."]
	var apply_msg := _apply_to_world(data)
	last_save_real_time = int(data.get("saved_at_real_unix", 0))
	last_save_simulated_day = loop.clock.get_display_day()
	last_save_simulated_time_text = loop.clock.get_time_text()
	last_save_population = int(data.get("population", npc_system.get_record_count()))
	last_load_status = "Caricato dal giorno %d %s." % [
		last_save_simulated_day, last_save_simulated_time_text
	]
	GameLog.info(TAG, last_load_status)
	return [Error.OK, apply_msg]


## Returns a human readable label for an error code.
static func error_label(code: int) -> String:
	match code:
		Error.OK: return "OK"
		Error.FILE_NOT_FOUND: return "File non trovato"
		Error.READ_FAILED: return "Lettura fallita"
		Error.NOT_JSON: return "JSON non valido"
		Error.NOT_OBJECT: return "Formato non valido (non e' un oggetto)"
		Error.VERSION_MISSING: return "Versione mancante"
		Error.VERSION_UNSUPPORTED: return "Versione non supportata"
		Error.CONTENT_MISSING: return "Contenuto mancante"
		Error.SYSTEM_LOAD_FAILED: return "Caricamento di un sistema fallito"
		Error.WRITE_FAILED: return "Scrittura fallita"
		Error.RENAME_FAILED: return "Sostituzione fallita"
		Error.WORLD_NOT_READY: return "Mondo non pronto"
	return "Errore sconosciuto"


# --- internals ---------------------------------------------------------------


func _ready_to_save() -> bool:
	return loop != null \
		and npc_system != null \
		and economy_system != null \
		and social_system != null \
		and chronicle_book != null \
		and chronicle_watcher != null


func _build_save_dictionary() -> Dictionary:
	var real_now := _real_now_seconds()
	return {
		"save_format_version": SUPPORTED_FORMAT_VERSION,
		"saved_at_real_unix": real_now,
		"saved_at_simulated_day": loop.clock.get_display_day(),
		"saved_at_simulated_minute": loop.clock.get_minute_of_day(),
		"population": npc_system.get_record_count() if npc_system != null else 0,
		"build_label": config.build_label if config != null else "",
		"content": {
			"loop": loop.to_dict(),
			"npc_system": npc_system.to_dict(),
			"economy_system": economy_system.to_dict(),
			"social_system": social_system.to_dict(),
			"chronicle_book": chronicle_book.to_dict() if chronicle_book != null else {},
			"chronicle_watcher": chronicle_watcher.to_dict() if chronicle_watcher != null else {},
		},
	}


func _validate_content(content: Dictionary) -> int:
	for required_key in ["loop", "npc_system", "economy_system", "social_system"]:
		if typeof(content.get(required_key, null)) != TYPE_DICTIONARY:
			return Error.CONTENT_MISSING
	return Error.OK


func _apply_to_world(data: Dictionary) -> String:
	var content: Dictionary = data.get("content", {}) as Dictionary
	# Order matters: loop first (restores clock), then NPCs (the records
	# economy and social reference), then economy (refers to NPCs), then
	# social (refers to NPCs and economy), finally chronicle (reads the
	# restored world).
	loop.from_dict(content.get("loop", {}))
	npc_system.from_dict(content.get("npc_system", {}))
	economy_system.from_dict(content.get("economy_system", {}))
	social_system.from_dict(content.get("social_system", {}))
	if chronicle_book != null:
		chronicle_book.from_dict(content.get("chronicle_book", {}))
		var known: Dictionary = {}
		for record in npc_system.get_records():
			known[record.id] = true
		chronicle_book.remove_subject_orphans(known)
	if chronicle_watcher != null:
		chronicle_watcher.from_dict(content.get("chronicle_watcher", {}))
		# If the watcher snapshot is missing (save from before watcher
		# state was stored), seed it from the current economy so that
		# observing right after load does not fire spurious shortages.
		var wd: Dictionary = content.get("chronicle_watcher", {}) as Dictionary
		if wd.is_empty() or not wd.has("prev_food"):
			chronicle_watcher.initialize(loop.clock)
	return "Giorno %d %s — %d voci di cronaca." % [
		loop.clock.get_display_day(),
		loop.clock.get_time_text(),
		chronicle_book.count() if chronicle_book != null else 0,
	]


func _write_text_file(path: String, text: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.flush()
	var ok := f.get_error() == OK
	f.close()
	return ok


func _read_text_file(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var text := f.get_as_text()
	f.close()
	return text


func _safe_parse(text: String) -> Variant:
	var res := JsonCodec.from_json(text)
	var ok: bool = res[0]
	if not ok:
		return null
	return res[1]


func _join_path(directory: String, filename: String) -> String:
	if directory.ends_with("/") or directory.ends_with("\\"):
		return directory + filename
	return directory.rstrip("/") + "/" + filename


## Current wall-clock time as a Unix timestamp in seconds.
func _real_now_seconds() -> int:
	return int(Time.get_unix_time_from_system())
