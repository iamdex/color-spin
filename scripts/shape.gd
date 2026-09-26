extends Node2D
## The central figure. Each side has its own color; one tap rotates it by one
## side, clockwise or counter-clockwise.
## sides == 1 means a single-color circle.

const RADIUS := 120.0
const TURN_TIME := 0.12

var sides := 1
var colors: Array[Color] = []
var turns := 0          # logical rotation, in "one side" steps
var base_angle := 0.0   # angle of vertex 0, chosen so no vertex points at a screen axis
var _tween: Tween


func setup(n: int, palette: Array[Color]) -> void:
	sides = n
	colors = palette.slice(0, n)
	turns = 0
	if _tween:
		_tween.kill()
	rotation = 0.0
	base_angle = _best_base_angle(n)
	queue_redraw()


## dir: 1 = clockwise (on screen), -1 = counter-clockwise.
func rotate_step(dir := 1) -> void:
	turns += dir
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "rotation", turns * _step(), TURN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func pulse() -> void:
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE * 1.1, 0.06)
	t.tween_property(self, "scale", Vector2.ONE, 0.1)


## Index of the side facing the given world angle (from the figure's center).
## Uses the logical rotation, so a turn counts immediately even while animating.
func side_at(world_angle: float) -> int:
	if sides == 1:
		return 0
	var local := world_angle - turns * _step() - base_angle
	return int(floor(fposmod(local, TAU) / _step())) % sides


## Distance from center to the figure's edge along the given world angle.
func edge_distance(world_angle: float) -> float:
	if sides == 1:
		return RADIUS
	var i := side_at(world_angle)
	var normal := base_angle + (i + 0.5) * _step() + turns * _step()
	var apothem := RADIUS * cos(PI / sides)
	return apothem / cos(angle_difference(normal, world_angle))


func _draw() -> void:
	if sides == 1:
		draw_circle(Vector2.ZERO, RADIUS, colors[0])
		draw_arc(Vector2.ZERO, RADIUS, 0, TAU, 64, colors[0].darkened(0.35), 6.0, true)
		return
	var verts: Array[Vector2] = []
	for k in sides:
		verts.append(Vector2.from_angle(base_angle + k * _step()) * RADIUS)
	# Soft colored halo: slightly larger translucent wedges behind the figure.
	for layer: Array in [[1.2, 0.07], [1.1, 0.14]]:
		for i in sides:
			var a: Vector2 = verts[i] * layer[0]
			var b: Vector2 = verts[(i + 1) % sides] * layer[0]
			draw_colored_polygon(PackedVector2Array([Vector2.ZERO, a, b]), Color(colors[i], layer[1]))
	# One colored wedge per side, so each edge is clearly identifiable.
	# Darker towards the center gives the figure a faceted, gem-like look.
	for i in sides:
		var a := verts[i]
		var b := verts[(i + 1) % sides]
		var c := colors[i]
		draw_polygon(PackedVector2Array([Vector2.ZERO, a, b]),
				PackedColorArray([c.darkened(0.5), c, c]))
		draw_line(a, b, c.lightened(0.35), 6.0, true)
	for v in verts:
		draw_line(Vector2.ZERO, v, Color(0.05, 0.05, 0.09, 0.55), 3.0, true)
	draw_circle(Vector2.ZERO, 18.0, Color(0.07, 0.07, 0.1))
	draw_arc(Vector2.ZERO, 18.0, 0, TAU, 32, Color(1, 1, 1, 0.3), 2.0, true)


func _step() -> float:
	return TAU / sides


## Balls arrive along the 4 screen axes. Pick a vertex offset that keeps every
## vertex (in every rotation step) as far as possible from those axes, so a ball
## always hits the middle-ish of a side and never a corner.
func _best_base_angle(n: int) -> float:
	if n < 3:
		return 0.0
	var step := TAU / n
	var best := 0.0
	var best_score := -1.0
	for d in 360:
		var a := deg_to_rad(d) * step / TAU
		var score := INF
		for k in n:
			var v := fposmod(a + k * step, PI / 2)
			score = minf(score, minf(v, PI / 2 - v))
		if score > best_score + 0.0001:
			best_score = score
			best = a
	return best
