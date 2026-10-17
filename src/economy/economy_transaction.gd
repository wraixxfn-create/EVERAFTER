class_name EconomyTransaction
extends RefCounted
## Immutable-by-convention record of an economic operation (production,
## consumption, transfer, merchant trade, community project or rejected
## transaction).
##
## Every entry carries the simulated tick, day and formatted clock time so the
## UI and the test suite can inspect the exact history of resource movements.

const KIND_PRODUCTION := "production"
const KIND_CONSUMPTION := "consumption"
const KIND_TRANSFER := "transfer"
const KIND_TRADE := "trade"
const KIND_PROJECT := "project"
const KIND_REJECTED := "rejected"

var id: int = 0
var tick: int = 0
var day: int = 1
var time_text: String = "00:00"
var kind: String = KIND_TRANSFER
var actor_id: String = ""
var from_owner: String = ""
var to_owner: String = ""
var resource_id: String = ""
var amount: int = 0
var coin_amount: int = 0
var success: bool = true
var important: bool = true
var reason: String = ""


func _init(
	initial_id: int = 0,
	initial_tick: int = 0,
	initial_kind: String = KIND_TRANSFER,
	initial_actor_id: String = "",
	initial_from_owner: String = "",
	initial_to_owner: String = "",
	initial_resource_id: String = "",
	initial_amount: int = 0,
	initial_reason: String = ""
) -> void:
	id = initial_id
	tick = maxi(initial_tick, 0)
	day = (tick / SimulationClock.MINUTES_PER_DAY) + 1
	time_text = SimulationClock.format_minutes(tick % SimulationClock.MINUTES_PER_DAY)
	kind = initial_kind
	actor_id = initial_actor_id
	from_owner = initial_from_owner
	to_owner = initial_to_owner
	resource_id = initial_resource_id
	amount = initial_amount
	success = initial_kind != KIND_REJECTED
	important = true
	reason = initial_reason


func format_short() -> String:
	return "[G%d %s] %s" % [day, time_text, reason]


func to_dict() -> Dictionary:
	return {
		"id": id,
		"tick": tick,
		"day": day,
		"time_text": time_text,
		"kind": kind,
		"actor_id": actor_id,
		"from_owner": from_owner,
		"to_owner": to_owner,
		"resource_id": resource_id,
		"amount": amount,
		"coin_amount": coin_amount,
		"success": success,
		"important": important,
		"reason": reason,
	}


func from_dict(data: Dictionary) -> void:
	id = int(data.get("id", id))
	tick = maxi(int(data.get("tick", tick)), 0)
	day = int(data.get("day", (tick / SimulationClock.MINUTES_PER_DAY) + 1))
	time_text = String(
		data.get("time_text", SimulationClock.format_minutes(tick % SimulationClock.MINUTES_PER_DAY))
	)
	kind = String(data.get("kind", kind))
	actor_id = String(data.get("actor_id", actor_id))
	from_owner = String(data.get("from_owner", from_owner))
	to_owner = String(data.get("to_owner", to_owner))
	resource_id = String(data.get("resource_id", resource_id))
	amount = int(data.get("amount", amount))
	coin_amount = int(data.get("coin_amount", coin_amount))
	success = bool(data.get("success", success))
	important = bool(data.get("important", important))
	reason = String(data.get("reason", reason))


func _to_string() -> String:
	return format_short()
