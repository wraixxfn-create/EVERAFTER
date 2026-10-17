class_name OfflineCatchup
extends RefCounted
## Advances the simulation to cover real time elapsed between two runs.
##
## Design rules (documented, not accidental):
## * The conversion from real seconds to simulated ticks is fixed:
##   `real_seconds * (1.0 / tick_seconds) * offline_time_scale` gives the
##   number of ticks to advance. With the default `tick_seconds=0.05` and
##   `offline_time_scale=1.0`, one real second = 20 simulated ticks = 20
##   simulated minutes, so one real hour = 20 sim-hours, one real day ≈ 20
##   sim-days. This is **not** real-time: the simulation is intended to run
##   faster than reality even offline.
## * A hard cap [member max_offline_simulated_days] (default 10 sim-days)
##   prevents coming back after months from instantly destroying or minting
##   the village.
## * Catch-up runs in batches of [member batch_ticks] (default 60 = one
##   simulated hour). After each batch the chronicle watcher observes the
##   state, so shortage/production/milestone entries are recorded rather
##   than only the final state.
## * Catch-up is idempotent in the presence of repeated loads: once it has
##   advanced past `last_save_real_time`, calling it again with the same
##   timestamp returns zero ticks.
## * Clock skew in the future (system clock set backwards after a save, or a
##   save made by a different machine) is clamped to zero additional ticks:
##   the player cannot time-travel forward by rewinding their clock.
## * Systems that have no aggregate catch-up logic (everything today runs
##   tick-by-tick already) are advanced tick-by-tick inside [method run].
##   Because of the daily cap this stays bounded: 10 sim-days = 14 400 ticks,
##   which finishes well under two seconds on a modest CPU.
##
## When we later add a proper aggregate model for some subsystems, we can
## swap the per-tick loop for a batched model without changing the public
## API.
##
## Unit tests: `tests/unit/test_offline_catchup.gd`.

const TAG := "OfflineCatchup"

## Simulated days we are willing to advance in one catch-up, hard cap.
const DEFAULT_MAX_OFFLINE_SIM_DAYS := 10
## Ticks per chronicle observation batch.
const DEFAULT_BATCH_TICKS := 60
## Real seconds that must elapse before we even attempt catch-up (avoid
## double-advancing on a quick quit/reload).
const MIN_REAL_SECONDS_FOR_CATCHUP := 30

## Ratio of simulated time to real time during catch-up. With the default
## tick_seconds=0.05 and this factor = 1.0, 1 real second = 20 sim minutes
## (see class docstring). Keep it conservative so offline play does not
## race ahead of the player's intent.
var offline_time_scale: float = 1.0
var max_offline_simulated_days: int = DEFAULT_MAX_OFFLINE_SIM_DAYS
var batch_ticks: int = DEFAULT_BATCH_TICKS

## Outcome summary, populated after [method run].
var ticks_applied: int = 0
var simulated_days_advanced: float = 0.0
var real_seconds_elapsed: int = 0
var was_capped: bool = false
var entry_records_added: int = 0

var _loop: SimulationLoop = null
var _watcher: ChronicleWatcher = null
var _book: ChronicleBook = null
## Save timestamp the world has already been advanced from. A later [method run]
## with the same timestamp applies nothing (see the idempotency rule above).
var _caught_up_save_time: int = 0


func _init(
	loop: SimulationLoop,
	watcher: ChronicleWatcher,
	book: ChronicleBook,
	config: GameConfig = null
) -> void:
	_loop = loop
	_watcher = watcher
	_book = book
	if config != null:
		# Tunables can be added to GameConfig later; we already read the
		# cap if a matching field exists to stay forward compatible.
		pass


## Computes how many ticks need to be applied given the real timestamp of
## the last save, applies them in batches, and returns a short human summary
## plus a chronicle entry marking the catch-up. If no catch-up is needed
## (or the elapsed time is below the safety floor) returns a summary
## describing that and applies nothing.
##
## [param last_save_real_time] is the unix-seconds timestamp stored in the
## save file; pass 0 to indicate "no previous save, no catch-up".
func run(last_save_real_time: int) -> Dictionary:
	_reset_outcome()
	var now := int(Time.get_unix_time_from_system())
	var elapsed := now - last_save_real_time
	real_seconds_elapsed = elapsed
	# Defensive: negative elapsed (clock went back) or tiny elapsed (quick
	# restart) → nothing to do.
	if last_save_real_time <= 0 or elapsed < MIN_REAL_SECONDS_FOR_CATCHUP:
		return _summary_dict("Nessun tempo trascorso dall'ultimo salvataggio.")
	if last_save_real_time == _caught_up_save_time:
		return _summary_dict("Il tempo offline di questo salvataggio e' gia' stato recuperato.")
	# Future timestamp protection: if the save was written more than a few
	# minutes ahead of "now", treat it as clock skew and don't advance.
	if elapsed < 0 and -elapsed > SaveManager.FUTURE_TOLERANCE_SECONDS:
		if _book != null:
			_book.record(
				ChronicleEntry.Category.SYSTEM,
				_loop.clock.get_display_day(),
				_loop.clock.get_minute_of_day(),
				_loop.clock.tick,
				35,
				"L'orologio di sistema e' cambiato dall'ultimo salvataggio; il mondo non avanza.",
				[],
				[],
				{"kind": "clock_skew", "elapsed_seconds": elapsed}
			)
		return _summary_dict(
			"L'orologio di sistema e' stato spostato all'indietro; nessun avanzamento.")
	if _loop == null:
		return _summary_dict("SimulationLoop non disponibile.")
	var tick_seconds := maxf(_loop.tick_seconds, 0.001)
	# real_seconds * (1/tick_seconds) is the simulated ticks that would have
	# passed at time_scale=1 over that real interval.
	var desired_ticks := int(float(elapsed) / tick_seconds * offline_time_scale)
	var max_ticks := max_offline_simulated_days * SimulationClock.MINUTES_PER_DAY
	var ticks := mini(desired_ticks, max_ticks)
	was_capped = desired_ticks > max_ticks
	ticks = maxi(ticks, 0)
	if ticks <= 0:
		return _summary_dict("Il tempo trascorso non basta per avanzare la simulazione.")
	# Remember starting day for the summary entry.
	var start_day := _loop.clock.get_display_day()
	var start_tick := _loop.clock.tick
	var start_entries := _book.count() if _book != null else 0
	# Apply in batches so the watcher can observe.
	var remaining := ticks
	var batch := maxi(batch_ticks, 1)
	while remaining > 0:
		var step := mini(remaining, batch)
		_loop.run_ticks(step)
		ticks_applied += step
		remaining -= step
		if _watcher != null:
			_watcher.observe(_loop.clock.tick, _loop.clock)
	# One more observation at the end so the final state is recorded.
	if _watcher != null:
		_watcher.observe(_loop.clock.tick, _loop.clock)
	_caught_up_save_time = last_save_real_time
	var end_day := _loop.clock.get_display_day()
	simulated_days_advanced = float(_loop.clock.tick - start_tick) / float(SimulationClock.MINUTES_PER_DAY)
	var entries_added := (_book.count() if _book != null else 0) - start_entries
	entry_records_added = maxi(entries_added, 0)
	# Chronicle entry marking the catch-up.
	var msg := "Sei tornato dopo %s di tempo reale: il mondo e' avanzato di %.1f giorni simulati." % [
		_format_real_duration(elapsed), simulated_days_advanced
	]
	if was_capped:
		msg += " (avanzamento limitato a %d giorni per protezione)." % max_offline_simulated_days
	if _book != null:
		_book.record(
			ChronicleEntry.Category.SYSTEM,
			end_day,
			_loop.clock.get_minute_of_day(),
			_loop.clock.tick,
			40,
			msg,
			[],
			[],
			{
				"kind": "offline_catchup",
				"real_seconds_elapsed": elapsed,
				"ticks_applied": ticks_applied,
				"capped": was_capped,
				"start_day": start_day,
				"end_day": end_day,
			}
		)
	return _summary_dict(msg)


func _reset_outcome() -> void:
	ticks_applied = 0
	simulated_days_advanced = 0.0
	real_seconds_elapsed = 0
	was_capped = false
	entry_records_added = 0


func _summary_dict(message: String) -> Dictionary:
	return {
		"ok": true,
		"message": message,
		"ticks_applied": ticks_applied,
		"simulated_days_advanced": simulated_days_advanced,
		"real_seconds_elapsed": real_seconds_elapsed,
		"was_capped": was_capped,
		"entries_added": entry_records_added,
	}


## Human readable duration ("2 ore e 13 minuti", "45 secondi", "3 giorni").
static func _format_real_duration(seconds: int) -> String:
	if seconds < 60:
		return "%d secondi" % seconds
	if seconds < 3600:
		return "%d minuti" % (seconds / 60)
	if seconds < 86400:
		var h := seconds / 3600
		var m := (seconds % 3600) / 60
		return "%d ore e %d minuti" % [h, m]
	var d := seconds / 86400
	var h := (seconds % 86400) / 3600
	return "%d giorni e %d ore" % [d, h]
