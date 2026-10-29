class_name ZoneView
extends Node2D
## Hand-authored area layouts and presentation. The session owns transitions and loot.
## Every peer builds the same static geometry from the zone ID.

const WALK_RECT := Rect2(-880.0, -500.0, 1760.0, 1000.0)
const ZONE_TITLES := {
	"camp": "余烬营地",
	"wilds": "低语林地",
	"mine": "琥珀矿井",
	"crypt": "回声地窟",
}

var zone_id: String = "camp"
var _portals: Array[Dictionary] = []
var _enemy_spawns: Array[Dictionary] = []
var _blockers: Array[Rect2] = []
var _spawn: Vector2 = Vector2(0.0, 180.0)
var _clock: float = 0.0
var _font: Font


func _ready() -> void:
	_ensure_font()
	if _portals.is_empty():
		build(zone_id)


func build(next_zone: String) -> void:
	zone_id = next_zone if ZONE_TITLES.has(next_zone) else "camp"
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_portals.clear()
	_enemy_spawns.clear()
	_blockers.clear()
	_clock = 0.0
	_ensure_font()
	_spawn = Vector2(0.0, 280.0)
	match zone_id:
		"camp":
			_spawn = Vector2(0.0, 170.0)
			_add_portal("camp_to_wilds", "低语林地", "wilds", Vector2(0.0, -340.0))
			_blockers.assign([
				Rect2(-570.0, -10.0, 210.0, 150.0),
				Rect2(360.0, -10.0, 210.0, 150.0),
				Rect2(-525.0, -295.0, 170.0, 105.0),
			])
		"wilds":
			_add_portal("wilds_to_camp", "余烬营地", "camp", Vector2(0.0, 405.0))
			_add_portal("wilds_to_mine", "琥珀矿井 · 小副本", "mine", Vector2(-620.0, -285.0))
			_add_portal("wilds_to_crypt", "回声地窟 · 小副本", "crypt", Vector2(620.0, -285.0))
			_blockers.assign([
				Rect2(-470.0, 65.0, 100.0, 75.0),
				Rect2(375.0, 65.0, 100.0, 75.0),
				Rect2(-65.0, -310.0, 130.0, 85.0),
			])
			_add_enemy(Vector2(-220.0, 95.0), "slime")
			_add_enemy(Vector2(240.0, 60.0), "slime")
			_add_enemy(Vector2(-430.0, -170.0), "slime")
			_add_enemy(Vector2(420.0, -170.0), "slime")
			_add_enemy(Vector2(-160.0, -165.0), "guard")
			_add_enemy(Vector2(190.0, -170.0), "guard")
		"mine":
			_add_portal("mine_to_wilds", "返回低语林地", "wilds", Vector2(0.0, 405.0))
			_blockers.assign([
				Rect2(-550.0, 5.0, 150.0, 95.0),
				Rect2(420.0, 5.0, 150.0, 95.0),
				Rect2(-650.0, -305.0, 110.0, 75.0),
			])
			_add_enemy(Vector2(-230.0, 100.0), "slime")
			_add_enemy(Vector2(250.0, 80.0), "slime")
			_add_enemy(Vector2(-330.0, -110.0), "guard")
			_add_enemy(Vector2(330.0, -110.0), "guard")
			_add_enemy(Vector2(0.0, -255.0), "boss")
		"crypt":
			_add_portal("crypt_to_wilds", "返回低语林地", "wilds", Vector2(0.0, 405.0))
			_blockers.assign([
				Rect2(-500.0, 10.0, 90.0, 130.0),
				Rect2(410.0, 10.0, 90.0, 130.0),
				Rect2(-500.0, -305.0, 90.0, 130.0),
				Rect2(410.0, -305.0, 90.0, 130.0),
			])
			_add_enemy(Vector2(-245.0, 95.0), "guard")
			_add_enemy(Vector2(245.0, 95.0), "guard")
			_add_enemy(Vector2(-250.0, -140.0), "slime")
			_add_enemy(Vector2(250.0, -140.0), "slime")
			_add_enemy(Vector2(0.0, -270.0), "boss")
	# Walls sit outside WALK_RECT; its interior remains identical on all peers.
	_add_collision(Rect2(-944.0, -564.0, 64.0, 1128.0))
	_add_collision(Rect2(880.0, -564.0, 64.0, 1128.0))
	_add_collision(Rect2(-880.0, -564.0, 1760.0, 64.0))
	_add_collision(Rect2(-880.0, 500.0, 1760.0, 64.0))
	for rect in _blockers:
		_add_collision(rect)
	queue_redraw()


func get_spawn(index: int = 0) -> Vector2:
	# A short row prevents co-op arrivals from completely covering one another.
	return _spawn + Vector2(float(index % 4) * 45.0 - 45.0, float(index / 4) * 42.0)


func get_enemy_spawns() -> Array:
	return _enemy_spawns.duplicate(true)


func get_portals() -> Array:
	return _portals.duplicate(true)


func get_walk_rect() -> Rect2:
	return WALK_RECT


func get_title() -> String:
	return str(ZONE_TITLES.get(zone_id, "未知区域"))


func _ensure_font() -> void:
	if _font == null:
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
		_font = font


func _add_portal(id: String, label: String, target: String, point: Vector2) -> void:
	_portals.append({"id": id, "label": label, "target": target, "position": point, "radius": 92.0})


func _add_enemy(point: Vector2, kind: String) -> void:
	_enemy_spawns.append({"position": point, "kind": kind})


func _add_collision(rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = rect.get_center()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var collider := CollisionShape2D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	if _font == null:
		return
	var palette: Dictionary = _get_palette()
	var floor_color: Color = palette["floor"]
	var line_color: Color = palette["line"]
	var accent: Color = palette["accent"]
	draw_rect(Rect2(-2000.0, -1500.0, 4000.0, 3000.0), Color("10191c"))
	draw_rect(WALK_RECT, floor_color)
	_draw_floor(floor_color, line_color)
	match zone_id:
		"camp": _draw_camp()
		"wilds": _draw_wilds()
		"mine": _draw_mine()
		"crypt": _draw_crypt()
	_draw_border(accent)
	for portal in _portals:
		_draw_portal(portal, accent)
	_draw_area_caption(accent)


func _get_palette() -> Dictionary:
	match zone_id:
		"wilds":
			return {"floor": Color("182d2b"), "line": Color("243b35"), "accent": Color("8bc8aa")}
		"mine":
			return {"floor": Color("302b27"), "line": Color("3b342c"), "accent": Color("e1ba77")}
		"crypt":
			return {"floor": Color("282a3b"), "line": Color("343649"), "accent": Color("b9a4e5")}
	return {"floor": Color("23332f"), "line": Color("2c4037"), "accent": Color("e3c18b")}


func _draw_floor(floor_color: Color, line_color: Color) -> void:
	for x in range(-880, 880, 80):
		for y in range(-500, 500, 80):
			var seed_number: int = absi(x * 17 + y * 53)
			if seed_number % 7 < 2:
				draw_rect(Rect2(float(x), float(y), 78.0, 78.0), floor_color.lightened(0.018))
			if zone_id == "mine" or zone_id == "crypt":
				draw_line(Vector2(x, y), Vector2(x + 78, y), line_color, 1.0)
				draw_line(Vector2(x, y), Vector2(x, y + 78), line_color, 1.0)
			elif seed_number % 5 == 0:
				var p := Vector2(x + 23, y + 36)
				draw_line(p, p + Vector2(-3.0, -9.0), line_color.lightened(0.05), 2.0)
				draw_line(p, p + Vector2(4.0, -7.0), line_color.lightened(0.05), 2.0)


func _draw_path(points: PackedVector2Array, color: Color, width: float = 90.0) -> void:
	draw_polyline(points, color.darkened(0.22), width + 18.0, true)
	draw_polyline(points, color, width, true)
	draw_polyline(points, color.lightened(0.035), width * 0.48, true)


func _draw_camp() -> void:
	_draw_path(PackedVector2Array([Vector2(0, 400), Vector2(0, 90), Vector2(0, -340)]), Color("465044"), 118.0)
	_draw_path(PackedVector2Array([Vector2(-440, 155), Vector2(0, 90), Vector2(440, 155)]), Color("414b40"), 82.0)
	draw_circle(Vector2(0, 85), 155.0, Color("515547"))
	draw_arc(Vector2(0, 85), 152.0, 0.0, TAU, 64, Color("79806a"), 2.0, true)
	draw_arc(Vector2(0, 85), 133.0, 0.0, TAU, 64, Color("656b58"), 1.0, true)
	_draw_tent(Vector2(-465, 65), Color("547668"))
	_draw_tent(Vector2(465, 65), Color("8b7653"))
	_draw_label(Vector2(-465, 195), "旅人仓库", Color("b9c9b8"), 19)
	_draw_label(Vector2(465, 195), "工匠营帐", Color("d5c3a0"), 19)
	_draw_house(Vector2(-440, -245))
	_draw_label(Vector2(-440, -155), "旧日瞭望所", Color("a8b9aa"), 18)
	_draw_fire(Vector2(0, 50))
	for p in [Vector2(-155, -95), Vector2(155, -95), Vector2(-145, 260), Vector2(145, 260)]:
		_draw_lantern(p, Color("edba74"))
	for i in range(10):
		_draw_tree(Vector2(-760 + (i % 2) * 105, -400 + i * 86), 0.9 + float(i % 3) * 0.1)
		_draw_tree(Vector2(725 + (i % 2) * 65, -410 + i * 90), 0.8 + float(i % 3) * 0.1)


func _draw_wilds() -> void:
	_draw_path(PackedVector2Array([Vector2(0, 430), Vector2(0, 175), Vector2(-160, -20), Vector2(-620, -285)]), Color("3b4b3d"))
	_draw_path(PackedVector2Array([Vector2(0, 175), Vector2(160, -20), Vector2(620, -285)]), Color("3b4b3d"))
	# A ruined waystone is the visual anchor between the two dungeon routes.
	_draw_rock(Rect2(-65, -310, 130, 85), Color("596961"))
	draw_colored_polygon(PackedVector2Array([Vector2(-23, -264), Vector2(-17, -360), Vector2(18, -376), Vector2(28, -264)]), Color("73867c"))
	draw_line(Vector2(-1, -345), Vector2(4, -288), Color("8bc8aa"), 3.0, true)
	_draw_label(Vector2(0, -205), "失落路标", Color("879f90"), 16)
	_draw_rock(_blockers[0], Color("46584e"))
	_draw_rock(_blockers[1], Color("46584e"))
	for i in range(13):
		_draw_tree(Vector2(-790 + (i % 3) * 38, -430 + i * 70), 0.78 + float(i % 3) * 0.12)
		_draw_tree(Vector2(740 + (i % 2) * 57, -435 + i * 72), 0.85 + float(i % 2) * 0.15)
	for p in [Vector2(-370, 315), Vector2(420, 320), Vector2(-295, -385), Vector2(300, -380)]:
		_draw_tree(p, 1.0)
	_draw_arch(Vector2(-620, -285), Color("887857"))
	_draw_arch(Vector2(620, -285), Color("77738e"))
	for i in range(18):
		var p := Vector2(-640.0 + float((i * 173) % 1250), -330.0 + float((i * 97) % 690))
		var opacity: float = 0.3 + sin(_clock * 1.2 + float(i)) * 0.15
		draw_circle(p + Vector2(sin(_clock + i) * 5.0, cos(_clock * 0.7 + i) * 7.0), 2.0, Color(0.65, 0.83, 0.59, opacity))


func _draw_mine() -> void:
	_draw_path(PackedVector2Array([Vector2(0, 430), Vector2(0, -330)]), Color("494238"), 170.0)
	for y in range(-390, 390, 40):
		draw_line(Vector2(-45, y), Vector2(45, y), Color("766044"), 5.0)
	draw_line(Vector2(-32, -390), Vector2(-32, 380), Color("8d8c78"), 4.0)
	draw_line(Vector2(32, -390), Vector2(32, 380), Color("8d8c78"), 4.0)
	draw_circle(Vector2(0, -255), 135.0, Color("3a332a"))
	draw_arc(Vector2(0, -255), 132.0, 0.0, TAU, 64, Color("716044"), 2.0, true)
	for rect in _blockers:
		_draw_rock(rect, Color("685a43"))
	for p in [Vector2(-680, 300), Vector2(665, 275), Vector2(-730, -150), Vector2(715, -210), Vector2(-290, -390), Vector2(290, -400)]:
		_draw_crystal(p, Color("dcac65"), 1.0)
	for p in [Vector2(-280, 255), Vector2(280, 255), Vector2(-580, -380), Vector2(580, -380)]:
		_draw_lantern(p, Color("dba661"))
	_draw_label(Vector2(0, -430), "矿脉深处", Color("b09b75"), 18)


func _draw_crypt() -> void:
	_draw_path(PackedVector2Array([Vector2(0, 435), Vector2(0, -325)]), Color("424159"), 210.0)
	for y in range(-400, 380, 65):
		draw_line(Vector2(-100, y), Vector2(100, y), Color("56536d"), 2.0)
	var center := Vector2(0, -270)
	draw_circle(center, 155.0, Color("363449"))
	draw_arc(center, 148.0, 0.0, TAU, 72, Color("827199"), 2.0, true)
	draw_arc(center, 127.0, 0.0, TAU, 72, Color("635578"), 1.0, true)
	for i in range(8):
		var direction := Vector2.from_angle(float(i) * TAU / 8.0)
		draw_line(center + direction * 128.0, center + direction * 147.0, Color("a88fbd"), 3.0, true)
	for rect in _blockers:
		_draw_pillar(rect)
	for p in [Vector2(-620, -350), Vector2(620, -350), Vector2(-620, 280), Vector2(620, 280)]:
		_draw_crystal(p, Color("a792d6"), 0.8)
	for p in [Vector2(-270, 270), Vector2(270, 270), Vector2(-275, -330), Vector2(275, -330)]:
		_draw_lantern(p, Color("b3a3e3"))
	_draw_label(Vector2(0, -455), "沉睡者的回声", Color("b4a6cb"), 18)


func _draw_border(accent: Color) -> void:
	draw_rect(WALK_RECT, accent.darkened(0.72), false, 7.0)
	for x in range(-880, 881, 110):
		draw_line(Vector2(x, -500), Vector2(x, -487), accent.darkened(0.5), 3.0)
		draw_line(Vector2(x, 500), Vector2(x, 487), accent.darkened(0.5), 3.0)
	for y in range(-500, 501, 100):
		draw_line(Vector2(-880, y), Vector2(-867, y), accent.darkened(0.5), 3.0)
		draw_line(Vector2(880, y), Vector2(867, y), accent.darkened(0.5), 3.0)


func _draw_portal(portal: Dictionary, accent: Color) -> void:
	var p: Vector2 = portal["position"]
	var pulse: float = sin(_clock * 2.2) * 0.08 + 0.2
	draw_circle(p, 56.0, Color(accent, 0.06))
	draw_circle(p, 42.0, Color(accent, pulse))
	draw_arc(p, 43.0, 0.0, TAU, 64, Color(accent, 0.8), 2.0, true)
	draw_arc(p, 50.0, _clock * 0.3, _clock * 0.3 + PI * 1.1, 48, Color(accent, 0.45), 1.5, true)
	var diamond := PackedVector2Array([p + Vector2(0, -15), p + Vector2(10, 0), p + Vector2(0, 15), p + Vector2(-10, 0)])
	draw_colored_polygon(diamond, accent)
	_draw_label(p + Vector2(0, 79), str(portal["label"]), accent.lightened(0.1), 18)


func _draw_area_caption(accent: Color) -> void:
	_draw_label(Vector2(-675, 410), get_title(), Color(accent, 0.38), 22)
	var caption: String = "休息 · 整备 · 出发" if zone_id == "camp" else "探索 · 战斗 · 寻宝"
	if zone_id == "mine" or zone_id == "crypt":
		caption = "小队副本 · 击败守卫"
	_draw_label(Vector2(-675, 438), caption, Color(accent, 0.28), 15)


func _draw_tree(p: Vector2, scale_factor: float) -> void:
	draw_ellipse_shadow(p + Vector2(0, 17) * scale_factor, Vector2(43, 18) * scale_factor)
	draw_rect(Rect2(p + Vector2(-6, -4) * scale_factor, Vector2(12, 33) * scale_factor), Color("495146"))
	var outer := PackedVector2Array([p + Vector2(0, -76) * scale_factor, p + Vector2(48, 10) * scale_factor, p + Vector2(-48, 10) * scale_factor])
	var middle := PackedVector2Array([p + Vector2(0, -91) * scale_factor, p + Vector2(39, -18) * scale_factor, p + Vector2(-39, -18) * scale_factor])
	draw_colored_polygon(outer, Color("29483c"))
	draw_colored_polygon(middle, Color("355747"))
	draw_line(p + Vector2(0, -86) * scale_factor, p + Vector2(-32, -22) * scale_factor, Color("4a6853"), 2.0)


func draw_ellipse_shadow(p: Vector2, size: Vector2) -> void:
	var points := PackedVector2Array()
	for i in range(24):
		points.append(p + Vector2(cos(float(i) * TAU / 24.0) * size.x, sin(float(i) * TAU / 24.0) * size.y))
	draw_colored_polygon(points, Color(0.02, 0.05, 0.05, 0.26))


func _draw_tent(p: Vector2, tint: Color) -> void:
	draw_rect(Rect2(p + Vector2(-116, -48), Vector2(232, 135)), Color(0.02, 0.04, 0.03, 0.25))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-104, 65), p + Vector2(0, -115), p + Vector2(104, 65)]), tint)
	draw_colored_polygon(PackedVector2Array([p + Vector2(0, -115), p + Vector2(104, 65), p + Vector2(0, 55)]), tint.darkened(0.25))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-30, 65), p + Vector2(0, -15), p + Vector2(30, 65)]), Color("1b2c26"))
	draw_line(p + Vector2(0, -115), p + Vector2(-104, 65), tint.lightened(0.25), 3.0, true)
	draw_line(p + Vector2(-123, 72), p + Vector2(-75, -8), Color("91866b"), 2.0)
	draw_line(p + Vector2(123, 72), p + Vector2(75, -8), Color("91866b"), 2.0)


func _draw_house(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-85, -50), Vector2(170, 105)), Color("566253"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-105, -42), p + Vector2(0, -102), p + Vector2(105, -42)]), Color("7a7660"))
	draw_rect(Rect2(p + Vector2(-17, 10), Vector2(34, 45)), Color("293a31"))
	draw_rect(Rect2(p + Vector2(-62, -24), Vector2(27, 25)), Color("c6ad72"))
	draw_rect(Rect2(p + Vector2(35, -24), Vector2(27, 25)), Color("c6ad72"))


func _draw_fire(p: Vector2) -> void:
	draw_circle(p, 54.0, Color(0.91, 0.59, 0.26, 0.045))
	draw_circle(p, 36.0, Color(0.91, 0.59, 0.26, 0.08))
	for i in range(8):
		draw_circle(p + Vector2.from_angle(float(i) * TAU / 8.0) * 24.0, 6.0, Color("899080"))
	draw_line(p + Vector2(-15, 8), p + Vector2(14, -5), Color("80624a"), 7.0)
	draw_line(p + Vector2(-12, -4), p + Vector2(15, 9), Color("80624a"), 7.0)
	var flicker: float = sin(_clock * 8.0) * 3.0
	draw_colored_polygon(PackedVector2Array([p + Vector2(-13, 4), p + Vector2(-9, -20), p + Vector2(0, -35 - flicker), p + Vector2(5, -12), p + Vector2(13, -21), p + Vector2(15, 4)]), Color("e8a75f"))
	draw_colored_polygon(PackedVector2Array([p + Vector2(-6, 5), p + Vector2(0, -19), p + Vector2(8, 5)]), Color("f2d28d"))


func _draw_lantern(p: Vector2, color: Color) -> void:
	draw_circle(p + Vector2(0, -20), 43.0, Color(color, 0.04))
	draw_circle(p + Vector2(0, -20), 23.0, Color(color, 0.08))
	draw_line(p + Vector2(0, 14), p + Vector2(0, -37), Color("677064"), 4.0)
	draw_rect(Rect2(p + Vector2(-7, -35), Vector2(14, 19)), color)
	draw_line(p + Vector2(-10, -37), p + Vector2(10, -37), color.darkened(0.4), 4.0)


func _draw_rock(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(rect.position + Vector2(6, 9), rect.size), Color(0, 0, 0, 0.18))
	var p: Vector2 = rect.position
	var s: Vector2 = rect.size
	var polygon := PackedVector2Array([p + Vector2(0, s.y * 0.3), p + Vector2(s.x * 0.2, 0), p + Vector2(s.x * 0.76, 0), p + Vector2(s.x, s.y * 0.27), p + s, p + Vector2(s.x * 0.18, s.y)])
	draw_colored_polygon(polygon, color)
	draw_line(p + Vector2(s.x * 0.2, 3), p + Vector2(s.x * 0.76, 3), color.lightened(0.2), 3.0)
	draw_line(p + Vector2(s.x * 0.34, 0), p + Vector2(s.x * 0.44, s.y * 0.67), color.darkened(0.2), 2.0)


func _draw_arch(p: Vector2, color: Color) -> void:
	draw_rect(Rect2(p + Vector2(-60, -65), Vector2(22, 89)), color.darkened(0.2))
	draw_rect(Rect2(p + Vector2(38, -65), Vector2(22, 89)), color.darkened(0.2))
	draw_rect(Rect2(p + Vector2(-65, -80), Vector2(130, 26)), color)
	draw_line(p + Vector2(-61, -77), p + Vector2(60, -77), color.lightened(0.24), 3.0)


func _draw_crystal(p: Vector2, color: Color, size: float) -> void:
	draw_circle(p, 55.0 * size, Color(color, 0.05))
	for i in range(3):
		var offset := Vector2(float(i - 1) * 20.0, float(absi(i - 1)) * 10.0) * size
		var height: float = (55.0 - float(absi(i - 1)) * 17.0) * size
		var points := PackedVector2Array([p + offset + Vector2(-11, 7) * size, p + offset + Vector2(-13, -height * 0.58), p + offset + Vector2(0, -height), p + offset + Vector2(12, -height * 0.65), p + offset + Vector2(9, 7) * size])
		draw_colored_polygon(points, color.darkened(float(absi(i - 1)) * 0.2))
		draw_line(p + offset + Vector2(0, -height + 5), p + offset + Vector2(1, 2), color.lightened(0.22), 2.0)


func _draw_pillar(rect: Rect2) -> void:
	draw_rect(Rect2(rect.position + Vector2(8, 10), rect.size), Color(0, 0, 0, 0.2))
	draw_rect(rect, Color("535268"))
	draw_rect(Rect2(rect.position + Vector2(10, 10), rect.size - Vector2(20, 20)), Color("636077"))
	draw_line(rect.position + Vector2(5, 3), rect.position + Vector2(rect.size.x - 5, 3), Color("8d819d"), 4.0)
	var center: Vector2 = rect.get_center()
	draw_line(center + Vector2(-8, -24), center + Vector2(7, -3), Color("9e8fb7"), 2.0)
	draw_line(center + Vector2(7, -3), center + Vector2(-7, 20), Color("9e8fb7"), 2.0)


func _draw_label(p: Vector2, text: String, color: Color, font_size: int) -> void:
	var width: float = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(_font, p - Vector2(width * 0.5, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
