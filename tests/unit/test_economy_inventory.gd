class_name TestEconomyInventory
extends RefCounted
## Unit tests for `ResourceType`, `ResourceInventory`, `EconomyTransaction` and
## atomic transfers/trades/projects in `EconomySystem`.
##
## Covers:
## 1. resources never become negative;
## 2. invalid transactions are rejected without side effects or partial state
##    mutations;
## 3. transfers and trades conserve total resources and never duplicate items;
## 4. wood, stone and coin can be spent atomically on community projects.


static func run_tests(harness: TestHarness) -> void:
	harness.suite("EconomyInventory")
	_test_resource_types(harness)
	_test_inventory_non_negative(harness)
	_test_bundles_atomic(harness)
	_test_transfers_and_validation(harness)
	_test_trades_and_conservation(harness)
	_test_community_projects(harness)


static func _test_resource_types(harness: TestHarness) -> void:
	for res_id in [
		ResourceType.FOOD,
		ResourceType.WOOD,
		ResourceType.STONE,
		ResourceType.COIN,
	]:
		harness.check(ResourceType.is_valid(res_id), "resource '%s' is valid" % res_id)
		harness.check(
			ResourceType.base_price(res_id) > 0, "resource '%s' has a positive base price" % res_id
		)
		harness.check(
			not ResourceType.label_for(res_id).is_empty(),
			"resource '%s' has a label" % res_id
		)
	harness.check(not ResourceType.is_valid("mithril"), "unknown resource is rejected")
	harness.check_equals(ResourceType.base_price("mithril"), 0, "unknown resource price is 0")


static func _test_inventory_non_negative(harness: TestHarness) -> void:
	var inv := ResourceInventory.new("test", "Test", -10, -5, 4, -1)
	harness.check_equals(inv.get_amount(ResourceType.FOOD), 0, "negative initial food clamped to 0")
	harness.check_equals(inv.get_amount(ResourceType.WOOD), 0, "negative initial wood clamped to 0")
	harness.check_equals(inv.get_amount(ResourceType.STONE), 4, "positive initial stone kept")
	harness.check_equals(inv.get_amount(ResourceType.COIN), 0, "negative initial coin clamped to 0")
	harness.check(inv.are_all_non_negative(), "all inventory counters are non-negative")

	harness.check(not inv.set_amount(ResourceType.STONE, -3), "set_amount rejects negative value")
	harness.check_equals(
		inv.get_amount(ResourceType.STONE), 4, "failed set_amount leaves stone unchanged"
	)
	harness.check(not inv.add(ResourceType.STONE, -2), "add rejects negative amount")
	harness.check(not inv.add(ResourceType.STONE, 0), "add rejects zero amount")
	harness.check(not inv.add("unknown", 5), "add rejects unknown resource")
	harness.check_equals(inv.get_amount(ResourceType.STONE), 4, "stone still 4 after failed adds")

	harness.check(not inv.remove(ResourceType.STONE, 5), "remove rejects overdraft (5 > 4)")
	harness.check(not inv.remove(ResourceType.STONE, -1), "remove rejects negative amount")
	harness.check(not inv.remove(ResourceType.FOOD, 1), "remove rejects removing from 0")
	harness.check_equals(
		inv.get_amount(ResourceType.STONE), 4, "rejected remove leaves stone at 4"
	)
	harness.check_equals(
		inv.get_amount(ResourceType.FOOD), 0, "rejected remove leaves food at 0"
	)

	harness.check(inv.add(ResourceType.FOOD, 7), "valid add succeeds")
	harness.check(inv.remove(ResourceType.FOOD, 3), "valid remove succeeds")
	harness.check_equals(inv.get_amount(ResourceType.FOOD), 4, "7 - 3 == 4 food")
	harness.check(inv.are_all_non_negative(), "inventory remains non-negative")


static func _test_bundles_atomic(harness: TestHarness) -> void:
	var inv := ResourceInventory.new("village", "Villaggio", 10, 6, 4, 20)
	var before := var_to_str(inv.to_dict())

	var unaffordable := {
		ResourceType.WOOD: 4,
		ResourceType.STONE: 9,
		ResourceType.COIN: 5,
	}
	harness.check(not inv.has_bundle(unaffordable), "has_bundle detects missing stone")
	harness.check(
		not inv.remove_bundle(unaffordable),
		"remove_bundle rejects partially affordable bundle"
	)
	harness.check_equals(
		var_to_str(inv.to_dict()),
		before,
		"failed remove_bundle causes zero partial state change"
	)

	var invalid_bundle := {
		ResourceType.WOOD: 2,
		ResourceType.STONE: -1,
	}
	harness.check(
		not inv.add_bundle(invalid_bundle), "add_bundle rejects bundle with negative entry"
	)
	harness.check_equals(
		var_to_str(inv.to_dict()),
		before,
		"failed add_bundle causes zero partial state change"
	)

	var affordable := {
		ResourceType.WOOD: 4,
		ResourceType.STONE: 3,
		ResourceType.COIN: 5,
	}
	harness.check(inv.remove_bundle(affordable), "affordable bundle is removed atomically")
	harness.check_equals(inv.get_amount(ResourceType.WOOD), 2, "wood reduced by 4")
	harness.check_equals(inv.get_amount(ResourceType.STONE), 1, "stone reduced by 3")
	harness.check_equals(inv.get_amount(ResourceType.COIN), 15, "coin reduced by 5")


static func _test_transfers_and_validation(harness: TestHarness) -> void:
	var records := NpcRoster.build(4)
	var places := NpcPlaceRegistry.new()
	var graph := NpcRouteGraph.new(places, [], [])
	var npc_sys := NpcSimulationSystem.new(records, places, graph)
	var economy := EconomySystem.new(npc_sys, 20, 10, 8, 50)
	economy.initialize(0)

	var snapshot_before := var_to_str(economy.village_inventory.to_dict())
	var npc_before := var_to_str(economy.get_inventory("npc_001").to_dict())

	harness.check(
		not economy.transfer_resource("village", "npc_001", ResourceType.FOOD, 999, 10),
		"transferring more food than available fails"
	)
	harness.check(
		not economy.transfer_resource("village", "npc_001", ResourceType.FOOD, -5, 11),
		"negative transfer fails"
	)
	harness.check(
		not economy.transfer_resource("village", "npc_001", ResourceType.FOOD, 0, 12),
		"zero transfer fails"
	)
	harness.check(
		not economy.transfer_resource("village", "village", ResourceType.FOOD, 2, 13),
		"self-transfer fails"
	)
	harness.check(
		not economy.transfer_resource("village", "npc_999", ResourceType.FOOD, 2, 14),
		"transfer to unknown owner fails"
	)
	harness.check(
		not economy.transfer_resource("village", "npc_001", "gold_bars", 2, 15),
		"transfer of unknown resource fails"
	)
	harness.check_equals(
		var_to_str(economy.village_inventory.to_dict()),
		snapshot_before,
		"village inventory is untouched after all invalid transfers"
	)
	harness.check_equals(
		var_to_str(economy.get_inventory("npc_001").to_dict()),
		npc_before,
		"recipient inventory is untouched after all invalid transfers"
	)
	harness.check_equals(
		economy.rejected_transaction_count,
		6,
		"all six invalid transfers were counted as rejected"
	)

	var total_food_before := EconomyRules.total_system_resource(economy, ResourceType.FOOD)
	harness.check(
		economy.transfer_resource("village", "npc_001", ResourceType.FOOD, 5, 20),
		"valid transfer of 5 Food succeeds"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.FOOD), 15, "village lost 5 Food (20 -> 15)"
	)
	harness.check_equals(
		economy.get_inventory("npc_001").get_amount(ResourceType.FOOD),
		5,
		"npc_001 gained 5 Food (0 -> 5)"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(economy, ResourceType.FOOD),
		total_food_before,
		"transfer never duplicates or destroys resources"
	)


static func _test_trades_and_conservation(harness: TestHarness) -> void:
	var records := NpcRoster.build(3)
	var places := NpcPlaceRegistry.new()
	var graph := NpcRouteGraph.new(places, [], [])
	var npc_sys := NpcSimulationSystem.new(records, places, graph)
	var economy := EconomySystem.new(npc_sys, 20, 10, 8, 30)
	economy.initialize(0)

	var total_food := EconomyRules.total_system_resource(economy, ResourceType.FOOD)
	var total_wood := EconomyRules.total_system_resource(economy, ResourceType.WOOD)
	var total_stone := EconomyRules.total_system_resource(economy, ResourceType.STONE)
	var total_coin := EconomyRules.total_system_resource(economy, ResourceType.COIN)

	var village_before := var_to_str(economy.village_inventory.to_dict())
	var market_before := var_to_str(economy.market_inventory.to_dict())
	harness.check(
		not economy.execute_trade("village", "market", ResourceType.STONE, 10, 5),
		"trade fails when buyer lacks sufficient coin"
	)
	harness.check_equals(
		var_to_str(economy.village_inventory.to_dict()),
		village_before,
		"failed trade leaves buyer inventory untouched"
	)
	harness.check_equals(
		var_to_str(economy.market_inventory.to_dict()),
		market_before,
		"failed trade leaves seller inventory untouched"
	)

	harness.check(
		economy.execute_trade("village", "market", ResourceType.WOOD, 3, 6),
		"valid trade of 3 Wood for 9 Coin succeeds"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.WOOD), 13, "village wood increased 10 -> 13"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.COIN), 21, "village coin decreased 30 -> 21"
	)

	harness.check(
		economy.execute_barter(
			"village", "market", ResourceType.WOOD, 2, ResourceType.FOOD, 3, 7
		),
		"valid barter succeeds"
	)

	harness.check_equals(
		EconomyRules.total_system_resource(economy, ResourceType.FOOD),
		total_food,
		"trades and barters conserve total Food"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(economy, ResourceType.WOOD),
		total_wood,
		"trades and barters conserve total Wood"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(economy, ResourceType.STONE),
		total_stone,
		"trades and barters conserve total Stone"
	)
	harness.check_equals(
		EconomyRules.total_system_resource(economy, ResourceType.COIN),
		total_coin,
		"trades and barters conserve total Coin"
	)


static func _test_community_projects(harness: TestHarness) -> void:
	var records := NpcRoster.build(4)
	var places := NpcPlaceRegistry.new()
	var graph := NpcRouteGraph.new(places, [], [])
	var npc_sys := NpcSimulationSystem.new(records, places, graph)
	var economy := EconomySystem.new(npc_sys, 20, 10, 3, 20)
	economy.initialize(0)

	var before := var_to_str(economy.village_inventory.to_dict())
	harness.check(
		not EconomyRules.can_fund_project(economy, "granary_repair"),
		"cannot fund granary_repair when stone is 3/4"
	)
	harness.check(
		not economy.fund_project("granary_repair", 10),
		"funding project with insufficient stone fails"
	)
	harness.check_equals(
		var_to_str(economy.village_inventory.to_dict()),
		before,
		"failed project funding does not deduct wood or coin"
	)

	economy.village_inventory.add(ResourceType.STONE, 5)
	harness.check(
		EconomyRules.can_fund_project(economy, "granary_repair"),
		"can fund granary_repair once stone >= 4"
	)
	harness.check(
		economy.fund_project("granary_repair", 15),
		"funding granary_repair succeeds"
	)
	harness.check(
		economy.completed_projects.has("granary_repair"),
		"granary_repair is marked completed"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.WOOD), 4, "6 Wood spent on project (10 -> 4)"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.STONE), 4, "4 Stone spent on project (8 -> 4)"
	)
	harness.check_equals(
		economy.get_village_resource(ResourceType.COIN), 12, "8 Coin spent on project (20 -> 12)"
	)
	harness.check(
		not economy.fund_project("granary_repair", 16),
		"non-repeatable project cannot be funded twice"
	)
