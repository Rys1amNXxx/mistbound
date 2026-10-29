extends Node2D
## Composition root: presentation/input, authoritative simulation, transport, persistence.

const Simulation = preload("res://scripts/systems/world_simulation.gd")
const Session = preload("res://scripts/systems/game_session.gd")
const Interface = preload("res://scripts/ui/game_ui.gd")
const Catalog = preload("res://scripts/systems/item_catalog.gd")

var simulation: Node2D
var session: Node
var ui: CanvasLayer
var camera: Camera2D
var _input_timer: float = 0.0
var _hud_timer: float = 0.0

func _ready() -> void:
	get_tree().auto_accept_quit = false
	simulation = Simulation.new()
	simulation.name = "World"
	add_child(simulation)
	session = Session.new()
	session.name = "Session"
	add_child(session)
	session.configure(simulation)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 8.0
	camera.zoom = Vector2(0.95, 0.95)
	add_child(camera)
	ui = Interface.new()
	add_child(ui)
	ui.solo_requested.connect(func(): session.start_solo())
	ui.host_requested.connect(_host)
	ui.join_requested.connect(_join)
	ui.leave_requested.connect(func(): session.stop())
	ui.equip_requested.connect(func(id: String): session.action("equip", id))
	ui.save_requested.connect(func():
		if session.save_now():
			ui.notify("角色进度已保存" if session.mode == "client" else "角色和世界进度已保存"))
	session.started.connect(func():
		ui.show_game()
		_update_hud()
		camera.reset_smoothing())
	session.ended.connect(func(reason: String): ui.show_menu(reason))
	session.message.connect(func(text: String):
		if ui.is_menu_open():
			ui.set_status(text)
		else:
			ui.notify(text))
	_parse_arguments.call_deferred()

func _host(port: int) -> void:
	var error: Error = session.host(port)
	if error != OK:
		ui.set_status("创建失败：%s。端口可能已占用。" % error_string(error))

func _join(address: String, port: int) -> void:
	var error: Error = session.join(address, port)
	ui.set_status("正在连接 %s:%d …" % [address, port] if error == OK else "连接失败：" + error_string(error))

func _process(delta: float) -> void:
	if not session.active:
		return
	_input_timer += delta
	_hud_timer += delta
	var id: int = session.local_id
	if simulation.players.has(id):
		var actor: Node2D = simulation.players[id].actor
		var bounds: Rect2 = simulation.zone.get_walk_rect()
		camera.limit_left = int(bounds.position.x)
		camera.limit_top = int(bounds.position.y)
		camera.limit_right = int(bounds.end.x)
		camera.limit_bottom = int(bounds.end.y)
		camera.position = actor.position
		for drop in simulation.loot.values():
			drop.actor.visible = int(drop.owner) == id
		if _input_timer >= 0.033:
			_input_timer = 0.0
			var motion := Vector2.ZERO
			var attacking := false
			if not ui.blocks_gameplay_input():
				motion = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)), float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))).normalized()
				attacking = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and get_viewport().gui_get_hovered_control() == null
			session.send_input(motion, get_global_mouse_position() - actor.position, attacking)
	if _hud_timer >= 0.1:
		_hud_timer = 0.0
		_update_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not session.active or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_I, KEY_ESCAPE:
			ui.toggle_inventory()
		KEY_E:
			if not ui.blocks_gameplay_input():
				session.action("interact")
		KEY_SPACE:
			if not ui.blocks_gameplay_input():
				session.action("dash")
		KEY_Q:
			if not ui.blocks_gameplay_input():
				_switch_weapon()

func _switch_weapon() -> void:
	if not simulation.players.has(session.local_id):
		return
	var profile: Dictionary = simulation.players[session.local_id].profile
	var weapons: Array[String] = []
	for item in Catalog.all_items():
		if item.slot == "weapon" and int(profile.inventory.get(item.id, 0)) > 0:
			weapons.append(item.id)
	if weapons.size() > 1:
		var next: int = (weapons.find(str(profile.equipped_weapon)) + 1) % weapons.size()
		session.action("equip", weapons[next])

func _update_hud() -> void:
	var id: int = session.local_id
	if not simulation.players.has(id):
		return
	var player: Dictionary = simulation.players[id]
	var profile: Dictionary = player.profile
	var inventory: Array = []
	for item in Catalog.all_items():
		var count := int(profile.inventory.get(item.id, 0))
		if count > 0:
			inventory.append({"id": item.id, "name": item.display_name, "description": item.description,
				"count": count, "slot": item.slot,
				"equipped": profile.equipped_weapon == item.id or profile.equipped_relic == item.id})
	var objective: String
	match simulation.current_zone:
		"camp": objective = "Q 切换剑与弩，I 查看武器和遗物。沿石路向北按 E 进入林地。"
		"wilds": objective = "探索林地：西北通往琥珀矿井，东北通往回声地窟。房主开启入口。"
		_: objective = "避开首领的冲锋走廊和重击圆圈。拾取遗物后在背包装备，再挑战一轮。"
	var weapon: Resource = Catalog.get_item(profile.equipped_weapon)
	var relic: Resource = Catalog.get_item(profile.equipped_relic)
	ui.update_hud({"zone_title": simulation.zone.get_title(), "mode": {"offline": "单人探索", "host": "房主", "client": "好友房间"}[session.mode],
		"player_count": simulation.players.size(), "hp": player.hp, "max_hp": player.max_hp,
		"coins": profile.coins, "level": mini(20, 1 + int(profile.xp) / 40), "xp": profile.xp,
		"weapon_name": weapon.display_name, "weapon_kind": weapon.weapon_kind,
		"relic_name": relic.display_name if relic != null else "未装备", "relic_charge": player.relic_charge,
		"equipped_name": weapon.display_name, "objective": objective,
		"interaction": simulation.interaction_for(id), "inventory": inventory, "boss_kills": simulation.world_data.get("boss_kills", 0)})

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if session != null:
			session.save_now()
		get_tree().quit()

func _parse_arguments() -> void:
	var port := 24570
	var args := OS.get_cmdline_user_args()
	for argument in args:
		if argument.begins_with("--port="):
			port = argument.trim_prefix("--port=").to_int()
	for argument in args:
		if argument == "--solo":
			session.start_solo()
		elif argument == "--host":
			_host(port)
		elif argument.begins_with("--join="):
			_join(argument.trim_prefix("--join="), port)
