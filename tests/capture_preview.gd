extends SceneTree
## Run with the normal renderer, not --headless. The test exits automatically.
## MISTBOUND_CAPTURE_DIR and MISTBOUND_SAVE_DIR must point to isolated directories.

const MainScene := preload("res://scenes/main.tscn")

var _capture_dir: String
var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture_dir = OS.get_environment("MISTBOUND_CAPTURE_DIR").strip_edges()
	if not _capture_dir.is_absolute_path() or OS.get_environment("MISTBOUND_SAVE_DIR").is_empty():
		push_error("Set absolute MISTBOUND_CAPTURE_DIR and isolated MISTBOUND_SAVE_DIR before capture.")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(_capture_dir) != OK:
		push_error("Unable to create preview directory.")
		quit(2)
		return
	root.size = Vector2i(1280, 800)
	var main: Node2D = MainScene.instantiate()
	root.add_child(main)
	await _settle()
	if OS.get_cmdline_user_args().has("--phase1"):
		await _capture_phase1(main)
		print("PREVIEW_CAPTURE_DONE failures=%d" % _failures)
		quit(0 if _failures == 0 else 1)
		return
	await _capture("01-menu.png")
	main.session.start_solo()
	await _settle()
	await _capture("02-camp.png")
	main.simulation.enter_zone("wilds")
	await _settle()
	await _capture("03-wilds.png")
	main.simulation.enter_zone("mine")
	await _settle()
	await _capture("04-mine.png")
	main.ui.toggle_inventory()
	await _settle()
	await _capture("05-inventory.png")
	root.size = Vector2i(1280, 720)
	await _settle()
	await _capture("06-inventory-720.png")
	main.session.stop()
	await _settle()
	await _capture("07-menu-720.png")
	print("PREVIEW_CAPTURE_DONE failures=%d" % _failures)
	quit(0 if _failures == 0 else 1)


func _settle(frames: int = 30) -> void:
	for index in range(frames):
		await process_frame


func _capture_phase1(main: Node2D) -> void:
	await _capture("phase1-01-menu.png")
	main.session.start_solo()
	# Pose deterministic scenes only inside this isolated visual test.
	main.session.set_physics_process(false)
	var player: Dictionary = main.simulation.players[1]
	player.profile.inventory["ember_relic"] = 1
	player.profile.inventory["storm_relic"] = 1
	main.simulation.act(1, "equip", "traveler_blade")
	main.simulation.act(1, "equip", "ember_relic")
	await _settle()
	await _capture("phase1-02-sword.png")
	main.simulation.enter_zone("wilds")
	main.simulation.act(1, "equip", "hunter_crossbow")
	player.actor.facing = Vector2.RIGHT
	await _settle()
	player.actor.slash_time = 0.18
	var at: Vector2 = player.actor.position
	main.simulation.effects.set_projectiles([
		{"id": 901, "position": at + Vector2(80, 0), "direction": Vector2.RIGHT, "owner": 1},
		{"id": 902, "position": at + Vector2(145, 0), "direction": Vector2.RIGHT, "owner": 1},
	])
	main.simulation.effects.play_event({"type": "shot", "position": at + Vector2(30, 2), "direction": Vector2.RIGHT})
	await _capture("phase1-03-crossbow.png")
	main.ui.toggle_inventory()
	await _settle()
	await _capture("phase1-04-two-slots.png")
	var inventory_scroll: ScrollContainer = main.ui._inventory_list.get_parent()
	inventory_scroll.scroll_vertical = 245
	await _settle()
	await _capture("phase1-05-relic-slots.png")
	root.size = Vector2i(1280, 720)
	await _settle()
	await _capture("phase1-06-inventory-720.png")
	main.ui.toggle_inventory()
	root.size = Vector2i(1280, 800)
	main.simulation.enter_zone("mine")
	player.actor.position = Vector2(-220, 35)
	player.actor.target_position = player.actor.position
	var boss: Node2D
	var victim: Node2D
	for enemy: Dictionary in main.simulation.enemies.values():
		if enemy.kind == "boss":
			boss = enemy.actor
			boss.position = Vector2(0, 0)
			boss.hp = enemy.hp
			boss.max_hp = enemy.max_hp
		elif victim == null:
			victim = enemy.actor
			victim.position = Vector2(200, 80)
		else:
			enemy.actor.hide()
	if boss != null:
		boss.boss_state = "charge_windup"
		boss.telegraph_direction = Vector2.RIGHT
		boss.telegraph_progress = 0.65
		boss.telegraph_range = 360
		boss.telegraph_radius = 36
		await _settle()
		await _capture("phase1-07-boss-charge.png")
		boss.boss_state = "slam_windup"
		boss.telegraph_radius = 115
		await _settle()
		await _capture("phase1-08-boss-slam.png")
		boss.boss_state = "recovery"
		boss.burning = true
		if victim != null:
			victim.burning = true
		main.simulation.act(1, "equip", "storm_relic")
		player.relic_charge = 2
		player.actor.relic_charge = 2
		await _settle()
		main.simulation.effects.play_event({"type": "chain", "points": [player.actor.position, boss.position, Vector2(200, 80)]})
		main.simulation.effects.play_event({"type": "hit", "position": boss.position, "damage": 24, "element": "chain"})
		main.simulation.effects.play_event({"type": "hit", "position": Vector2(200, 80), "damage": 5, "element": "burn"})
		await _capture("phase1-09-effects.png")
		main.simulation.effects.clear_effects()
		boss.burning = false
		boss.boss_state = "charge"
		await _settle(2)
		main.simulation.effects.play_event({"type": "charge", "position": boss.position, "direction": Vector2.RIGHT})
		await _capture("phase1-10-charge-action.png")
		main.simulation.effects.clear_effects()
		boss.boss_state = "slam"
		await _settle(2)
		main.simulation.effects.play_event({"type": "slam", "position": boss.position, "radius": 115})
		main.simulation.effects.play_event({"type": "hit", "position": boss.position + Vector2(150, 0), "damage": 0, "element": "physical"})
		await _capture("phase1-11-slam-action.png")
	main.session.stop()


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image.is_empty():
		push_error("Empty framebuffer: " + file_name)
		_failures += 1
		return
	var path := _capture_dir.path_join(file_name)
	var error := image.save_png(path)
	if error != OK:
		push_error("Screenshot write failed: %s (%s)" % [path, error_string(error)])
		_failures += 1
	else:
		print("PREVIEW_CAPTURE " + path)
