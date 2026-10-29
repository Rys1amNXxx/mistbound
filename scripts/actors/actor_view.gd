class_name ActorView
extends CharacterBody2D
## Shared lightweight view. Only the host drives CharacterBody2D movement.

var kind: String = "player"
var display_name: String = "旅人"
var tint: Color = Color("7ce0cc")
var hp: float = 100.0
var max_hp: float = 100.0
var facing: Vector2 = Vector2.RIGHT
var target_position: Vector2
var simulated: bool = true
var local_player: bool = false
var slash_time: float = 0.0
var hurt_time: float = 0.0
var windup: float = 0.0
var radius: float = 15.0
var weapon_kind: String = "melee"
var burning: bool = false
var relic_charge: int = 0
var boss_state: String = "chase"
var telegraph_direction: Vector2 = Vector2.RIGHT
var telegraph_progress: float = 0.0
var telegraph_range: float = 360.0
var telegraph_radius: float = 115.0
var _clock: float = 0.0
var _font: SystemFont

func _ready() -> void:
	collision_layer = 2 if kind == "player" else 4
	collision_mask = 1
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	add_child(shape)
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC"])
	target_position = position

func _process(delta: float) -> void:
	_clock += delta
	slash_time = maxf(0.0, slash_time - delta)
	hurt_time = maxf(0.0, hurt_time - delta)
	if not simulated:
		if position.distance_to(target_position) > 250.0:
			position = target_position
		else:
			position = position.lerp(target_position, 1.0 - exp(-18.0 * delta))
	queue_redraw()

func _draw() -> void:
	var body_color := tint.lightened(0.5) if hurt_time > 0.0 else tint
	if kind == "boss" and boss_state == "recovery" and hurt_time <= 0.0:
		body_color = body_color.darkened(0.35)
	draw_set_transform(Vector2(0, 11), 0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, radius + 9, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO)
	if kind == "boss":
		_draw_boss_telegraph()
	if local_player:
		draw_arc(Vector2(0, 6), radius + 8, 0, TAU, 36, Color(0.6, 0.93, 0.8, 0.7), 1.5, true)
	if kind == "player":
		var coat := PackedVector2Array([Vector2(-13, 10), Vector2(-10, -9), Vector2(0, -17), Vector2(10, -9), Vector2(13, 10), Vector2(0, 15)])
		draw_colored_polygon(coat, body_color.darkened(0.3))
		draw_circle(Vector2(0, -9), 9, Color("d9c8aa"))
		draw_arc(Vector2(0, -9), 10, PI, TAU, 14, body_color, 5, true)
		if weapon_kind in ["projectile", "ranged", "crossbow", "bow"]:
			_draw_crossbow()
		else:
			var direction := _normalized(facing)
			draw_line(Vector2(4, 2), Vector2(4, 2) + direction * 27, Color("e8debc"), 4, true)
			draw_line(Vector2(4, 2) + direction * 6 - direction.orthogonal() * 5, Vector2(4, 2) + direction * 6 + direction.orthogonal() * 5, Color("b48b55"), 3, true)
			draw_circle(Vector2(4, 2) + direction * 4, 4, Color("d1a36e"))
	elif kind == "slime":
		draw_set_transform(Vector2(0, 2), 0, Vector2(1.0, 0.85 + sin(_clock * 3) * 0.06))
		draw_circle(Vector2.ZERO, radius, body_color)
		draw_arc(Vector2(-2, -3), radius - 5, PI, PI * 1.7, 12, body_color.lightened(0.3), 2, true)
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2(-5, 0), 2, Color("11242c"))
		draw_circle(Vector2(5, 0), 2, Color("11242c"))
	else:
		var points := PackedVector2Array()
		for i in range(6):
			points.append(Vector2.from_angle(TAU * i / 6.0 - PI / 2) * radius)
		draw_colored_polygon(points, body_color.darkened(0.2))
		draw_polyline(points + PackedVector2Array([points[0]]), body_color, 2, true)
		draw_line(Vector2(-8, -2), Vector2(8, -2), Color("ffcf88"), 3, true)
		if kind == "boss":
			draw_arc(Vector2.ZERO, radius + 9, _clock * 0.25, _clock * 0.25 + PI * 1.5, 32, tint.darkened(0.1), 2, true)
	if burning and kind != "player":
		_draw_burning()
	if windup > 0.0 and kind != "boss":
		draw_circle(Vector2.ZERO, 56, Color(0.94, 0.35, 0.27, 0.13))
		draw_arc(Vector2.ZERO, 56, 0, TAU, 48, Color("ee8864"), 2, true)
	if slash_time > 0.0 and kind == "player" and weapon_kind not in ["projectile", "ranged", "crossbow", "bow"]:
		var angle := facing.angle()
		draw_arc(Vector2.ZERO, 85, angle - 0.9, angle + 0.9, 20, Color(1.0, 0.89, 0.61, clampf(slash_time / 0.18, 0.0, 1.0)), 6, true)
	if hp < max_hp or kind == "boss":
		var width := 52.0 if kind == "boss" else 34.0
		draw_rect(Rect2(-width / 2, -radius - 13, width, 4), Color("132329"))
		draw_rect(Rect2(-width / 2, -radius - 13, width * clampf(hp / maxf(max_hp, 1.0), 0, 1), 4), Color("dfa474"))
	if kind == "player" and _font:
		var text_width := _font.get_string_size(display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		draw_string(_font, Vector2(-text_width / 2, -32), display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("dae6dd"))
		if local_player and relic_charge > 0:
			for index in range(3):
				var center := Vector2((index - 1) * 10, radius + 16)
				var points := PackedVector2Array([center + Vector2(0, -3), center + Vector2(3, 0), center + Vector2(0, 3), center + Vector2(-3, 0)])
				draw_colored_polygon(points, Color("9be8ed") if index < relic_charge else Color("38565d"))


func _draw_crossbow() -> void:
	var flash := clampf(slash_time / 0.18, 0.0, 1.0)
	draw_set_transform(Vector2(4, 2) - _normalized(facing) * flash * 3.0, facing.angle())
	draw_line(Vector2(-5, 0), Vector2(24, 0), Color("c5a176"), 6, true)
	draw_line(Vector2(-2, 0), Vector2(27, 0), Color("ece0bb"), 2, true)
	var limbs := PackedVector2Array([Vector2(9, -15), Vector2(18, -10), Vector2(20, 0), Vector2(18, 10), Vector2(9, 15)])
	draw_polyline(limbs, Color("7bbeb6"), 4, true)
	draw_polyline(PackedVector2Array([Vector2(9, -15), Vector2(3 - flash * 5, 0), Vector2(9, 15)]), Color("e4d9bb"), 1.2, true)
	draw_circle(Vector2(1, 4), 4, Color("d1a36e"))
	if slash_time > 0.0:
		var flash_color := Color(1.0, 0.91, 0.65, flash)
		draw_line(Vector2(30, 0), Vector2(44, 0), flash_color, 3, true)
		draw_line(Vector2(31, -2), Vector2(37, -7), flash_color, 2, true)
		draw_line(Vector2(31, 2), Vector2(37, 7), flash_color, 2, true)
		draw_arc(Vector2(1, 0), 10, PI * 0.55, PI * 1.45, 12, Color(0.64, 0.87, 0.84, flash * 0.7), 1.5, true)
	draw_set_transform(Vector2.ZERO)


func _draw_boss_telegraph() -> void:
	var progress := clampf(telegraph_progress, 0.0, 1.0)
	var direction := _normalized(telegraph_direction)
	var pulse := 0.72 + sin(_clock * 11.0) * 0.18
	if boss_state == "charge_windup":
		var width := maxf(1.0, telegraph_radius)
		var length := maxf(1.0, telegraph_range)
		draw_set_transform(Vector2.ZERO, direction.angle())
		draw_rect(Rect2(0, -width, length, width * 2), Color(0.95, 0.36, 0.22, 0.13))
		draw_rect(Rect2(0, -width, length * progress, width * 2), Color(1.0, 0.48, 0.25, 0.19))
		draw_rect(Rect2(0, -width, length, width * 2), Color(1.0, 0.61, 0.36, pulse), false, 2, true)
		for index in range(1, 5):
			var x := length * float(index) / 5.0
			draw_polyline(PackedVector2Array([Vector2(x - 9, -8), Vector2(x, 0), Vector2(x - 9, 8)]), Color(1.0, 0.71, 0.45, pulse), 2, true)
		draw_set_transform(Vector2.ZERO)
		_draw_state_label("冲锋蓄力", Color("ffb077"))
	elif boss_state == "slam_windup":
		var size := maxf(1.0, telegraph_radius)
		draw_circle(Vector2.ZERO, size, Color(0.93, 0.29, 0.22, 0.11))
		draw_circle(Vector2.ZERO, size * progress, Color(0.96, 0.38, 0.24, 0.14))
		draw_arc(Vector2.ZERO, size, 0, TAU, 64, Color(1.0, 0.56, 0.37, pulse), 2, true)
		draw_arc(Vector2.ZERO, size * maxf(0.08, progress), 0, TAU, 56, Color(1.0, 0.72, 0.43, 0.8), 2, true)
		for index in range(12):
			var radial := Vector2.from_angle(TAU * index / 12.0)
			draw_line(radial * (size - 6), radial * (size + 4), Color("e9a178"), 2, true)
		_draw_state_label("震地蓄力", Color("ffb077"))
	elif boss_state == "charge":
		draw_set_transform(Vector2.ZERO, direction.angle())
		for index in range(3):
			var y := (index - 1) * radius * 0.65
			draw_line(Vector2(-radius, y), Vector2(-radius - 65 - index * 12, y), Color(1.0, 0.67, 0.37, 0.45), 4 - index, true)
		draw_set_transform(Vector2.ZERO)
		draw_circle(Vector2.ZERO, radius + 6, Color(1.0, 0.58, 0.2, 0.18))
	elif boss_state == "slam":
		draw_circle(Vector2.ZERO, telegraph_radius, Color(1.0, 0.45, 0.18, 0.12))
		draw_arc(Vector2.ZERO, telegraph_radius, 0, TAU, 64, Color("ffd39a"), 3, true)
	elif boss_state == "recovery":
		draw_arc(Vector2.ZERO, radius + 8, 0, TAU, 32, Color(0.67, 0.82, 0.79, 0.4), 1.5, true)
		_draw_state_label("破绽", Color("a6ccc1"))


func _draw_state_label(text: String, color: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(_font, Vector2(-width / 2, -radius - 23), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)


func _draw_burning() -> void:
	for index in range(3):
		var center := Vector2((index - 1) * radius * 0.65, -radius * 0.25)
		var height := 13.0 + sin(_clock * 13.0 + index * 2.1) * 4.0
		var flame := PackedVector2Array([center + Vector2(-5, 5), center + Vector2(-4, -3), center + Vector2(1, -height), center + Vector2(5, 1), center + Vector2(4, 5)])
		draw_colored_polygon(flame, Color(1.0, 0.4, 0.13, 0.82))
		draw_line(center + Vector2(0, 3), center + Vector2(0, -height * 0.45), Color("ffdd82"), 3, true)


func _normalized(direction: Vector2) -> Vector2:
	return direction.normalized() if direction.length_squared() > 0.0001 else Vector2.RIGHT
