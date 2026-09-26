extends Node2D
## A colored ball flying straight towards the center figure.

const RADIUS := 16.0
const TRAIL_LEN := 12

var color_index := 0
var color := Color.WHITE
var velocity := Vector2.ZERO
var _trail: Array[Vector2] = []


func _process(delta: float) -> void:
	_trail.push_front(position)
	if _trail.size() > TRAIL_LEN:
		_trail.pop_back()
	position += velocity * delta
	queue_redraw()


func _draw() -> void:
	for i in _trail.size():
		var t := 1.0 - float(i + 1) / (TRAIL_LEN + 1)
		draw_circle(_trail[i] - position, RADIUS * (0.3 + 0.6 * t), Color(color, 0.22 * t))
	# Soft glow, body, and a small highlight.
	draw_circle(Vector2.ZERO, RADIUS * 2.0, Color(color, 0.07))
	draw_circle(Vector2.ZERO, RADIUS * 1.45, Color(color, 0.15))
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_circle(Vector2(-5, -5), RADIUS * 0.35, Color(1, 1, 1, 0.45))
