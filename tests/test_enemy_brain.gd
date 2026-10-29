extends SceneTree
## Run with: godot --headless --path . --script res://tests/test_enemy_brain.gd
## No save files or real game session are created.

const Brain = preload("res://scripts/systems/enemy_brain.gd")
var failures: Array[String] = []
var assertions: int = 0


class Body extends CharacterBody2D:
	var radius: float = 15.0


class FakeSimulation extends Node2D:
	var enemies: Dictionary = {}
	var players: Dictionary = {}
	var hits: Array[Dictionary] = []
	var attempts: Array[int] = []
	var events: Array[Dictionary] = []

	func _nearest_player(point: Vector2) -> int:
		var nearest: int = 0
		var distance: float = INF
		for id in players:
			var candidate: float = point.distance_squared_to(players[id].actor.position)
			if candidate < distance:
				distance = candidate
				nearest = id
		return nearest

	func _hurt_player(id: int, damage: float) -> void:
		attempts.append(id)
		if float(players[id].get("dash_time", 0.0)) > 0.0:
			return
		hits.append({"id": id, "damage": damage})
		players[id].hp -= damage

	func _clamp_actor(actor: CharacterBody2D) -> void:
		actor.position = actor.position.clamp(Vector2(-900, -500), Vector2(900, 500))

	func emit_combat_event(event: Dictionary) -> void:
		events.append(event)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_charge_warning_and_direction()
	await _test_charge_sweep_and_recovery()
	await _test_charge_dodge_is_not_rehit()
	await _test_wall_blocks_charge_and_damage()
	await _test_slam_and_alternation()
	await _test_normal_attack_and_disconnect()
	if failures.is_empty():
		print("PASS enemy brain: %d assertions" % assertions)
		quit(0)
	else:
		for failure in failures:
			push_error(failure)
		print("FAIL enemy brain: %d failures / %d assertions" % [failures.size(), assertions])
		quit(1)


func _new_sim() -> FakeSimulation:
	var sim := FakeSimulation.new()
	root.add_child(sim)
	return sim


func _body(sim: FakeSimulation, point: Vector2, radius: float, layer: int) -> Body:
	var actor := Body.new()
	actor.radius = radius
	actor.position = point
	actor.collision_layer = layer
	actor.collision_mask = 1
	actor.motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var collider := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = radius
	collider.shape = shape
	actor.add_child(collider)
	sim.add_child(actor)
	return actor


func _enemy(sim: FakeSimulation, kind: String = "boss") -> Dictionary:
	var enemy: Dictionary = {"actor": _body(sim, Vector2.ZERO, 30.0 if kind == "boss" else 15.0, 4),
		"kind": kind, "hp": 100.0, "max_hp": 100.0, "home": Vector2.ZERO}
	Brain.initialize(enemy)
	enemy.cooldown = 0.0
	sim.enemies[1] = enemy
	return enemy


func _player(sim: FakeSimulation, point: Vector2, id: int = 1) -> Dictionary:
	var player: Dictionary = {"actor": _body(sim, point, 15.0, 2), "hp": 100.0, "dash_time": 0.0}
	sim.players[id] = player
	return player


func _wait_physics() -> void:
	await physics_frame
	await physics_frame


func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _test_charge_warning_and_direction() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim)
	var player := _player(sim, Vector2(200, 0))
	await _wait_physics()
	Brain.step(sim, 1, 1.0 / 60.0)
	_check(enemy.state == "charge_windup", "boss must warn before charging")
	_check(is_equal_approx(enemy.telegraph_range, 360.0) and is_equal_approx(enemy.telegraph_radius, 36.0), "charge warning geometry")
	player.actor.position = Vector2(0, 200)
	Brain.step(sim, 1, 0.80)
	_check(enemy.state == "charge_windup" and sim.hits.is_empty(), "no charge damage during warning")
	_check(enemy.actor.position == Vector2.ZERO, "boss must remain stationary during warning")
	_check(enemy.telegraph_direction.is_equal_approx(Vector2.RIGHT), "charge must not track the dodging target")
	_check(enemy.telegraph_progress > 0.9 and enemy.telegraph_progress < 1.0, "warning progress approaches completion")
	Brain.step(sim, 1, 0.06)
	_check(enemy.state == "charge" and sim.events.size() == 1 and sim.events[0].type == "charge", "charge starts after warning with one event")
	sim.queue_free()
	await process_frame


func _test_charge_sweep_and_recovery() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim)
	_player(sim, Vector2(100, 0))
	_player(sim, Vector2(250, 0), 2)
	await _wait_physics()
	Brain.step(sim, 1, 0.01)
	Brain.step(sim, 1, 0.86)
	# A single long step must hit both targets between the endpoints.
	Brain.step(sim, 1, 0.7)
	_check(sim.hits.size() == 2, "swept charge must hit players between its endpoints")
	_check(sim.hits.all(func(hit: Dictionary) -> bool: return is_equal_approx(hit.damage, 28.0)), "charge damage is 28")
	_check(enemy.actor.position.distance_to(Vector2(360, 0)) < 1.0, "charge must travel at most 360 pixels")
	_check(enemy.state == "recovery" and enemy.next_attack == "slam", "charge recovers and selects slam next")
	Brain.step(sim, 1, 0.9)
	_check(enemy.state == "recovery" and sim.hits.size() == 2, "charge cannot damage again during recovery")
	Brain.step(sim, 1, 0.11)
	_check(enemy.state == "chase", "charge recovery lasts one second")
	sim.queue_free()
	await process_frame


func _test_charge_dodge_is_not_rehit() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim)
	var player := _player(sim, Vector2(80, 0))
	await _wait_physics()
	Brain.step(sim, 1, 0.01)
	Brain.step(sim, 1, 0.86)
	player.dash_time = 0.2
	Brain.step(sim, 1, 0.1)
	_check(sim.attempts.size() == 1 and sim.hits.is_empty(), "dash may dodge the charge hit")
	player.dash_time = 0.0
	Brain.step(sim, 1, 0.1)
	_check(sim.attempts.size() == 1 and sim.hits.is_empty(), "the same charge must not re-hit after dash immunity expires")
	_check(enemy.state == "charge", "dodge test happens during the same continuing charge")
	sim.queue_free()
	await process_frame


func _test_wall_blocks_charge_and_damage() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim)
	_player(sim, Vector2(180, 0))
	await _wait_physics()
	Brain.step(sim, 1, 0.01)
	Brain.step(sim, 1, 0.86)
	var wall := StaticBody2D.new()
	wall.position = Vector2(100, 0)
	wall.collision_layer = 1
	var collider := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(20, 300)
	collider.shape = rectangle
	wall.add_child(collider)
	sim.add_child(wall)
	await _wait_physics()
	Brain.step(sim, 1, 0.6)
	_check(enemy.state == "recovery", "world collision must end a charge")
	_check(enemy.actor.position.x < 61.0, "charge body must stop before the wall")
	_check(sim.hits.is_empty(), "charge must not hit through walls")
	# Even a radial slam cannot damage a player shielded by the same wall.
	enemy.state = "slam_windup"
	enemy.state_time = 0.0
	enemy.windup = 0.9
	Brain.step(sim, 1, 0.91)
	_check(sim.hits.is_empty(), "slam damage must respect world line of sight")
	sim.queue_free()
	await process_frame


func _test_slam_and_alternation() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim)
	_player(sim, Vector2(100, 0))
	enemy.next_attack = "slam"
	await _wait_physics()
	Brain.step(sim, 1, 0.01)
	_check(enemy.state == "slam_windup" and is_equal_approx(enemy.telegraph_radius, 115.0), "slam has its own radius warning")
	Brain.step(sim, 1, 0.89)
	_check(sim.hits.is_empty() and enemy.actor.position == Vector2.ZERO, "slam has a stationary 0.9 second warning")
	Brain.step(sim, 1, 0.02)
	_check(sim.hits.size() == 1 and is_equal_approx(sim.hits[0].damage, 32.0), "slam hits once for 32")
	_check(enemy.state == "recovery" and enemy.next_attack == "charge", "slam recovery selects charge next")
	Brain.step(sim, 1, 1.1)
	_check(enemy.state == "recovery" and sim.hits.size() == 1, "slam recovery remains safe for 1.2 seconds")
	Brain.step(sim, 1, 0.11)
	Brain.step(sim, 1, 0.01)
	_check(enemy.state == "charge_windup", "boss alternates back to charge")
	sim.queue_free()
	await process_frame


func _test_normal_attack_and_disconnect() -> void:
	var sim := _new_sim()
	var enemy := _enemy(sim, "slime")
	_player(sim, Vector2(40, 0))
	await _wait_physics()
	Brain.step(sim, 1, 0.01)
	Brain.step(sim, 1, 0.44)
	_check(enemy.state == "melee_windup" and sim.hits.is_empty(), "ordinary enemies warn for 0.45 seconds")
	Brain.step(sim, 1, 0.02)
	_check(sim.hits.size() == 1 and is_equal_approx(sim.hits[0].damage, 10.0), "ordinary enemy melee damage")
	Brain.step(sim, 1, 0.5)
	_check(enemy.state == "chase" and sim.hits.size() == 1, "ordinary enemy cooldown prevents immediate repeat")
	enemy.kind = "boss"
	Brain.initialize(enemy)
	enemy.cooldown = 0.0
	Brain.step(sim, 1, 0.01)
	sim.players.clear()
	Brain.step(sim, 1, 1.0)
	_check(enemy.state == "chase" and sim.hits.size() == 1 and enemy.windup == 0.0, "disconnect during warning safely cancels without hits")
	sim.queue_free()
	await process_frame
