extends Node2D
## Short-lived visual effects in world space: particle bursts, expanding rings
## and floating text.


class Particle:
	var pos: Vector2
	var vel: Vector2
	var color: Color
	var size: float
	var life: float
	var max_life: float


class Ring:
	var pos: Vector2
	var color: Color
	var from: float
	var to: float
	var life: float
	var max_life: float


class FloatText:
	var pos: Vector2
	var text: String
	var color: Color
	var life: float
	var max_life: float


const TEXT_SIZE := 34

var font: Font
var _particles: Array[Particle] = []
var _rings: Array[Ring] = []
var _texts: Array[FloatText] = []


func burst(pos: Vector2, color: Color, count := 14, speed := 280.0) -> void:
	for i in count:
		var p := Particle.new()
		p.pos = pos
		p.vel = Vector2.from_angle(randf() * TAU) * speed * randf_range(0.3, 1.0)
		p.color = color
		p.size = randf_range(3.0, 7.0)
		p.max_life = randf_range(0.35, 0.7)
		p.life = p.max_life
		_particles.append(p)


func ring(pos: Vector2, color: Color, from: float, to: float, duration := 0.35) -> void:
	var r := Ring.new()
	r.pos = pos
	r.color = color
	r.from = from
	r.to = to
	r.max_life = duration
	r.life = duration
	_rings.append(r)


func text(pos: Vector2, s: String, color: Color) -> void:
	var t := FloatText.new()
	t.pos = pos
	t.text = s
	t.color = color
	t.max_life = 0.7
	t.life = t.max_life
	_texts.append(t)


func clear() -> void:
	_particles.clear()
	_rings.clear()
	_texts.clear()


func _process(delta: float) -> void:
	for i in range(_particles.size() - 1, -1, -1):
		var p := _particles[i]
		p.life -= delta
		if p.life <= 0.0:
			_particles.remove_at(i)
			continue
		p.pos += p.vel * delta
		p.vel *= maxf(1.0 - 3.0 * delta, 0.0)
	for i in range(_rings.size() - 1, -1, -1):
		_rings[i].life -= delta
		if _rings[i].life <= 0.0:
			_rings.remove_at(i)
	for i in range(_texts.size() - 1, -1, -1):
		var t := _texts[i]
		t.life -= delta
		if t.life <= 0.0:
			_texts.remove_at(i)
			continue
		t.pos.y -= 70.0 * delta
	queue_redraw()


func _draw() -> void:
	for r in _rings:
		var t := 1.0 - r.life / r.max_life
		var radius := lerpf(r.from, r.to, 1.0 - pow(1.0 - t, 3.0))
		draw_arc(r.pos, radius, 0, TAU, 64, Color(r.color, 1.0 - t), 1.0 + 5.0 * (1.0 - t), true)
	for p in _particles:
		var t := p.life / p.max_life
		draw_circle(p.pos, p.size * t, Color(p.color, t))
	if font:
		for ft in _texts:
			var a := clampf(ft.life / ft.max_life * 2.0, 0.0, 1.0)
			draw_string(font, ft.pos + Vector2(-60, 0), ft.text, HORIZONTAL_ALIGNMENT_CENTER,
					120, TEXT_SIZE, Color(ft.color, a))
