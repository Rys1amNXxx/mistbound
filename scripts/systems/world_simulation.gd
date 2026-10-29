class_name WorldSimulation
extends Node2D
## Authoritative world rules. The network session never accepts client damage or loot.

signal notice(peer_id: int, message: String)
signal checkpoint()

const Actor = preload("res://scripts/actors/actor_view.gd")
const Loot = preload("res://scripts/actors/loot_view.gd")
const Zone = preload("res://scripts/world/zone_view.gd")
const Catalog = preload("res://scripts/systems/item_catalog.gd")
const Store = preload("res://scripts/systems/save_store.gd")
const Combat = preload("res://scripts/systems/combat_rules.gd")
const Brain = preload("res://scripts/systems/enemy_brain.gd")
const Effects = preload("res://scripts/actors/combat_view.gd")
const COLORS := [Color("80c5b5"), Color("e1bd80"), Color("b6a1de"), Color("87b7d7")]

var zone: Node2D
var actors: Node2D
var effects: Node2D
var combat: RefCounted
var players: Dictionary = {}
var enemies: Dictionary = {}
var loot: Dictionary = {}
var current_zone: String = "camp"
var epoch: int = 0
var world_data: Dictionary = {}
var authoritative: bool = true
var _next_id: int = 0
var _snapshot_sequence: int = 0
var _last_received_sequence: int = -1
var _combat_events: Array = []
var _next_event_id: int = 0
var _last_received_event: int = 0

func _ready() -> void:
	zone = Zone.new()
	add_child(zone)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	add_child(actors)
	effects = Effects.new()
	effects.z_index = 2
	add_child(effects)
	combat = Combat.new()
	combat.configure(self)

func reset(is_authority: bool, saved_world: Dictionary = {}) -> void:
	combat.clear()
	_clear_combat_events()
	_next_event_id = 0
	_clear_entities(players)
	_clear_entities(enemies)
	_clear_entities(loot)
	authoritative = is_authority
	world_data = saved_world.duplicate(true) if not saved_world.is_empty() else Store.default_world()
	epoch = 0
	_next_id = 0
	_snapshot_sequence = 0
	_last_received_sequence = -1
	current_zone = "camp"
	zone.build("camp")

func add_player(peer_id: int, profile: Dictionary) -> void:
	if players.has(peer_id):
		return
	var actor := _make_actor("player", zone.get_spawn(players.size()), peer_id)
	var clean: Dictionary = Catalog.sanitize_profile(profile)
	actor.display_name = "%s · %d" % [clean.name, players.size() + 1]
	var maximum := _max_hp(clean)
	players[peer_id] = {"actor": actor, "profile": clean, "hp": maximum, "max_hp": maximum,
		"move": Vector2.ZERO, "aim": Vector2.RIGHT, "attack": false, "attack_cd": 0.0,
		"dash_cd": 0.0, "dash_time": 0.0, "invulnerability": 0.0, "dash_direction": Vector2.RIGHT, "input_age": 0.0,
		"relic_charge": 0}
	actor.weapon_kind = Catalog.get_item(clean.equipped_weapon).weapon_kind

func remove_player(peer_id: int) -> void:
	combat.remove_owner(peer_id)
	if players.has(peer_id):
		_destroy(players[peer_id].actor)
		players.erase(peer_id)
	for id in loot.keys():
		if int(loot[id].owner) == peer_id:
			_destroy(loot[id].actor)
			loot.erase(id)

func enter_zone(zone_id: String) -> void:
	if zone_id not in ["camp", "wilds", "mine", "crypt"]:
		return
	combat.clear()
	_clear_combat_events()
	_clear_entities(enemies)
	_clear_entities(loot)
	current_zone = zone_id
	epoch += 1
	zone.build(zone_id)
	var visited: Array = world_data.get("visited", ["camp"])
	if not visited.has(zone_id):
		visited.append(zone_id)
	world_data["visited"] = visited
	var index := 0
	for id in players:
		var player: Dictionary = players[id]
		player.actor.position = zone.get_spawn(index)
		player.actor.target_position = player.actor.position
		player.move = Vector2.ZERO
		player.attack = false
		player.dash_time = 0.0
		player.invulnerability = 1.0
		player.input_age = 1.0
		player.relic_charge = 0
		if zone_id == "camp":
			player.hp = player.max_hp
		index += 1
	for spawn in zone.get_enemy_spawns():
		var kind: String = spawn.kind
		_next_id += 1
		var actor := _make_actor(kind, spawn.position)
		actor.set_meta("entity_id", _next_id)
		var base_hp: float = 280.0 if kind == "boss" else (80.0 if kind == "guard" else 44.0)
		var maximum: float = base_hp * (1.0 + 0.4 * max(0, players.size() - 1))
		enemies[_next_id] = {"actor": actor, "kind": kind, "hp": maximum, "max_hp": maximum,
			"cooldown": 0.8, "windup": 0.0, "home": spawn.position}
		Brain.initialize(enemies[_next_id])
	notice.emit(0, "抵达%s · 探索进度已记录" % zone.get_title())
	checkpoint.emit()

func set_input(peer_id: int, motion: Vector2, aim: Vector2, attack: bool) -> void:
	if not players.has(peer_id) or not motion.is_finite() or not aim.is_finite():
		return
	var player: Dictionary = players[peer_id]
	player.move = motion.limit_length(1.0)
	if aim.length_squared() > 0.001:
		player.aim = aim.normalized()
	player.attack = attack
	player.input_age = 0.0

func act(peer_id: int, action: String, argument: String = "") -> void:
	if not players.has(peer_id):
		return
	var player: Dictionary = players[peer_id]
	match action:
		"dash":
			if float(player.dash_cd) <= 0.0:
				player.dash_time = 0.16
				player.dash_cd = 0.85
				player.dash_direction = player.move.normalized() if player.move.length_squared() > 0.01 else player.aim
		"interact":
			_interact(peer_id)
		"equip":
			_equip(peer_id, argument)

func _equip(peer_id: int, item_id: String) -> void:
	var player: Dictionary = players[peer_id]
	if item_id.is_empty():
		player.profile.equipped_relic = ""
		player.relic_charge = 0
		notice.emit(peer_id, "已卸下遗物")
	elif int(player.profile.inventory.get(item_id, 0)) > 0 and Catalog.get_item(item_id) != null:
		var item: Resource = Catalog.get_item(item_id)
		if item.slot == "weapon":
			player.profile.equipped_weapon = item_id
			player.actor.weapon_kind = item.weapon_kind
		elif item.slot == "relic":
			if player.profile.equipped_relic != item_id:
				player.relic_charge = 0
			player.profile.equipped_relic = item_id
		else:
			return
		notice.emit(peer_id, "已装备：" + item.display_name)
	else:
		return
	checkpoint.emit()

func step(delta: float) -> void:
	_step_events(delta)
	for id in players:
		var player: Dictionary = players[id]
		var actor: CharacterBody2D = player.actor
		player.input_age += delta
		if float(player.input_age) > 0.35:
			player.move = Vector2.ZERO
			player.attack = false
		player.attack_cd = maxf(0.0, player.attack_cd - delta)
		player.dash_cd = maxf(0.0, player.dash_cd - delta)
		player.dash_time = maxf(0.0, player.dash_time - delta)
		player.invulnerability = maxf(0.0, player.invulnerability - delta)
		actor.facing = player.aim
		actor.velocity = player.dash_direction * 650.0 if player.dash_time > 0 else player.move * 225.0
		actor.move_and_slide()
		_clamp_actor(actor)
		if bool(player.attack) and float(player.attack_cd) <= 0.0:
			_attack(id)
		actor.hp = player.hp
		actor.max_hp = player.max_hp
		actor.relic_charge = player.relic_charge
	combat.step(delta)
	for id in enemies.keys():
		Brain.step(self, id, delta)
		_update_enemy_view(enemies[id])
	effects.set_projectiles(combat.projectile_snapshot())

func _attack(peer_id: int) -> void:
	combat.attack(peer_id)

func _hurt_player(peer_id: int, damage: float) -> void:
	var player: Dictionary = players[peer_id]
	if float(player.dash_time) > 0 or float(player.invulnerability) > 0:
		return
	player.hp -= damage
	player.actor.hurt_time = 0.18
	emit_combat_event({"type": "hit", "position": player.actor.position, "damage": damage, "element": "physical", "target": "player"})
	if float(player.hp) <= 0:
		player.hp = player.max_hp
		player.actor.position = zone.get_spawn(players.keys().find(peer_id))
		player.dash_time = 0.0
		player.invulnerability = 1.2
		player.profile.coins = maxi(0, int(player.profile.coins) - 5)
		notice.emit(peer_id, "在区域入口重生 · 损失 5 金币，装备保留")
		checkpoint.emit()

func _defeat_enemy(enemy_id: int) -> void:
	var enemy: Dictionary = enemies[enemy_id]
	var boss: bool = enemy.kind == "boss"
	var index := 0
	for peer_id in players:
		var player: Dictionary = players[peer_id]
		player.profile.xp = mini(Catalog.MAX_CURRENCY, int(player.profile.xp) + (50 if boss else 8))
		var old_max: float = player.max_hp
		player.max_hp = _max_hp(player.profile)
		player.hp += player.max_hp - old_max
		var item_id: String = ""
		if boss:
			item_id = "ember_relic" if current_zone == "mine" else "storm_relic"
		_spawn_loot(peer_id, enemy.actor.position + Vector2(index * 20, 18), 40 if boss else 6, item_id)
		index += 1
	if boss:
		world_data.boss_kills = mini(Catalog.MAX_CURRENCY, int(world_data.get("boss_kills", 0)) + 1)
		notice.emit(0, "首领已击败！靠近自己的金色掉落按 E 拾取遗物")
	_destroy(enemy.actor)
	enemies.erase(enemy_id)
	checkpoint.emit()

func _spawn_loot(owner: int, point: Vector2, coins: int, item_id: String) -> void:
	_next_id += 1
	var view := Loot.new()
	view.position = point
	if item_id != "":
		view.tint = Catalog.get_item(item_id).color
	actors.add_child(view)
	loot[_next_id] = {"actor": view, "owner": owner, "coins": coins, "item_id": item_id}

func _interact(peer_id: int) -> void:
	var player: Dictionary = players[peer_id]
	for id in loot.keys():
		var drop: Dictionary = loot[id]
		if int(drop.owner) == peer_id and player.actor.position.distance_to(drop.actor.position) <= 65.0:
			player.profile.coins = mini(Catalog.MAX_CURRENCY, int(player.profile.coins) + int(drop.coins))
			var label := "+%d 金币" % int(drop.coins)
			if str(drop.item_id) != "":
				var inventory: Dictionary = player.profile.inventory
				inventory[drop.item_id] = mini(Catalog.MAX_ITEM_COUNT, int(inventory.get(drop.item_id, 0)) + 1)
				label += " · " + Catalog.get_item(drop.item_id).display_name + "（I 打开背包装备）"
			notice.emit(peer_id, label)
			_destroy(drop.actor)
			loot.erase(id)
			checkpoint.emit()
			return
	for portal in zone.get_portals():
		if player.actor.position.distance_to(portal.position) <= float(portal.radius):
			if peer_id != 1:
				notice.emit(peer_id, "由房主在入口按 E，带领全队切换区域")
				return
			enter_zone(portal.target)
			return

func interaction_for(peer_id: int) -> String:
	if not players.has(peer_id):
		return ""
	var point: Vector2 = players[peer_id].actor.position
	for id in loot:
		if int(loot[id].owner) == peer_id and point.distance_to(loot[id].actor.position) <= 65.0:
			return "拾取你的战利品"
	for portal in zone.get_portals():
		if point.distance_to(portal.position) <= float(portal.radius):
			return "全队前往 " + str(portal.label) if peer_id == 1 else "请房主开启：" + str(portal.label)
	return ""

func get_profile(peer_id: int) -> Dictionary:
	return players[peer_id].profile.duplicate(true) if players.has(peer_id) else {}

func snapshot() -> Dictionary:
	_snapshot_sequence += 1
	var state := {"zone": current_zone, "epoch": epoch, "sequence": _snapshot_sequence,
		"players": [], "enemies": [], "loot": [], "world": world_data.duplicate(true),
		"projectiles": combat.projectile_snapshot(), "events": []}
	for entry in _combat_events:
		state.events.append(entry.event.duplicate(true))
	for id in players:
		var p: Dictionary = players[id]
		state.players.append({"id": id, "position": p.actor.position, "facing": p.aim, "hp": p.hp, "max_hp": p.max_hp,
			"profile": p.profile.duplicate(true), "name": p.actor.display_name, "slash": p.actor.slash_time,
			"charge": p.relic_charge, "hurt": p.actor.hurt_time})
	for id in enemies:
		var e: Dictionary = enemies[id]
		state.enemies.append({"id": id, "position": e.actor.position, "kind": e.kind, "hp": e.hp, "max_hp": e.max_hp,
			"windup": e.windup, "state": e.state, "telegraph_direction": e.telegraph_direction,
			"telegraph_progress": e.telegraph_progress, "telegraph_range": e.telegraph_range,
			"telegraph_radius": e.telegraph_radius, "burning": combat.burns.has(id), "hurt": e.actor.hurt_time})
	for id in loot:
		var drop: Dictionary = loot[id]
		state.loot.append({"id": id, "position": drop.actor.position, "owner": drop.owner, "coins": drop.coins, "item_id": drop.item_id})
	return state

func apply_snapshot(state: Dictionary, local_id: int) -> bool:
	var incoming_epoch := int(state.get("epoch", 0))
	var sequence := int(state.get("sequence", -1))
	if incoming_epoch < epoch or sequence <= _last_received_sequence:
		return false
	_last_received_sequence = sequence
	var changed_zone: bool = incoming_epoch != epoch or current_zone != str(state.zone)
	if changed_zone:
		_clear_combat_events()
		_clear_entities(enemies)
		_clear_entities(loot)
		current_zone = state.zone
		epoch = incoming_epoch
		zone.build(current_zone)
	world_data = state.world.duplicate(true)
	var seen: Array = []
	for data in state.players:
		var id := int(data.id)
		seen.append(id)
		if not players.has(id):
			add_player(id, data.profile)
			players[id].actor.position = data.position
		var p: Dictionary = players[id]
		p.profile = data.profile
		p.hp = data.hp
		p.max_hp = data.max_hp
		p.aim = data.facing
		p.relic_charge = int(data.get("charge", 0))
		var actor: CharacterBody2D = p.actor
		actor.target_position = data.position
		if changed_zone:
			actor.position = data.position
		actor.facing = data.facing
		actor.hp = data.hp
		actor.max_hp = data.max_hp
		actor.display_name = data.name
		actor.local_player = id == local_id
		actor.slash_time = maxf(actor.slash_time, float(data.slash))
		actor.weapon_kind = Catalog.get_item(p.profile.equipped_weapon).weapon_kind
		actor.relic_charge = p.relic_charge
		actor.hurt_time = maxf(actor.hurt_time, float(data.get("hurt", 0)))
	_remove_absent(players, seen)
	seen.clear()
	for data in state.enemies:
		var id := int(data.id)
		seen.append(id)
		if not enemies.has(id):
			enemies[id] = {"actor": _make_actor(data.kind, data.position), "kind": data.kind}
		var e: Dictionary = enemies[id]
		e.hp = data.hp
		e.max_hp = data.max_hp
		e.actor.target_position = data.position
		e.actor.hp = data.hp
		e.actor.max_hp = data.max_hp
		e.actor.windup = data.windup
		e.actor.boss_state = data.get("state", "chase")
		e.actor.telegraph_direction = data.get("telegraph_direction", Vector2.RIGHT)
		e.actor.telegraph_progress = data.get("telegraph_progress", 0.0)
		e.actor.telegraph_range = data.get("telegraph_range", 360.0)
		e.actor.telegraph_radius = data.get("telegraph_radius", 115.0)
		e.actor.burning = data.get("burning", false)
		e.actor.hurt_time = maxf(e.actor.hurt_time, float(data.get("hurt", 0)))
	_remove_absent(enemies, seen)
	seen.clear()
	for data in state.loot:
		var id := int(data.id)
		seen.append(id)
		if not loot.has(id):
			var view := Loot.new()
			view.position = data.position
			if str(data.item_id) != "":
				view.tint = Catalog.get_item(data.item_id).color
			actors.add_child(view)
			loot[id] = {"actor": view, "owner": data.owner, "coins": data.coins, "item_id": data.item_id}
		loot[id].actor.visible = int(data.owner) == local_id
	_remove_absent(loot, seen)
	effects.set_projectiles(state.get("projectiles", []))
	for event in state.get("events", []):
		if int(event.id) > _last_received_event:
			_last_received_event = int(event.id)
			effects.play_event(event)
	return true

func emit_combat_event(event: Dictionary) -> void:
	_next_event_id += 1
	var data := event.duplicate(true)
	data["id"] = _next_event_id
	_combat_events.append({"event": data, "remaining": 0.65})
	if _combat_events.size() > 32:
		_combat_events.pop_front()
	effects.play_event(data)

func _step_events(delta: float) -> void:
	for entry in _combat_events:
		entry.remaining -= delta
	while not _combat_events.is_empty() and float(_combat_events[0].remaining) <= 0:
		_combat_events.pop_front()

func _clear_combat_events() -> void:
	_combat_events.clear()
	_last_received_event = 0
	effects.clear_effects()
	effects.set_projectiles([])

func _update_enemy_view(enemy: Dictionary) -> void:
	var actor: CharacterBody2D = enemy.actor
	actor.hp = enemy.hp
	actor.max_hp = enemy.max_hp
	actor.windup = enemy.windup
	actor.boss_state = enemy.state
	actor.telegraph_direction = enemy.telegraph_direction
	actor.telegraph_progress = enemy.telegraph_progress
	actor.telegraph_range = enemy.telegraph_range
	actor.telegraph_radius = enemy.telegraph_radius
	# Dictionaries are keyed by entity ID, so look up the visual's ID once at spawn.
	actor.burning = combat.burns.has(int(actor.get_meta("entity_id", 0)))

func _make_actor(kind: String, point: Vector2, peer_id: int = 0) -> CharacterBody2D:
	var actor := Actor.new()
	actor.kind = kind
	actor.position = point
	actor.simulated = authoritative
	actor.radius = 30.0 if kind == "boss" else 15.0
	actor.tint = COLORS[players.size() % COLORS.size()] if kind == "player" else (Color("ab8ade") if kind == "boss" else (Color("dbad75") if kind == "guard" else Color("719c8a")))
	actor.local_player = peer_id == 1 and authoritative
	actors.add_child(actor)
	return actor

func _nearest_player(point: Vector2) -> int:
	var nearest := 0
	var distance := INF
	for id in players:
		var candidate: float = point.distance_squared_to(players[id].actor.position)
		if candidate < distance:
			distance = candidate
			nearest = id
	return nearest

func _clamp_actor(actor: CharacterBody2D) -> void:
	var rect: Rect2 = zone.get_walk_rect().grow(-float(actor.radius))
	actor.position = actor.position.clamp(rect.position, rect.end)

func _level(profile: Dictionary) -> int:
	return mini(20, 1 + int(profile.xp) / 40)

func _max_hp(profile: Dictionary) -> float:
	return 100.0 + (_level(profile) - 1) * 5.0

func _destroy(node: Node) -> void:
	if is_instance_valid(node):
		node.get_parent().remove_child(node)
		node.queue_free()

func _clear_entities(collection: Dictionary) -> void:
	for id in collection:
		_destroy(collection[id].actor)
	collection.clear()

func _remove_absent(collection: Dictionary, seen: Array) -> void:
	for id in collection.keys():
		if not seen.has(id):
			_destroy(collection[id].actor)
			collection.erase(id)
