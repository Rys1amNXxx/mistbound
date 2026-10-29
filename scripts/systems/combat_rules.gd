class_name CombatRules
extends RefCounted
## Authoritative weapon/effect rules. Views never decide hits or grant rewards.

const Catalog = preload("res://scripts/systems/item_catalog.gd")
const BURN_DURATION := 3.0
const BURN_INTERVAL := 0.5
const BURN_DAMAGE := 4.0
const CHAIN_DAMAGE := 12.0
const CHAIN_RADIUS := 190.0

var simulation: Node2D
var projectiles: Dictionary = {}
var burns: Dictionary = {}
var _next_projectile: int = 0

func configure(world: Node2D) -> void:
	simulation = world

func clear() -> void:
	projectiles.clear()
	burns.clear()

func remove_owner(peer_id: int) -> void:
	for id in projectiles.keys():
		if int(projectiles[id].owner) == peer_id:
			projectiles.erase(id)
	for id in burns.keys():
		if int(burns[id].owner) == peer_id:
			burns.erase(id)

func attack(peer_id: int) -> void:
	if not simulation.players.has(peer_id):
		return
	var player: Dictionary = simulation.players[peer_id]
	if float(player.attack_cd) > 0.0:
		return
	var weapon: Resource = Catalog.get_item(str(player.profile.equipped_weapon))
	if weapon == null or weapon.slot != "weapon":
		return
	player.attack_cd = weapon.attack_interval
	player.actor.slash_time = 0.18 if weapon.weapon_kind == "melee" else 0.10
	var damage: float = weapon.base_damage + float(simulation._level(player.profile) - 1) * 2.0
	var origin: Vector2 = player.actor.position
	var direction: Vector2 = player.aim
	var relic_id: String = player.profile.equipped_relic
	if weapon.weapon_kind == "projectile":
		_next_projectile += 1
		projectiles[_next_projectile] = {"id": _next_projectile, "owner": peer_id,
			"position": origin, "direction": direction, "speed": weapon.projectile_speed,
			"remaining": weapon.attack_range, "damage": damage, "relic_id": relic_id}
		simulation.emit_combat_event({"type": "shot", "position": origin, "direction": direction})
	else:
		for enemy_id in simulation.enemies.keys():
			if not simulation.enemies.has(enemy_id):
				continue
			var enemy: Dictionary = simulation.enemies[enemy_id]
			var offset: Vector2 = enemy.actor.position - origin
			if offset.length() > weapon.attack_range + float(enemy.actor.radius):
				continue
			if offset.length() >= 22.0 and offset.normalized().dot(direction) <= 0.12:
				continue
			if not _line_clear(origin, enemy.actor.position):
				continue
			_weapon_hit(peer_id, enemy_id, damage, relic_id)

func step(delta: float) -> void:
	_step_projectiles(delta)
	_step_burns(delta)

func _step_projectiles(delta: float) -> void:
	for id in projectiles.keys():
		var shot: Dictionary = projectiles[id]
		if not simulation.players.has(int(shot.owner)):
			projectiles.erase(id)
			continue
		var start: Vector2 = shot.position
		var distance: float = minf(float(shot.remaining), float(shot.speed) * delta)
		var finish: Vector2 = start + shot.direction * distance
		var wall: Dictionary = _wall_hit(start, finish)
		var first_t: float = start.distance_to(wall.position) / maxf(distance, 0.0001) if not wall.is_empty() else 1.0001
		var victim: int = 0
		for enemy_id in simulation.enemies:
			var enemy: Dictionary = simulation.enemies[enemy_id]
			var intersection := _segment_circle(start, finish, enemy.actor.position, float(enemy.actor.radius) + 3.0)
			if intersection >= 0.0 and intersection < first_t:
				first_t = intersection
				victim = enemy_id
		if victim != 0:
			_weapon_hit(int(shot.owner), victim, float(shot.damage), str(shot.relic_id))
			projectiles.erase(id)
		elif not wall.is_empty():
			simulation.emit_combat_event({"type": "hit", "position": wall.position, "damage": 0.0, "element": "physical"})
			projectiles.erase(id)
		else:
			shot.position = finish
			shot.remaining -= distance
			if float(shot.remaining) <= 0.001:
				projectiles.erase(id)

func _weapon_hit(peer_id: int, enemy_id: int, damage: float, relic_id: String) -> void:
	if not simulation.enemies.has(enemy_id):
		return
	var position: Vector2 = simulation.enemies[enemy_id].actor.position
	_damage(enemy_id, damage, "physical")
	var relic: Resource = Catalog.get_item(relic_id)
	if relic == null:
		return
	match relic.effect_id:
		"burn":
			if simulation.enemies.has(enemy_id):
				if burns.has(enemy_id):
					burns[enemy_id].remaining = BURN_DURATION
					burns[enemy_id].owner = peer_id
				else:
					burns[enemy_id] = {"remaining": BURN_DURATION, "until_tick": BURN_INTERVAL, "owner": peer_id}
		"chain":
			if not simulation.players.has(peer_id):
				return
			var player: Dictionary = simulation.players[peer_id]
			# In-flight bolts retain their damage/effect, but cannot build a removed relic's charge.
			if str(player.profile.equipped_relic) != relic_id:
				return
			player.relic_charge = (int(player.relic_charge) + 1) % 3
			if int(player.relic_charge) == 0:
				_chain(enemy_id, position)

func _step_burns(delta: float) -> void:
	for enemy_id in burns.keys():
		if not simulation.enemies.has(enemy_id):
			burns.erase(enemy_id)
			continue
		var status: Dictionary = burns[enemy_id]
		var duration: float = minf(delta, float(status.remaining))
		status.remaining = maxf(0.0, float(status.remaining) - duration)
		status.until_tick -= duration
		while float(status.until_tick) <= 0.00001:
			status.until_tick += BURN_INTERVAL
			_damage(enemy_id, BURN_DAMAGE, "burn")
			if not simulation.enemies.has(enemy_id):
				break
		if float(status.remaining) <= 0.0 or not simulation.enemies.has(enemy_id):
			burns.erase(enemy_id)

func _chain(first_id: int, origin: Vector2) -> void:
	var visited: Array = [first_id]
	var points: Array = [origin]
	_damage(first_id, CHAIN_DAMAGE, "chain")
	var last: Vector2 = origin
	for hop in range(2):
		var nearest := 0
		var nearest_distance: float = CHAIN_RADIUS
		for id in simulation.enemies:
			if id in visited:
				continue
			var point: Vector2 = simulation.enemies[id].actor.position
			var distance: float = point.distance_to(last)
			if distance <= nearest_distance and _line_clear(last, point):
				nearest = id
				nearest_distance = distance
		if nearest == 0:
			break
		last = simulation.enemies[nearest].actor.position
		points.append(last)
		visited.append(nearest)
		_damage(nearest, CHAIN_DAMAGE, "chain")
	simulation.emit_combat_event({"type": "chain", "points": points})

func _damage(enemy_id: int, amount: float, element: String) -> void:
	if not simulation.enemies.has(enemy_id):
		return
	var enemy: Dictionary = simulation.enemies[enemy_id]
	enemy.hp -= amount
	enemy.actor.hurt_time = 0.15
	simulation.emit_combat_event({"type": "hit", "position": enemy.actor.position,
		"damage": amount, "element": element, "target": "enemy"})
	if float(enemy.hp) <= 0.0:
		burns.erase(enemy_id)
		simulation._defeat_enemy(enemy_id)

func projectile_snapshot() -> Array:
	var result: Array = []
	for id in projectiles:
		var shot: Dictionary = projectiles[id]
		result.append({"id": id, "owner": shot.owner, "position": shot.position,
			"direction": shot.direction, "speed": shot.speed})
	return result

func _wall_hit(start: Vector2, finish: Vector2) -> Dictionary:
	if start.is_equal_approx(finish):
		return {}
	var query := PhysicsRayQueryParameters2D.create(start, finish, 1)
	query.hit_from_inside = true
	return simulation.get_world_2d().direct_space_state.intersect_ray(query)

func _line_clear(start: Vector2, finish: Vector2) -> bool:
	return _wall_hit(start, finish).is_empty()

static func _segment_circle(start: Vector2, finish: Vector2, center: Vector2, radius: float) -> float:
	var from_center := start - center
	var direction := finish - start
	var c := from_center.length_squared() - radius * radius
	if c <= 0:
		return 0.0
	var a := direction.length_squared()
	if a <= 0.000001:
		return -1.0
	var b := 2.0 * from_center.dot(direction)
	var discriminant := b * b - 4.0 * a * c
	if discriminant < 0:
		return -1.0
	var hit := (-b - sqrt(discriminant)) / (2.0 * a)
	return hit if hit >= 0.0 and hit <= 1.0 else -1.0
