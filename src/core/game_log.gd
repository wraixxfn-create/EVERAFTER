class_name GameLog
extends RefCounted
## Minimal leveled logger used by every module.
##
## Why not bare `print()`:
## * one place to raise or lower verbosity while profiling;
## * a small in-memory ring buffer that the UI or a future debug console can
##   show without redirecting stdout;
## * a tag per line, so that once the simulation grows (npcs, economy, history)
##   the output stays readable.
##
## Deliberately tiny on purpose: no threads, no files, no third party logger.

enum Level {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3,
}

const MAX_HISTORY := 128

static var _level: int = Level.INFO
static var _history: PackedStringArray = PackedStringArray()


static func set_level(level: int) -> void:
	_level = clampi(level, Level.DEBUG, Level.ERROR)


static func get_level() -> int:
	return _level


static func debug(tag: String, message: String) -> void:
	_write(Level.DEBUG, tag, message)


static func info(tag: String, message: String) -> void:
	_write(Level.INFO, tag, message)


static func warning(tag: String, message: String) -> void:
	_write(Level.WARNING, tag, message)


static func error(tag: String, message: String) -> void:
	_write(Level.ERROR, tag, message)


## Last [constant MAX_HISTORY] lines, oldest first.
static func history() -> PackedStringArray:
	return _history


static func clear_history() -> void:
	_history = PackedStringArray()


static func level_name(level: int) -> String:
	match level:
		Level.DEBUG:
			return "DEBUG"
		Level.INFO:
			return "INFO"
		Level.WARNING:
			return "WARN"
		Level.ERROR:
			return "ERROR"
		_:
			return "?"


static func _write(level: int, tag: String, message: String) -> void:
	var line := "[%s] %s: %s" % [level_name(level), tag, message]
	_history.append(line)
	while _history.size() > MAX_HISTORY:
		_history.remove_at(0)
	if level >= Level.ERROR:
		push_error(line)
	elif level >= Level.WARNING:
		push_warning(line)
	else:
		print(line)
