extends Node2D

var tint: Color = Color("e6be78")
var _clock: float = 0.0

func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 19, Color(tint, 0.08))
	draw_arc(Vector2.ZERO, 13, 0, TAU, 24, Color(tint, 0.4), 1, true)
	var offset := Vector2(0, sin(_clock * 3) * 3 - 4)
	draw_colored_polygon(PackedVector2Array([offset + Vector2(0, -9), offset + Vector2(7, 0), offset + Vector2(0, 9), offset + Vector2(-7, 0)]), tint)
	draw_line(offset + Vector2(0, -6), offset + Vector2(0, 4), tint.lightened(0.5), 2, true)
