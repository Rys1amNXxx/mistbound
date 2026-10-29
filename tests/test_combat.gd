extends SceneTree
## Real combat rules with deterministic encounter fixtures. Actors are positioned
## and given large health pools; no production damage/physics method is replaced.
## attack_cd is reset only for fixed successive strikes, never in the cooldown test.
## Physics-frame waits register the real zone walls before raycast assertions.

const Simulation = preload("res://scripts/systems/world_simulation.gd")
const Catalog = preload("res://scripts/systems/item_catalog.gd")

var checks: int = 0
var failures: int = 0
var simulation: Node2D


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var original: String = OS.get_environment("MISTBOUND_SAVE_DIR")
	if original.is_empty() or not original.is_absolute_path() or original.contains("://"):
		push_error("Combat tests require an absolute isolated MISTBOUND_SAVE_DIR.")
		quit(2)
		return
	var directory: String = original.path_join("combat-%s-%s" % [OS.get_process_id(), Time.get_ticks_usec()])
	OS.set_environment("MISTBOUND_SAVE_DIR", directory)
	simulation = Simulation.new()
	root.add_child(simulation)
	simulation.effects.set_process(false)
	await _test_sword_and_cooldown()
	await _test_projectiles()
	await _test_walls()
	await _test_equipment()
	await _test_burn_ticks()
	await _test_burn_refresh_and_proc_isolation()
	await _test_chain()
	await _test_cleanup()
	await _test_snapshot_replication()
	simulation.queue_free()
	await process_frame
	OS.set_environment("MISTBOUND_SAVE_DIR", original)
	print("Combat tests: %s checks, %s failures. Isolated directory: %s" % [checks, failures, directory])
	quit(0 if failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL: " + message)


func _fresh() -> void:
	simulation.reset(true)
	simulation.add_player(1, _profile())
	simulation.enter_zone("mine")
	simulation.players[1].actor.position = Vector2(-600, 250)
	simulation.set_input(1, Vector2.ZERO, Vector2.RIGHT, false)
	for id: int in simulation.enemies:
		var enemy: Dictionary = simulation.enemies[id]
		enemy.actor.position = Vector2(780, 400)
		enemy.hp = 1000.0
		enemy.max_hp = 1000.0
		enemy.cooldown = 100.0
	await physics_frame
	await physics_frame


func _profile() -> Dictionary:
	return Catalog.sanitize_profile({"name": "战斗测试", "inventory": {"ember_relic": 1, "storm_relic": 1}})


func _target(index: int, point: Vector2, health: float = 1000.0) -> int:
	var id: int = simulation.enemies.keys()[index]
	simulation.enemies[id].actor.position = point
	simulation.enemies[id].hp = health
	simulation.enemies[id].max_hp = health
	return id


func _strike() -> void:
	simulation.players[1].attack_cd = 0.0
	simulation.combat.attack(1)


func _hit_count(element: String) -> int:
	var count: int = 0
	for entry: Dictionary in simulation._combat_events:
		if entry.event.get("type") == "hit" and entry.event.get("element") == element:
			count += 1
	return count


func _event_count(type: String) -> int:
	var count: int = 0
	for entry: Dictionary in simulation._combat_events:
		if entry.event.get("type") == type:
			count += 1
	return count


func _test_sword_and_cooldown() -> void:
	await _fresh()
	var front: int = _target(0, Vector2(-540, 250))
	var behind: int = _target(1, Vector2(-660, 250))
	var side: int = _target(2, Vector2(-600, 310))
	var distant: int = _target(3, Vector2(-450, 250))
	simulation.combat.attack(1)
	_check(simulation.enemies[front].hp == 978.0, "Sword damages a target in its forward cone by 22.")
	_check(simulation.enemies[behind].hp == 1000.0 and simulation.enemies[side].hp == 1000.0, "Sword rejects targets behind and outside the forward cone.")
	_check(simulation.enemies[distant].hp == 1000.0, "Sword cannot reach a distant target.")
	_check(is_equal_approx(simulation.players[1].attack_cd, 0.38), "Sword starts its real cooldown.")
	simulation.combat.attack(1)
	_check(simulation.enemies[front].hp == 978.0, "Repeated attack calls cannot bypass cooldown.")
	simulation.step(0.2)
	simulation.combat.attack(1)
	_check(simulation.enemies[front].hp == 978.0 and simulation.players[1].attack_cd > 0.0, "Partially elapsed cooldown still blocks an attack.")
	simulation.step(0.2)
	simulation.combat.attack(1)
	_check(simulation.enemies[front].hp == 956.0, "Simulation time expires cooldown and allows the next swing.")


func _test_projectiles() -> void:
	await _fresh()
	simulation.act(1, "equip", "hunter_crossbow")
	# Put the farther enemy first in dictionary order to test geometric priority.
	var far: int = _target(0, Vector2(-200, 250))
	var near: int = _target(1, Vector2(-400, 250))
	simulation.combat.attack(1)
	_check(simulation.combat.projectiles.size() == 1 and simulation.enemies[near].hp == 1000.0, "Crossbow creates a traveling arrow rather than instant damage.")
	_check(is_equal_approx(simulation.players[1].attack_cd, 0.60), "Crossbow uses its own attack interval.")
	simulation.combat.step(0.4)
	_check(simulation.enemies[near].hp == 982.0, "Swept arrow collision catches a target crossed between endpoints.")
	_check(simulation.enemies[far].hp == 1000.0 and simulation.combat.projectiles.is_empty(), "Arrow selects the nearest victim once and disappears.")
	simulation.combat.step(0.4)
	_check(simulation.enemies[near].hp == 982.0 and simulation.enemies[far].hp == 1000.0, "Consumed arrow cannot damage another victim later.")
	await _fresh()
	simulation.act(1, "equip", "hunter_crossbow")
	simulation.players[1].actor.position = Vector2(-700, 250)
	simulation.combat.attack(1)
	simulation.combat.step(0.5)
	_check(simulation.combat.projectiles.size() == 1, "Unobstructed arrow remains alive before maximum range.")
	if not simulation.combat.projectiles.is_empty():
		var shot: Dictionary = simulation.combat.projectiles.values()[0]
		_check(shot.position.is_equal_approx(Vector2(-320, 250)) and is_equal_approx(shot.remaining, 240.0), "Arrow advances by speed times elapsed time.")
	simulation.combat.step(0.5)
	_check(simulation.combat.projectiles.is_empty() and _hit_count("physical") == 0, "Arrow expires at range without inventing a hit.")


func _test_walls() -> void:
	await _fresh()
	simulation.act(1, "equip", "hunter_crossbow")
	simulation.players[1].actor.position = Vector2(-650, 50)
	var behind: int = _target(0, Vector2(-350, 50))
	simulation.combat.attack(1)
	simulation.combat.step(0.5)
	_check(simulation.enemies[behind].hp == 1000.0 and simulation.combat.projectiles.is_empty(), "Swept ray stops at a real mine wall before an enemy behind it.")
	var before: int = _target(1, Vector2(-590, 50))
	_strike()
	simulation.combat.step(0.5)
	_check(simulation.enemies[before].hp == 982.0 and simulation.enemies[behind].hp == 1000.0, "An enemy in front of the wall is hit before the wall.")
	simulation.act(1, "equip", "traveler_blade")
	simulation.players[1].actor.position = Vector2(-570, 40)
	simulation.enemies[before].actor.position = Vector2(780, 400)
	simulation.enemies[behind].actor.position = Vector2(-520, -15)
	simulation.set_input(1, Vector2.ZERO, Vector2(50, -55), false)
	_strike()
	_check(simulation.enemies[behind].hp == 1000.0, "Sword cannot strike through a wall corner despite being in range and cone.")


func _test_equipment() -> void:
	await _fresh()
	simulation.act(1, "equip", "hunter_crossbow")
	simulation.act(1, "equip", "ember_relic")
	_check(simulation.get_profile(1).equipped_weapon == "hunter_crossbow" and simulation.get_profile(1).equipped_relic == "ember_relic", "Weapon and relic equip independently.")
	simulation.act(1, "equip", "traveler_blade")
	_check(simulation.get_profile(1).equipped_relic == "ember_relic", "Changing weapon preserves the relic.")
	simulation.act(1, "equip", "storm_relic")
	simulation.players[1].relic_charge = 2
	simulation.act(1, "equip", "hunter_crossbow")
	_check(simulation.players[1].relic_charge == 2, "Changing weapon preserves the equipped storm relic's charge.")
	simulation.act(1, "equip", "ember_relic")
	_check(simulation.players[1].relic_charge == 0, "Changing relic resets storm charge.")
	simulation.act(1, "equip", "")
	_check(simulation.get_profile(1).equipped_relic == "" and simulation.get_profile(1).equipped_weapon == "hunter_crossbow", "Unequipping a relic leaves the weapon equipped.")
	_check(simulation.players[1].actor.weapon_kind == "projectile", "Host actor presentation follows the equipped weapon.")


func _test_burn_ticks() -> void:
	await _fresh()
	var target: int = _target(0, Vector2(-550, 250))
	simulation.act(1, "equip", "ember_relic")
	simulation.combat.attack(1)
	_check(simulation.enemies[target].hp == 978.0 and simulation.combat.burns.size() == 1, "Ember applies a burn without adding flat weapon damage.")
	simulation.step(0.0)
	_check(simulation.enemies[target].actor.burning, "Host enemy view reflects active burn status.")
	simulation.combat.step(0.49)
	_check(simulation.enemies[target].hp == 978.0, "Burn does no damage before the half-second interval.")
	simulation.combat.step(0.01)
	_check(simulation.enemies[target].hp == 974.0, "First burn tick deals four damage at half a second.")
	for tick: int in range(5):
		simulation.combat.step(0.5)
	_check(simulation.enemies[target].hp == 954.0 and _hit_count("burn") == 6, "Three-second burn produces exactly six four-damage ticks.")
	_check(simulation.combat.burns.is_empty(), "Completed burn status is removed.")
	simulation.combat.step(1.0)
	simulation.step(0.0)
	_check(simulation.enemies[target].hp == 954.0 and not simulation.enemies[target].actor.burning, "Expired burn cannot tick or remain visually active.")


func _test_burn_refresh_and_proc_isolation() -> void:
	await _fresh()
	var target: int = _target(0, Vector2(-550, 250))
	simulation.act(1, "equip", "ember_relic")
	simulation.combat.attack(1)
	simulation.combat.step(0.25)
	_strike()
	_check(simulation.combat.burns.size() == 1 and is_equal_approx(simulation.combat.burns[target].remaining, 3.0), "Repeated ember hit refreshes one burn rather than stacking statuses.")
	simulation.combat.step(0.25)
	_check(simulation.enemies[target].hp == 952.0, "Refreshing preserves the existing tick cadence without double damage.")
	simulation.combat.step(2.5)
	_check(simulation.combat.burns.has(target), "Refresh extends burn beyond the original expiry.")
	simulation.combat.step(0.25)
	_check(simulation.enemies[target].hp == 932.0 and _hit_count("burn") == 6 and simulation.combat.burns.is_empty(), "Refreshed burn expires without stacking or an extra partial tick.")
	await _fresh()
	target = _target(0, Vector2(-550, 250), 24.0)
	simulation.act(1, "equip", "ember_relic")
	simulation.combat.attack(1)
	simulation.act(1, "equip", "storm_relic")
	simulation.players[1].relic_charge = 2
	simulation.combat.step(0.5)
	_check(not simulation.enemies.has(target) and simulation.combat.burns.is_empty(), "Lethal burn follows the real enemy-death path and cleans its status.")
	_check(simulation.players[1].relic_charge == 2 and _event_count("chain") == 0, "Damage-over-time death cannot charge or trigger the newly equipped storm relic.")


func _test_chain() -> void:
	await _fresh()
	var primary: int = _target(0, Vector2(-550, 250))
	var hop_one: int = _target(1, Vector2(-400, 250))
	var hop_two: int = _target(2, Vector2(-250, 250))
	var excluded: int = _target(3, Vector2(-100, 250))
	simulation.act(1, "equip", "storm_relic")
	_strike()
	_check(simulation.players[1].relic_charge == 1 and simulation.enemies[primary].hp == 978.0, "First weapon hit adds one storm charge without bonus damage.")
	_strike()
	_check(simulation.players[1].relic_charge == 2 and _event_count("chain") == 0, "Second weapon hit does not discharge storm.")
	_strike()
	_check(simulation.enemies[primary].hp == 922.0 and simulation.players[1].relic_charge == 0, "Third weapon hit deals twelve chain damage to the primary and resets charge.")
	_check(simulation.enemies[hop_one].hp == 988.0 and simulation.enemies[hop_two].hp == 988.0, "Storm reaches two distinct nearby enemies for twelve each.")
	_check(simulation.enemies[excluded].hp == 1000.0, "Storm cannot exceed two secondary hops.")
	_check(_hit_count("chain") == 3 and _event_count("chain") == 1, "Chain damages each target once and never recursively procs itself.")
	var points: Array = []
	for entry: Dictionary in simulation._combat_events:
		if entry.event.type == "chain":
			points = entry.event.points
	_check(points.size() == 3 and points[0] != points[1] and points[1] != points[2] and points[0] != points[2], "Chain visual contains three non-repeated target points.")
	_strike()
	_check(simulation.players[1].relic_charge == 1 and _event_count("chain") == 1, "Only another weapon hit starts the next three-hit cycle.")


func _test_cleanup() -> void:
	await _fresh()
	simulation.add_player(2, _profile())
	simulation.players[1].actor.position = Vector2(-650, 250)
	simulation.players[2].actor.position = Vector2(-650, -380)
	_target(0, Vector2(-600, 250))
	_target(1, Vector2(-600, -380))
	for owner: int in [1, 2]:
		simulation.set_input(owner, Vector2.ZERO, Vector2.RIGHT, false)
		simulation.act(owner, "equip", "ember_relic")
		simulation.combat.attack(owner)
		simulation.act(owner, "equip", "hunter_crossbow")
		simulation.players[owner].attack_cd = 0.0
		simulation.combat.attack(owner)
	_check(simulation.combat.burns.size() == 2 and simulation.combat.projectiles.size() == 2, "Cleanup fixture has active burns and projectiles from two owners.")
	simulation.remove_player(2)
	_check(simulation.combat.burns.size() == 1 and simulation.combat.projectiles.size() == 1, "Removing a player clears only their burns and projectiles.")
	if not simulation.combat.burns.is_empty() and not simulation.combat.projectiles.is_empty():
		_check(simulation.combat.burns.values()[0].owner == 1 and simulation.combat.projectiles.values()[0].owner == 1, "Remaining effects still belong to the connected player.")
	simulation.players[1].relic_charge = 2
	simulation.step(0.0)
	simulation.enter_zone("wilds")
	_check(simulation.combat.burns.is_empty() and simulation.combat.projectiles.is_empty(), "Zone transition clears all active gameplay effects.")
	_check(simulation.players[1].relic_charge == 0 and simulation.effects._projectiles.is_empty() and simulation.effects._effects.is_empty(), "Zone transition resets charge and clears cosmetic effects.")


func _test_snapshot_replication() -> void:
	await _fresh()
	var burning: int = _target(0, Vector2(-550, 250))
	simulation.act(1, "equip", "ember_relic")
	simulation.combat.attack(1)
	simulation.act(1, "equip", "hunter_crossbow")
	simulation.act(1, "equip", "storm_relic")
	simulation.players[1].relic_charge = 2
	_strike()
	var boss_id: int = 0
	for id: int in simulation.enemies:
		if simulation.enemies[id].kind == "boss":
			boss_id = id
	_check(boss_id != 0, "Replication fixture has a boss telegraph.")
	if boss_id == 0:
		return
	var boss: Dictionary = simulation.enemies[boss_id]
	boss.state = "charge_windup"
	boss.windup = 0.34
	boss.telegraph_direction = Vector2.DOWN
	boss.telegraph_progress = 0.6
	boss.telegraph_range = 360.0
	boss.telegraph_radius = 36.0
	simulation.step(0.0)
	var replica: Node2D = Simulation.new()
	root.add_child(replica)
	replica.reset(false)
	replica.effects.set_process(false)
	var state: Dictionary = simulation.snapshot()
	_check(replica.apply_snapshot(state, 1), "Combat snapshot applies to a real client replica.")
	_check(replica.get_profile(1).equipped_weapon == "hunter_crossbow" and replica.get_profile(1).equipped_relic == "storm_relic", "Snapshot carries both independent equipment slots.")
	_check(replica.players[1].relic_charge == 2 and replica.players[1].actor.relic_charge == 2 and replica.players[1].actor.weapon_kind == "projectile", "Replica view carries weapon kind and storm charge.")
	_check(replica.effects._projectiles.size() == 1 and replica.combat.projectiles.is_empty(), "Client displays projectiles without running authoritative projectile rules.")
	_check(replica.enemies[burning].actor.burning, "Replica displays the host's burn status.")
	var view: Node2D = replica.enemies[boss_id].actor
	_check(view.boss_state == "charge_windup" and view.telegraph_direction == Vector2.DOWN and is_equal_approx(view.telegraph_progress, 0.6) and view.telegraph_range == 360.0 and view.telegraph_radius == 36.0, "Boss telegraph state, direction, progress, and dimensions replicate.")
	var displayed: int = replica.effects._sequence
	_check(displayed == state.events.size() and displayed > 0, "Initial snapshot replays each cosmetic event once.")
	_check(replica.apply_snapshot(simulation.snapshot(), 1) and replica.effects._sequence == displayed, "A newer snapshot containing old events cannot replay them.")
	_check(not replica.apply_snapshot(state, 1) and replica.effects._sequence == displayed, "Duplicate or stale snapshot cannot replay combat events.")
	simulation.emit_combat_event({"type": "hit", "position": Vector2.ZERO, "damage": 3.0, "element": "physical"})
	_check(replica.apply_snapshot(simulation.snapshot(), 1) and replica.effects._sequence == displayed + 1, "Only the newly introduced event plays on the next snapshot.")
	simulation.enter_zone("wilds")
	_check(replica.apply_snapshot(simulation.snapshot(), 1) and replica.effects._projectiles.is_empty() and replica.effects._effects.is_empty(), "New epoch clears old projectile and event visuals on the replica.")
	replica.queue_free()
