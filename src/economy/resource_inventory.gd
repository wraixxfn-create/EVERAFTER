class_name ResourceInventory
extends RefCounted
## Validated, non-negative integer inventory of resources (`food`, `wood`,
## `stone`, `coin`).
##
## Every mutating operation (`set_amount`, `add`, `remove`, `add_bundle`,
## `remove_bundle`) validates its arguments *before* touching any counter: a
## rejected call returns `false` and leaves the inventory completely unchanged.

var owner_id: String = ""
var display_name: String = ""

var _amounts: Dictionary = {
	ResourceType.FOOD: 0,
	ResourceType.WOOD: 0,
	ResourceType.STONE: 0,
	ResourceType.COIN: 0,
}


func _init(
	initial_owner_id: String = "",
	initial_display_name: String = "",
	initial_food: int = 0,
	initial_wood: int = 0,
	initial_stone: int = 0,
	initial_coin: int = 0
) -> void:
	owner_id = initial_owner_id
	display_name = initial_display_name
	_amounts = {
		ResourceType.FOOD: maxi(initial_food, 0),
		ResourceType.WOOD: maxi(initial_wood, 0),
		ResourceType.STONE: maxi(initial_stone, 0),
		ResourceType.COIN: maxi(initial_coin, 0),
	}


func get_amount(resource_id: String) -> int:
	if not ResourceType.is_valid(resource_id):
		return 0
	return int(_amounts.get(resource_id, 0))


## Sets a resource quantity when [param resource_id] is valid and [param amount]
## is `>= 0`. Returns `false` without mutating state when invalid.
func set_amount(resource_id: String, amount: int) -> bool:
	if not ResourceType.is_valid(resource_id) or amount < 0:
		return false
	_amounts[resource_id] = amount
	return true


func has_amount(resource_id: String, amount: int) -> bool:
	if not ResourceType.is_valid(resource_id) or amount < 0:
		return false
	return get_amount(resource_id) >= amount


## Adds a positive quantity (`amount > 0`) of a valid resource. Returns `false`
## with no side effects when the resource is unknown or `amount <= 0`.
func add(resource_id: String, amount: int) -> bool:
	if not ResourceType.is_valid(resource_id) or amount <= 0:
		return false
	_amounts[resource_id] = get_amount(resource_id) + amount
	return true


## Removes a positive quantity (`amount > 0`) when the current stock is
## sufficient. Never allows a counter to go below zero.
func remove(resource_id: String, amount: int) -> bool:
	if not ResourceType.is_valid(resource_id) or amount <= 0:
		return false
	var current := get_amount(resource_id)
	if current < amount:
		return false
	_amounts[resource_id] = current - amount
	return true


## True when every entry in [param bundle] is a valid resource with a
## non-negative integer cost and the inventory holds at least that amount.
func has_bundle(bundle: Dictionary) -> bool:
	if bundle.is_empty():
		return false
	for key in bundle.keys():
		var resource_id := String(key)
		var value: Variant = bundle[key]
		if typeof(value) != TYPE_INT:
			return false
		var amount := int(value)
		if not has_amount(resource_id, amount):
			return false
	return true


## Atomically adds all resources in [param bundle]. If any entry is invalid or
## negative, nothing is modified and `false` is returned.
func add_bundle(bundle: Dictionary) -> bool:
	if bundle.is_empty():
		return false
	var has_positive := false
	for key in bundle.keys():
		var resource_id := String(key)
		var value: Variant = bundle[key]
		if not ResourceType.is_valid(resource_id) or typeof(value) != TYPE_INT:
			return false
		var amount := int(value)
		if amount < 0:
			return false
		if amount > 0:
			has_positive = true
	if not has_positive:
		return false
	for key in bundle.keys():
		var resource_id := String(key)
		var amount := int(bundle[key])
		if amount > 0:
			_amounts[resource_id] = get_amount(resource_id) + amount
	return true


## Atomically removes all resources in [param bundle]. If any entry is invalid,
## negative or exceeds current stock, nothing is modified and `false` is
## returned.
func remove_bundle(bundle: Dictionary) -> bool:
	if not has_bundle(bundle):
		return false
	var has_positive := false
	for key in bundle.keys():
		if int(bundle[key]) > 0:
			has_positive = true
	if not has_positive:
		return false
	for key in bundle.keys():
		var resource_id := String(key)
		var amount := int(bundle[key])
		if amount > 0:
			_amounts[resource_id] = get_amount(resource_id) - amount
	return true


func total_materials() -> int:
	return (
		get_amount(ResourceType.FOOD)
		+ get_amount(ResourceType.WOOD)
		+ get_amount(ResourceType.STONE)
	)


func are_all_non_negative() -> bool:
	for resource_id in ResourceType.ALL_IDS:
		if get_amount(resource_id) < 0:
			return false
	return true


func validate() -> PackedStringArray:
	var problems: PackedStringArray = []
	if owner_id.is_empty():
		problems.append("inventory has an empty owner_id")
	for resource_id in ResourceType.ALL_IDS:
		if get_amount(resource_id) < 0:
			problems.append("%s: negative amount for %s" % [owner_id, resource_id])
	return problems


func copy() -> ResourceInventory:
	return ResourceInventory.new(
		owner_id,
		display_name,
		get_amount(ResourceType.FOOD),
		get_amount(ResourceType.WOOD),
		get_amount(ResourceType.STONE),
		get_amount(ResourceType.COIN)
	)


func to_dict() -> Dictionary:
	return {
		"owner_id": owner_id,
		"display_name": display_name,
		"amounts": {
			ResourceType.FOOD: get_amount(ResourceType.FOOD),
			ResourceType.WOOD: get_amount(ResourceType.WOOD),
			ResourceType.STONE: get_amount(ResourceType.STONE),
			ResourceType.COIN: get_amount(ResourceType.COIN),
		},
	}


func from_dict(data: Dictionary) -> void:
	owner_id = String(data.get("owner_id", owner_id))
	display_name = String(data.get("display_name", display_name))
	var amounts_data: Dictionary = data.get("amounts", {})
	for resource_id in ResourceType.ALL_IDS:
		_amounts[resource_id] = maxi(int(amounts_data.get(resource_id, 0)), 0)


func _to_string() -> String:
	return "%s (Cibo %d, Legno %d, Pietra %d, Moneta %d)" % [
		display_name if not display_name.is_empty() else owner_id,
		get_amount(ResourceType.FOOD),
		get_amount(ResourceType.WOOD),
		get_amount(ResourceType.STONE),
		get_amount(ResourceType.COIN),
	]
