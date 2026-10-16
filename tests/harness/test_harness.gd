class_name TestHarness
extends RefCounted
## Minimal assertion harness for the headless test suite.
##
## Deliberately not a third party framework: the project must stay runnable
## offline with nothing but the engine installed, and the checks needed today
## are a dozen lines of code. If the suite grows, replacing this file with GUT
## is a local change (see `docs/ROADMAP.md`).
##
## Results are counted in three buckets: passed, failed and skipped. A skipped
## check is printed loudly and is never counted as a pass.

var passed_count: int = 0
var skipped_reasons: PackedStringArray = []
var failure_messages: PackedStringArray = []

var _suite_name := ""


func suite(suite_name: String) -> void:
	_suite_name = suite_name
	print("--- %s" % suite_name)


func check(condition: bool, description: String) -> void:
	if condition:
		passed_count += 1
	else:
		_record_failure(description)


func check_equals(actual: Variant, expected: Variant, description: String) -> void:
	if actual == expected:
		passed_count += 1
	else:
		_record_failure("%s — expected %s, got %s" % [description, expected, actual])


func check_not_equals(actual: Variant, unexpected: Variant, description: String) -> void:
	if actual != unexpected:
		passed_count += 1
	else:
		_record_failure("%s — value should not be %s" % [description, unexpected])


func check_almost(actual: float, expected: float, tolerance: float, description: String) -> void:
	if absf(actual - expected) <= tolerance:
		passed_count += 1
	else:
		_record_failure(
			"%s — expected %s (+/-%s), got %s" % [description, expected, tolerance, actual]
		)


## Records a check that could not be executed in this environment (for example
## because it needs a real rendering backend). Reported, never counted as passed.
func skip(description: String) -> void:
	skipped_reasons.append("%s: %s" % [_suite_name, description])


func failed_count() -> int:
	return failure_messages.size()


func succeeded() -> bool:
	return failure_messages.is_empty()


func print_summary() -> void:
	print("")
	print("==========================================================")
	for reason in skipped_reasons:
		print("SKIP  %s" % reason)
	for message in failure_messages:
		print("FAIL  %s" % message)
	print("----------------------------------------------------------")
	print(
		"passed: %d   failed: %d   skipped: %d"
		% [passed_count, failure_messages.size(), skipped_reasons.size()]
	)
	if succeeded():
		print("RESULT: OK")
	else:
		print("RESULT: FAILURES")
	print("==========================================================")


func _record_failure(description: String) -> void:
	failure_messages.append("%s: %s" % [_suite_name, description])
