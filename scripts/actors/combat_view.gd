class_name CombatView
extends Node2D
## Cosmetic-only layer. Projectiles are snapshots; events never apply damage here.

const MAX_EFFECTS := 128
const MAX_PROJECTILES := 256

var _projectiles: Dictionary = {}
var _effects: Array[Dictionary] = []
var _font: SystemFont
var _sequence := 0


func _ready() -> void:
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])


func set_projectiles(entries: Array) -> void:
	var next: Dictionary = {}
	for entry in entries.slice(0, MAX_PROJECTILES):
		if not entry is Dictionary:
			continue
		var data: Dictionary = entry
		var id := str(data.get("id", ""))
		var point: Variant = data.get("position", Vector2.ZERO)
		var heading: Variant = data.get("direction", Vector2.RIGHT)
		if id.is_empty() or not point is Vector2 or not heading is Vector2:
			continue
		var position_value: Vector2 = point
		var direction: Vector2 = heading
		if not position_value.is_finite() or not direction.is_finite():
			continue
		var projectile: Dictionary = _projectiles.get(id, {"position": position_value})
		projectile["target"] = position_value
		projectile["direction"] = _normalized(direction)
		projectile["owner"] = int(data.get("owner", 0))
		next[id] = projectile
	_projectiles = next
	queue_redraw()


func play_event(event: Dictionary) -> void:
	var type := str(event.get("type", ""))
	if type not in ["hit", "chain", "shot", "slam", "charge"]:
		return
	_sequence += 1
	var effect: Dictionary = event.duplicate(true)
	effect["age"] = 0.0
	effect["seed"] = _sequence
	match type:
		"hit": effect["duration"] = 0.7
		"chain":
			effect["duration"] = 0.3
			effect["segments"] = _make_lightning(event.get("points", []), _sequence)
		"shot": effect["duration"] = 0.14
		"slam": effect["duration"] = 0.5
		"charge": effect["duration"] = 0.25
	if type != "chain":
		var point: Variant = event.get("position", Vector2.ZERO)
		if not point is Vector2 or not point.is_finite():
			return
		effect["position"] = point
	if _effects.size() >= MAX_EFFECTS:
		_effects.pop_front()
	_effects.append(effect)
	queue_redraw()


func clear_effects() -> void:
	_projectiles.clear()
	_effects.clear()
	queue_redraw()


func _process(delta: float) -> void:
	for projectile: Dictionary in _projectiles.values():
		var current: Vector2 = projectile.position
		var target: Vector2 = projectile.target
		projectile.position = current.lerp(target, 1.0 - exp(-30.0 * delta)) if current.distance_to(target) < 300.0 else target
	for index in range(_effects.size() - 1, -1, -1):
		_effects[index]["age"] = float(_effects[index].age) + delta
		if float(_effects[index].age) >= float(_effects[index].duration):
			_effects.remove_at(index)
	# Also clear the final frame after the last short-lived effect expires.
	queue_redraw()


func _draw() -> void:
	for projectile: Dictionary in _projectiles.values():
		_draw_projectile(projectile)
	for effect: Dictionary in _effects:
		var progress := clampf(float(effect.age) / float(effect.duration), 0.0, 1.0)
		match str(effect.type):
			"hit": _draw_hit(effect, progress)
			"chain": _draw_chain(effect, progress)
			"shot": _draw_shot(effect, progress)
			"slam": _draw_slam(effect, progress)
			"charge": _draw_charge(effect, progress)


func _draw_projectile(projectile: Dictionary) -> void:
	var point: Vector2 = projectile.position
	var direction: Vector2 = projectile.direction
	var side := direction.orthogonal()
	draw_line(point - direction * 25, point - direction * 12, Color(0.86, 0.91, 0.76, 0.3), 3, true)
	draw_line(point - direction * 13, point + direction * 9, Color("f0d7a1"), 2.4, true)
	draw_colored_polygon(PackedVector2Array([point + direction * 13, point + direction * 5 + side * 4, point + direction * 5 - side * 4]), Color("e5eee4"))
	draw_line(point - direction * 12, point - direction * 18 + side * 4, Color("80c6ba"), 2, true)
	draw_line(point - direction * 12, point - direction * 18 - side * 4, Color("80c6ba"), 2, true)


func _draw_hit(effect: Dictionary, progress: float) -> void:
	var point: Vector2 = effect.position
	var color := Color("f0dfb6")
	var element := str(effect.get("element", "physical"))
	if element == "burn":
		color = Color("ffb36b")
	elif element == "chain":
		color = Color("a4eaff")
	if str(effect.get("target", "enemy")) == "player":
		color = Color("ff8f83")
	var alpha := 1.0 - progress
	if progress < 0.35:
		var spark_alpha := 1.0 - progress / 0.35
		for index in range(5):
			var direction := Vector2.from_angle(TAU * index / 5.0 + int(effect.seed) * 0.67)
			draw_line(point + direction * (5 + progress * 20), point + direction * (11 + progress * 38), Color(color, spark_alpha), 2, true)
	var damage := maxf(0.0, float(effect.get("damage", 0.0)))
	if _font != null and damage > 0.0:
		var text := str(int(round(damage)))
		var font_size := 14 if element == "burn" else 18
		var text_width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var drift := float(int(effect.seed) % 3 - 1) * 11
		var at := point + Vector2(drift - text_width / 2, -23 - progress * 30)
		draw_string(_font, at + Vector2(1, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.04, 0.08, 0.1, alpha * 0.9))
		draw_string(_font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(color, alpha))


func _draw_chain(effect: Dictionary, progress: float) -> void:
	var alpha := (1.0 - progress) * (0.85 + 0.15 * sin(progress * 35))
	for segment: PackedVector2Array in effect.get("segments", []):
		if segment.size() < 2:
			continue
		draw_polyline(segment, Color(0.31, 0.7, 1.0, alpha * 0.2), 10, true)
		draw_polyline(segment, Color(0.54, 0.89, 1.0, alpha), 3, true)
		draw_polyline(segment, Color(0.94, 1.0, 1.0, alpha), 1, true)
		draw_circle(segment[-1], 8 * (1.0 - progress), Color(0.7, 0.95, 1.0, alpha * 0.4))


func _draw_shot(effect: Dictionary, progress: float) -> void:
	var point: Vector2 = effect.position
	var direction := _event_direction(effect)
	var alpha := 1.0 - progress
	draw_line(point, point + direction * (18 + progress * 22), Color(1.0, 0.9, 0.61, alpha), 3 * alpha + 1, true)
	for side in [-1, 1]:
		var end := point + direction.rotated(0.5 * side) * (10 + progress * 12)
		draw_line(point, end, Color(1.0, 0.9, 0.61, alpha), 1.5, true)


func _draw_slam(effect: Dictionary, progress: float) -> void:
	var point: Vector2 = effect.position
	var radius := maxf(1.0, float(effect.get("radius", 115.0)))
	var alpha := 1.0 - progress
	var ring := radius * (0.35 + progress * 0.65)
	draw_circle(point, ring, Color(1.0, 0.55, 0.3, alpha * 0.08))
	draw_arc(point, ring, 0, TAU, 64, Color(1.0, 0.72, 0.46, alpha), 4 * alpha + 1, true)
	draw_arc(point, ring * 0.78, 0, TAU, 56, Color(1.0, 0.88, 0.66, alpha * 0.4), 1.5, true)
	for index in range(10):
		var direction := Vector2.from_angle(TAU * index / 10.0 + 0.3)
		draw_line(point + direction * ring * 0.55, point + direction * ring * 0.88, Color(0.95, 0.57, 0.33, alpha * 0.7), 2, true)


func _draw_charge(effect: Dictionary, progress: float) -> void:
	var point: Vector2 = effect.position
	var direction := _event_direction(effect)
	var side := direction.orthogonal()
	var alpha := 1.0 - progress
	for index in range(5):
		var offset := side * (index - 2) * 13.0
		draw_line(point + offset - direction * progress * 40, point + offset - direction * (35 + progress * 110), Color(1.0, 0.68, 0.39, alpha * 0.6), 2, true)


func _make_lightning(raw_points: Variant, seed: int) -> Array[PackedVector2Array]:
	var segments: Array[PackedVector2Array] = []
	if not raw_points is Array:
		return segments
	var points: Array[Vector2] = []
	for raw in raw_points.slice(0, 12):
		if raw is Vector2 and raw.is_finite():
			points.append(raw)
	for index in range(points.size() - 1):
		var start := points[index]
		var end := points[index + 1]
		var side := _normalized(end - start).orthogonal()
		var count := clampi(int(start.distance_to(end) / 24.0), 3, 12)
		var segment := PackedVector2Array([start])
		for step in range(1, count):
			var t := float(step) / count
			var displacement := sin(float(step * 9 + seed * 3 + index * 5)) * 9.0
			segment.append(start.lerp(end, t) + side * displacement)
		segment.append(end)
		segments.append(segment)
	return segments


func _event_direction(effect: Dictionary) -> Vector2:
	var direction: Variant = effect.get("direction", Vector2.RIGHT)
	return _normalized(direction) if direction is Vector2 else Vector2.RIGHT


func _normalized(direction: Vector2) -> Vector2:
	return direction.normalized() if direction.is_finite() and direction.length_squared() > 0.0001 else Vector2.RIGHT
