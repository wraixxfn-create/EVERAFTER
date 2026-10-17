class_name ResourceType
extends RefCounted
## Canonical resource identifiers, Italian display names, base exchange prices
## and minimum safety thresholds for the village economy.
##
## Every resource quantity and unit price in this phase is represented as a
## non-negative integer (`int`), which avoids floating-point rounding drift in
## transfers, trades and multi-day balances.

const FOOD := "food"
const WOOD := "wood"
const STONE := "stone"
const COIN := "coin"

const ALL_IDS := [FOOD, WOOD, STONE, COIN]
const MATERIAL_IDS := [FOOD, WOOD, STONE]

## Documented base unit prices expressed in `coin`.
const PRICE_FOOD := 2
const PRICE_WOOD := 3
const PRICE_STONE := 4
const PRICE_COIN := 1

## Minimum village stockpile before the economy flags a low-reserve warning.
const SHORTAGE_FOOD := 8
const SHORTAGE_WOOD := 4
const SHORTAGE_STONE := 4
const SHORTAGE_COIN := 6


static func is_valid(resource_id: String) -> bool:
	return ALL_IDS.has(resource_id)


static func is_material(resource_id: String) -> bool:
	return MATERIAL_IDS.has(resource_id)


static func all_ids() -> PackedStringArray:
	return PackedStringArray(ALL_IDS)


static func material_ids() -> PackedStringArray:
	return PackedStringArray(MATERIAL_IDS)


static func label_for(resource_id: String) -> String:
	match resource_id:
		FOOD:
			return "Cibo"
		WOOD:
			return "Legno"
		STONE:
			return "Pietra"
		COIN:
			return "Moneta"
		_:
			return "Sconosciuta"


static func base_price(resource_id: String) -> int:
	match resource_id:
		FOOD:
			return PRICE_FOOD
		WOOD:
			return PRICE_WOOD
		STONE:
			return PRICE_STONE
		COIN:
			return PRICE_COIN
		_:
			return 0


static func shortage_threshold(resource_id: String) -> int:
	match resource_id:
		FOOD:
			return SHORTAGE_FOOD
		WOOD:
			return SHORTAGE_WOOD
		STONE:
			return SHORTAGE_STONE
		COIN:
			return SHORTAGE_COIN
		_:
			return 0
