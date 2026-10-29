extends SceneTree
## Two real ENet peers verify ranged combat, boss warnings, personal loot and saves.
## Only the host arranges encounters; player actions still use real session RPCs.
const Store = preload("res://scripts/systems/save_store.gd")
var game: Node
var role := ""
var port := 24679
var phase := 0
var elapsed := 0.0
var phase_time := 0.0
var first_guest := 0
var target_enemy := 0
var boss_enemy := 0
var target_position := Vector2.ZERO
var observed_disconnect := false
var interact_timer := 0.0
var saw_projectile := false
var saw_shot_event := false
var saw_boss_warning := false
var saw_private_loot := false
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test-role="):
			role = arg.trim_prefix("--test-role=")
		if arg.begins_with("--test-port="):
			port = arg.trim_prefix("--test-port=").to_int()
	if OS.get_environment("MISTBOUND_SAVE_DIR").is_empty():
		push_error("Network tests require isolated MISTBOUND_SAVE_DIR")
		quit(1)
		return
	_boot.call_deferred()

func _boot() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.set_process(false)
	var error: Error = game.session.host(port) if role == "host" else game.session.join("127.0.0.1", port)
	if error != OK:
		_fail("could not open peer: " + error_string(error))

func _process(delta: float) -> bool:
	if game == null or failed:
		return false
	elapsed += delta
	phase_time += delta
	if elapsed > 35.0:
		_fail("timeout in phase %d" % phase)
		return false
	if role == "host":
		_host_step()
	else:
		_observe_client_presentation()
		_client_step(delta)
	return false

func _advance(next: int) -> void:
	phase = next
	phase_time = 0.0
	interact_timer = 0.0
	print("NETWORK %s phase=%d" % [role, phase])

func _host_step() -> void:
	var sim: Node = game.simulation
	if phase >= 1 and phase <= 4 and not sim.players.has(first_guest):
		_fail("guest disconnected before completing the combat scenario")
		return
	match phase:
		0:
			if sim.players.size() == 2:
				for id in sim.players:
					if id != 1:
						first_guest = id
				sim.enter_zone("wilds")
				_advance(1)
		1:
			var guest: Dictionary = sim.players[first_guest]
			if guest.profile.equipped_weapon == "hunter_crossbow" and guest.actor.position.x > 35:
				target_enemy = sim.enemies.keys()[0]
				_remove_other_enemies(target_enemy)
				target_position = Vector2(-220, 95)
				var enemy: Dictionary = sim.enemies[target_enemy]
				enemy.hp = 18.0
				enemy.actor.position = target_position
				guest.actor.position = target_position + Vector2(180, 0)
				guest.invulnerability = 30.0
				_advance(2)
		2:
			_hold_target(target_enemy)
			if int(sim.players[first_guest].profile.coins) >= 6:
				if sim.enemies.has(target_enemy):
					_fail("guest loot arrived without authoritative ranged defeat")
					return
				if sim.players[first_guest].profile.equipped_weapon != "hunter_crossbow":
					_fail("guest weapon equip RPC was not retained by host")
					return
				for portal in sim.zone.get_portals():
					if portal.target == "mine":
						sim.players[1].actor.position = portal.position
						sim.act(1, "interact")
						break
				for id in sim.enemies:
					if sim.enemies[id].kind == "boss":
						boss_enemy = id
				if boss_enemy == 0:
					_fail("mine did not spawn a boss")
					return
				_remove_other_enemies(boss_enemy)
				var boss: Dictionary = sim.enemies[boss_enemy]
				sim.players[first_guest].actor.position = boss.actor.position + Vector2(250, 0)
				sim.players[first_guest].invulnerability = 30.0
				sim.players[1].actor.position = Vector2(0, 330)
				_advance(3)
		3:
			# Allow a full natural charge warning/attack to reach the remote peer.
			if phase_time > 3.0:
				var boss: Dictionary = sim.enemies[boss_enemy]
				boss.hp = 18.0
				boss.state = "recovery"
				boss.state_time = 0.0
				boss.recovery_duration = 30.0
				boss.windup = 0.0
				target_position = Vector2(0, -255)
				boss.actor.position = target_position
				sim.players[first_guest].actor.position = target_position + Vector2(180, 0)
				_advance(4)
		4:
			_hold_target(boss_enemy)
			var profile: Dictionary = sim.players[first_guest].profile
			if profile.equipped_relic == "ember_relic":
				if sim.enemies.has(boss_enemy) or int(profile.inventory.get("ember_relic", 0)) < 1:
					_fail("equipped boss relic without real boss defeat/drop/pickup")
					return
				if profile.equipped_weapon != "hunter_crossbow" or int(profile.coins) < 46:
					_fail("relic equip replaced weapon or lost rewards")
					return
				_advance(5)
		5:
			if not sim.players.has(first_guest):
				observed_disconnect = true
			if observed_disconnect and sim.players.size() == 2:
				for id in sim.players:
					if id != 1 and not _has_saved_loadout(sim.players[id].profile):
						_fail("reconnected guest lost rewards or separate equipment slots")
						return
				_advance(6)
		6:
			if phase_time > 0.7:
				game.session.stop("test host shutdown")
				print("NETWORK HOST PASS: movement, ranged RPC combat, boss warning, real relic drop, separate slots, rejoin")
				quit(0)

func _remove_other_enemies(keep: int) -> void:
	var sim: Node = game.simulation
	for id in sim.enemies.keys():
		if id != keep:
			sim._destroy(sim.enemies[id].actor)
			sim.enemies.erase(id)

func _hold_target(id: int) -> void:
	var sim: Node = game.simulation
	if sim.enemies.has(id):
		sim.enemies[id].actor.position = target_position
		sim.enemies[id].cooldown = 30.0

func _observe_client_presentation() -> void:
	var sim: Node = game.simulation
	var session: Node = game.session
	if not session.active:
		return
	for projectile in sim.effects._projectiles.values():
		if int(projectile.owner) == session.local_id:
			saw_projectile = true
	for event in sim.effects._effects:
		if event.type == "shot":
			saw_shot_event = true
	for enemy in sim.enemies.values():
		var actor: Node = enemy.actor
		if enemy.kind == "boss" and actor.boss_state == "charge_windup":
			if not is_equal_approx(actor.telegraph_range, 360.0) or not is_equal_approx(actor.telegraph_radius, 36.0):
				_fail("boss warning geometry was not replicated")
				return
			if not actor.telegraph_direction.is_normalized() or actor.telegraph_progress < 0.0 or actor.telegraph_progress > 1.0 or actor.windup <= 0.0:
				_fail("boss warning timing or direction was not replicated")
				return
			saw_boss_warning = true
	for drop in sim.loot.values():
		if int(drop.owner) != session.local_id:
			if drop.actor.visible:
				_fail("guest can see another player's private loot")
				return
			saw_private_loot = true

func _client_step(delta: float) -> void:
	var sim: Node = game.simulation
	var session: Node = game.session
	if phase >= 1 and phase <= 7 and not session.active:
		_fail("unexpected disconnection during active scenario")
		return
	match phase:
		0:
			if session.active and sim.current_zone == "wilds":
				if sim.players.size() != 2:
					_fail("initial roster missing host")
					return
				session.action("equip", "hunter_crossbow")
				_advance(1)
		1:
			var player: Dictionary = sim.players[session.local_id]
			if player.profile.equipped_weapon == "hunter_crossbow":
				if player.actor.position.y > 180:
					session.send_input(Vector2.RIGHT, Vector2.RIGHT, false)
				else:
					_advance(2)
		2:
			_shoot_closest()
			if _has_own_drop():
				_advance(3)
		3:
			_pickup_own_drop(delta)
			if sim.current_zone == "mine":
				if int(sim.players[session.local_id].profile.coins) < 6 or not (saw_projectile or saw_shot_event):
					_fail("ranged reward or client projectile/shot presentation was not replicated")
					return
				_advance(4)
		4:
			session.send_input(Vector2.ZERO, Vector2.LEFT, false)
			for enemy in sim.enemies.values():
				if enemy.kind == "boss" and float(enemy.hp) <= 18.0:
					if not saw_boss_warning:
						_fail("client never observed natural boss charge warning")
						return
					_advance(5)
		5:
			_shoot_closest()
			if _has_own_drop("ember_relic"):
				_advance(6)
		6:
			_pickup_own_drop(delta, "ember_relic")
			if int(sim.players[session.local_id].profile.inventory.get("ember_relic", 0)) >= 1:
				_advance(7)
		7:
			session.send_input(Vector2.ZERO, Vector2.LEFT, false)
			# The pickup helper sends equip immediately after interact on the same
			# reliable channel. There is no retry to hide a shared-throttle regression.
			if phase_time > 1.0 and sim.players[session.local_id].profile.equipped_relic != "ember_relic":
				_fail("same-frame pickup then equip was incorrectly throttled")
				return
			if _has_saved_loadout(sim.players[session.local_id].profile):
				if not saw_private_loot or not session.save_now():
					_fail("personal loot isolation or confirmed character save failed")
					return
				if not _has_saved_loadout(Store.load_character()):
					_fail("save did not retain weapon and relic in separate slots")
					return
				if phase_time > 0.3:
					session.stop("test guest reconnect")
					_advance(8)
		8:
			if phase_time > 0.5:
				session.join("127.0.0.1", port)
				_advance(9)
		9:
			if session.active and sim.current_zone == "mine":
				if not _has_saved_loadout(sim.players[session.local_id].profile):
					_fail("rejoin did not restore weapon/relic and confirmed rewards")
					return
				_advance(10)
		10:
			if not session.active:
				if not _has_saved_loadout(Store.load_character()):
					_fail("host disconnect did not preserve confirmed character")
					return
				if Store.load_world().visited != ["camp"]:
					_fail("guest overwrote its own world with host world")
					return
				print("NETWORK CLIENT PASS: ranged visuals, boss telegraph, personal relic, equipment slots, rejoin, own-world isolation")
				quit(0)

func _shoot_closest() -> void:
	var sim: Node = game.simulation
	var session: Node = game.session
	var actor: Node2D = sim.players[session.local_id].actor
	var closest := INF
	var aim := Vector2.LEFT
	for enemy in sim.enemies.values():
		var offset: Vector2 = enemy.actor.position - actor.position
		if offset.length() < closest:
			closest = offset.length()
			aim = offset.normalized()
	session.send_input(Vector2.ZERO, aim, not sim.enemies.is_empty())

func _has_own_drop(item_id: String = "") -> bool:
	for drop in game.simulation.loot.values():
		if int(drop.owner) == game.session.local_id and (item_id.is_empty() or drop.item_id == item_id):
			return true
	return false

func _pickup_own_drop(delta: float, item_id: String = "") -> void:
	var sim: Node = game.simulation
	var session: Node = game.session
	var motion := Vector2.ZERO
	var closest := INF
	for drop in sim.loot.values():
		if int(drop.owner) == session.local_id and (item_id.is_empty() or drop.item_id == item_id):
			var offset: Vector2 = drop.actor.position - sim.players[session.local_id].actor.position
			if offset.length() < closest:
				closest = offset.length()
				motion = offset.normalized() if offset.length() > 38 else Vector2.ZERO
	session.send_input(motion, Vector2.LEFT, false)
	# Wait until firmly in pickup range so this regression really submits the
	# interact/equip pair together, rather than collecting earlier at 38–65 px.
	if not item_id.is_empty() and closest > 38.0:
		return
	interact_timer += delta
	if interact_timer > 0.2:
		interact_timer = 0.0
		session.action("interact")
		if not item_id.is_empty() and closest <= 38.0:
			session.action("equip", item_id)

func _has_saved_loadout(profile: Dictionary) -> bool:
	return int(profile.coins) >= 46 and profile.equipped_weapon == "hunter_crossbow" and profile.equipped_relic == "ember_relic" and int(profile.inventory.get("ember_relic", 0)) >= 1

func _fail(reason: String) -> void:
	if failed:
		return
	failed = true
	push_error("NETWORK %s FAIL: %s" % [role, reason])
	quit(1)
