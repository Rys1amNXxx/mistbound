class_name EnemyBrain
extends RefCounted
## Host-only enemy state machines. Presentation consumes the public telegraph fields.
## state_time is elapsed time; windup is remaining warning time.

const NORMAL_SPEED := 95.0
const NORMAL_REACH := 56.0
const NORMAL_WINDUP := 0.45
const NORMAL_COOLDOWN := 1.35
const BOSS_SPEED := 70.0
const CHARGE_WINDUP := 0.85
const CHARGE_SPEED := 600.0
const CHARGE_DURATION := 0.6
const CHARGE_RANGE := 360.0
const CHARGE_RADIUS := 36.0
const SLAM_WINDUP := 0.9
const SLAM_RADIUS := 115.0
const PLAYER_RADIUS := 15.0
const WORLD_MASK := 1


static func initialize(enemy: Dictionary) -> void:
	enemy["state"] = "chase"
	enemy["state_time"] = 0.0
	enemy["cooldown"] = 0.8
	enemy["windup"] = 0.0
	enemy["telegraph_direction"] = Vector2.RIGHT
	enemy["telegraph_progress"] = 0.0
	enemy["telegraph_range"] = 0.0
	enemy["telegraph_radius"] = 0.0
	enemy["next_attack"] = "charge"
	enemy["charge_distance"] = 0.0
	enemy["charge_hit_players"] = []
	enemy["recovery_duration"] = 0.0


static func step(sim: Node, enemy_id: int, delta: float) -> void:
	if delta <= 0.0 or not sim.enemies.has(enemy_id):
		return
	var enemy: Dictionary = sim.enemies[enemy_id]
	if not enemy.has("state"):
		initialize(enemy)
	var actor: CharacterBody2D = enemy.actor
	if not is_instance_valid(actor) or not actor.is_inside_tree():
		return
	actor.velocity = Vector2.ZERO
	enemy.cooldown = maxf(0.0, float(enemy.cooldown) - delta)
	var nearest: int = sim._nearest_player(actor.position)
	if nearest == 0 or not sim.players.has(nearest):
		# No stale peer lookup or continuing an attack after the whole party leaves.
		_set_chase(enemy)
		return
	var target_actor: CharacterBody2D = sim.players[nearest].actor
	if not is_instance_valid(target_actor):
		_set_chase(enemy)
		return
	var offset: Vector2 = target_actor.position - actor.position
	if str(enemy.kind) == "boss":
		_step_boss(sim, enemy_id, enemy, actor, offset, delta)
	else:
		_step_normal(sim, enemy, actor, offset, delta)


static func _step_normal(sim: Node, enemy: Dictionary, actor: CharacterBody2D, offset: Vector2, delta: float) -> void:
	if str(enemy.state) == "melee_windup":
		if _advance_windup(enemy, delta, NORMAL_WINDUP):
			_damage_in_radius(sim, actor, NORMAL_REACH, 10.0)
			enemy.cooldown = NORMAL_COOLDOWN
			_set_chase(enemy)
		return
	if offset.length() < NORMAL_REACH - 6.0 and float(enemy.cooldown) <= 0.0 and _line_clear(actor, actor.position, actor.position + offset):
		_begin_windup(enemy, "melee_windup", offset, NORMAL_WINDUP, NORMAL_REACH, 0.0)
	elif offset.length() < 400.0 and offset.length() > NORMAL_REACH * 0.65:
		_move_toward(sim, actor, offset, NORMAL_SPEED, delta)


static func _step_boss(sim: Node, enemy_id: int, enemy: Dictionary, actor: CharacterBody2D, offset: Vector2, delta: float) -> void:
	match str(enemy.state):
		"charge_windup":
			if _advance_windup(enemy, delta, CHARGE_WINDUP):
				enemy.state = "charge"
				enemy.state_time = 0.0
				enemy.charge_distance = 0.0
				enemy.charge_hit_players = []
				sim.emit_combat_event({"type": "charge", "enemy_id": enemy_id,
					"position": actor.position, "direction": enemy.telegraph_direction,
					"range": CHARGE_RANGE, "radius": CHARGE_RADIUS, "duration": CHARGE_DURATION})
		"charge":
			_step_charge(sim, enemy, actor, delta)
		"slam_windup":
			if _advance_windup(enemy, delta, SLAM_WINDUP):
				_damage_in_radius(sim, actor, SLAM_RADIUS, 32.0)
				sim.emit_combat_event({"type": "slam", "enemy_id": enemy_id,
					"position": actor.position, "direction": enemy.telegraph_direction,
					"radius": SLAM_RADIUS, "duration": 0.45})
				_begin_recovery(enemy, 1.2, "charge")
		"recovery":
			enemy.state_time += delta
			if float(enemy.state_time) >= float(enemy.recovery_duration):
				_set_chase(enemy)
		_:
			var distance: float = offset.length()
			var can_attack: bool = float(enemy.cooldown) <= 0.0 and _line_clear(actor, actor.position, actor.position + offset)
			if str(enemy.next_attack) == "charge" and distance <= 420.0 and can_attack:
				_begin_windup(enemy, "charge_windup", offset, CHARGE_WINDUP, CHARGE_RADIUS, CHARGE_RANGE)
			elif str(enemy.next_attack) == "slam" and distance <= 140.0 and can_attack:
				_begin_windup(enemy, "slam_windup", offset, SLAM_WINDUP, SLAM_RADIUS, 0.0)
			elif distance < 620.0 and distance > NORMAL_REACH:
				_move_toward(sim, actor, offset, BOSS_SPEED, delta)


static func _begin_windup(enemy: Dictionary, state: String, offset: Vector2, duration: float, radius: float, reach: float) -> void:
	enemy.state = state
	enemy.state_time = 0.0
	enemy.windup = duration
	# The direction is captured once; dodging during windup cannot be tracked.
	enemy.telegraph_direction = offset.normalized() if offset.length_squared() > 0.001 else Vector2.RIGHT
	enemy.telegraph_progress = 0.0
	enemy.telegraph_radius = radius
	enemy.telegraph_range = reach


static func _advance_windup(enemy: Dictionary, delta: float, duration: float) -> bool:
	enemy.state_time += delta
	enemy.windup = maxf(0.0, duration - float(enemy.state_time))
	enemy.telegraph_progress = clampf(float(enemy.state_time) / duration, 0.0, 1.0)
	return float(enemy.state_time) >= duration


static func _step_charge(sim: Node, enemy: Dictionary, actor: CharacterBody2D, delta: float) -> void:
	var before: Vector2 = actor.position
	var direction: Vector2 = enemy.telegraph_direction
	var remaining: float = maxf(0.0, CHARGE_RANGE - float(enemy.charge_distance))
	var distance: float = minf(CHARGE_SPEED * delta, remaining)
	actor.velocity = direction * CHARGE_SPEED
	# move_and_collide stops against the first world collider without sliding into
	# a different path. Test damage only along the actual collision-limited sweep.
	var collision: KinematicCollision2D = actor.move_and_collide(direction * distance)
	sim._clamp_actor(actor)
	var after: Vector2 = actor.position
	enemy.charge_distance += before.distance_to(after)
	enemy.state_time += delta
	var hit_players: Array = enemy.charge_hit_players
	for peer_id in sim.players.keys():
		if hit_players.has(peer_id) or not sim.players.has(peer_id):
			continue
		var player_actor: CharacterBody2D = sim.players[peer_id].actor
		if not is_instance_valid(player_actor):
			continue
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(player_actor.position, before, after)
		if nearest.distance_to(player_actor.position) <= CHARGE_RADIUS + PLAYER_RADIUS and _line_clear(actor, nearest, player_actor.position):
			# Count an attempted hit even if the player's dash grants invulnerability.
			# A successful dodge must not be hit again later in this same charge.
			hit_players.append(peer_id)
			sim._hurt_player(peer_id, 28.0)
	if collision != null or float(enemy.charge_distance) >= CHARGE_RANGE - 0.01 or float(enemy.state_time) >= CHARGE_DURATION:
		actor.velocity = Vector2.ZERO
		_begin_recovery(enemy, 1.0, "slam")


static func _begin_recovery(enemy: Dictionary, duration: float, next_attack: String) -> void:
	enemy.state = "recovery"
	enemy.state_time = 0.0
	enemy.recovery_duration = duration
	enemy.next_attack = next_attack
	_clear_telegraph(enemy)


static func _set_chase(enemy: Dictionary) -> void:
	enemy.state = "chase"
	enemy.state_time = 0.0
	enemy.charge_hit_players = []
	_clear_telegraph(enemy)


static func _clear_telegraph(enemy: Dictionary) -> void:
	enemy.windup = 0.0
	enemy.telegraph_progress = 0.0
	enemy.telegraph_range = 0.0
	enemy.telegraph_radius = 0.0


static func _move_toward(sim: Node, actor: CharacterBody2D, offset: Vector2, speed: float, delta: float) -> void:
	if offset.length_squared() <= 0.001:
		return
	actor.velocity = offset.normalized() * speed
	var collision: KinematicCollision2D = actor.move_and_collide(actor.velocity * delta)
	if collision != null:
		# Small, simple slide behavior keeps ordinary pursuit moving along walls.
		var slide: Vector2 = collision.get_remainder().slide(collision.get_normal())
		if slide.length_squared() > 0.001:
			actor.move_and_collide(slide)
	sim._clamp_actor(actor)


static func _damage_in_radius(sim: Node, actor: CharacterBody2D, radius: float, damage: float) -> void:
	for peer_id in sim.players.keys():
		if not sim.players.has(peer_id):
			continue
		var player_actor: CharacterBody2D = sim.players[peer_id].actor
		if is_instance_valid(player_actor) and actor.position.distance_to(player_actor.position) <= radius + PLAYER_RADIUS and _line_clear(actor, actor.position, player_actor.position):
			sim._hurt_player(peer_id, damage)


static func _line_clear(actor: CharacterBody2D, from: Vector2, to: Vector2) -> bool:
	if from.distance_squared_to(to) <= 0.001:
		return true
	var query := PhysicsRayQueryParameters2D.create(from, to, WORLD_MASK)
	query.collide_with_areas = false
	query.hit_from_inside = true
	return actor.get_world_2d().direct_space_state.intersect_ray(query).is_empty()
