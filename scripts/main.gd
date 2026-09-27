extends Node2D
## Game loop: main menu, spawns balls from the 4 screen edges, checks hits
## against the figure, tracks score / lives / level, handles input, pause,
## game over, sound, the about screen and the local leaderboard.

const ShapeScript := preload("res://scripts/shape.gd")
const BallScript := preload("res://scripts/ball.gd")
const FxScript := preload("res://scripts/fx.gd")
const SfxScript := preload("res://scripts/sfx.gd")
const MusicScript := preload("res://scripts/music.gd")

const PALETTE: Array[Color] = [
	Color("#ff4d6d"), # red
	Color("#4dabf7"), # blue
	Color("#ffd43b"), # yellow
	Color("#51cf66"), # green
	Color("#b197fc"), # purple
	Color("#ff922b"), # orange
	Color("#3bc9db"), # cyan
	Color("#f783ac"), # pink
]
const BG_TOP := Color("#1c1638")
const BG_BOTTOM := Color("#08080f")
const INK := Color("#12121c")
const MAX_LIVES := 5
const POINTS_PER_LEVEL := 10
const LEVELS_PER_SIDE := 3
const MIN_SIDES := 3
const MAX_SIDES := 8
const MENU_SIDES := 6
const ABOUT := [
	["COME SI GIOCA", [
		"Ruota la figura: ogni pallina deve",
		"toccare il lato del suo colore.",
		"Ogni 10 punti sali di livello.",
		"Ogni 3 livelli arriva un lato in più",
		"e recuperi una vita.",
		"Dopo 5 errori la partita finisce.",
	]],
	["COMANDI", [
		"Tocca a sinistra o a destra per ruotare",
		"Tastiera: frecce oppure A e D",
		"P o Esc pausa  ·  M musica  ·  S suoni",
	]],
	["CREDITI", [
		"Un gioco di Davide Dex Espertini",
		"Fatto con Godot 4: grafica e suoni",
		"sono generati dal codice",
		"github.com/iamdex/color-spin",
	]],
]
const SPAWN_DIRS: Array[Vector2] = [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const SAVE_PATH := "user://save.cfg"
const DOT_COUNT := 40
const TOP_SIZE := 10
const RESUME_BEATS := 3   # "3, 2, 1" countdown before play resumes
const RESUME_BEAT := 0.5
const NAME_MAX := 14
const NAME_ROW := 84.0    # extra room the name field takes on the game over screen

enum State { MENU, PLAYING, PAUSED, GAME_OVER, LEADERBOARD, ABOUT }

var state := State.MENU
var score := 0
var best := 0
var new_best := false
var lives := MAX_LIVES
var level := 1
var spawn_timer := 0.0
var menu_turn_timer := 0.0
var shake := 0.0
var flash := 0.0
var fade := 0.0
var score_pop := 0.0
var banner := ""
var banner_time := 0.0
var game_over_time := 0.0
var pause_time := 0.0
var resume_timer := 0.0       # > 0 while the resume countdown runs
var time := 0.0
var dots: Array[Vector3] = [] # x, y, radius of the drifting background dots
var streak := 0               # consecutive hits, drives the hit sound's pitch
var arrow_flash := [0.0, 0.0] # left, right: lights up the turn arrows on tap
var top: Array[Dictionary] = [] # local leaderboard: {score, level, date, name}
var last_rank := 0            # position of the last game in `top`, 0 = not ranked
var player_name := ""         # last name typed, offered again for the next record

var world: Node2D
var shape: Node2D
var balls: Node2D
var fx: Node2D
var sfx: Node
var music: Node
var hud: Control
var name_edit: LineEdit
var font: Font


func _ready() -> void:
	randomize()
	font = _make_font()
	# Pausing freezes the tree: balls, effects and the figure's tweens live
	# under `world` and stop, while this node keeps running menus and input.
	process_mode = Node.PROCESS_MODE_ALWAYS
	world = Node2D.new()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	balls = Node2D.new()
	world.add_child(balls)
	shape = ShapeScript.new()
	world.add_child(shape)
	fx = FxScript.new()
	fx.font = font
	world.add_child(fx)
	sfx = SfxScript.new()
	add_child(sfx)
	music = MusicScript.new()
	add_child(music)

	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.draw.connect(_draw_hud)
	layer.add_child(hud)
	name_edit = _make_name_edit()
	hud.add_child(name_edit)

	var size := get_viewport_rect().size
	for i in DOT_COUNT:
		dots.append(Vector3(randf() * size.x, randf() * size.y, randf_range(1.0, 3.0)))

	_load()
	_go_to_menu()


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Montserrat", "Poppins", "Nunito", "Helvetica Neue", "Arial", "sans-serif"])
	f.font_weight = 800
	return f


func _make_name_edit() -> LineEdit:
	var e := LineEdit.new()
	e.max_length = NAME_MAX
	e.alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.placeholder_text = "Scrivi il tuo nome"
	e.select_all_on_focus = true
	e.visible = false
	e.add_theme_font_override("font", font)
	e.add_theme_font_size_override("font_size", 30)
	e.add_theme_color_override("font_color", Color.WHITE)
	e.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.4))
	e.add_theme_color_override("caret_color", PALETTE[2])
	e.add_theme_color_override("selection_color", Color(PALETTE[2], 0.35))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.08)
	sb.border_color = Color(1, 1, 1, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	sb.anti_aliasing = true
	sb.content_margin_left = 20
	sb.content_margin_right = 20
	e.add_theme_stylebox_override("normal", sb)
	# The focus style is drawn over "normal": just a highlighted border.
	var focus := sb.duplicate() as StyleBoxFlat
	focus.draw_center = false
	focus.border_color = PALETTE[2]
	e.add_theme_stylebox_override("focus", focus)
	e.text_changed.connect(_on_name_changed)
	e.text_submitted.connect(func(_t: String) -> void: e.release_focus())
	return e


func _on_name_changed(text: String) -> void:
	player_name = text.strip_edges()
	if last_rank > 0:
		top[last_rank - 1]["name"] = player_name


## Saves the typed name when leaving the game over screen.
func _close_name_edit() -> void:
	if name_edit.visible:
		name_edit.release_focus()
		name_edit.visible = false
		_save()


func _go_to_menu() -> void:
	_close_name_edit()
	_set_paused(false)
	_clear_board()
	state = State.MENU
	shape.setup(MENU_SIDES, PALETTE)
	music.play_menu()
	menu_turn_timer = 1.0
	fade = 1.0


func _start() -> void:
	_close_name_edit()
	_set_paused(false)
	_clear_board()
	score = 0
	streak = 0
	last_rank = 0
	lives = MAX_LIVES
	level = 1
	new_best = false
	spawn_timer = 1.0
	state = State.PLAYING
	fade = 1.0
	shape.setup(_sides_for_level(level), PALETTE)
	music.play_game(level, _tier(level))
	_show_banner("Livello 1")


func _clear_board() -> void:
	for b in balls.get_children():
		b.queue_free()
	fx.clear()


func _unhandled_input(event: InputEvent) -> void:
	var action := ""
	var pos := Vector2(-1, -1)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		action = "tap"
		pos = event.position
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_LEFT, KEY_A:
				action = "left"
			KEY_RIGHT, KEY_D:
				action = "right"
			KEY_SPACE, KEY_ENTER, KEY_UP:
				action = "confirm"
			KEY_ESCAPE:
				action = "back"
			KEY_P:
				action = "pause"
			KEY_I:
				action = "info"
			KEY_M:
				action = "music"
			KEY_S:
				action = "effects"
	if action == "":
		return
	get_viewport().set_input_as_handled()
	if action == "music":
		_toggle_music()
		return
	if action == "effects":
		_toggle_sound()
		return

	match state:
		State.MENU:
			if action == "tap" and _sound_button().has_point(pos):
				_toggle_sound()
			elif action == "tap" and _music_button().has_point(pos):
				_toggle_music()
			elif action == "tap" and _menu_buttons()[1].has_point(pos):
				sfx.play("click")
				state = State.LEADERBOARD
				fade = 0.6
			elif action == "info" or (action == "tap" and _info_button().has_point(pos)):
				sfx.play("click")
				state = State.ABOUT
				fade = 0.6
			elif action != "back":
				_start()
		State.PLAYING:
			if action == "pause" or action == "back" \
					or (action == "tap" and _pause_button().grow(12).has_point(pos)):
				_pause()
				return
			var dir := 0
			match action:
				"left":
					dir = -1
				"right", "confirm":
					dir = 1
				"tap":
					dir = -1 if pos.x < hud.size.x / 2.0 else 1
			if dir != 0:
				shape.rotate_step(dir)
				sfx.play("turn_left" if dir < 0 else "turn_right")
				arrow_flash[0 if dir < 0 else 1] = 1.0
		State.PAUSED:
			if resume_timer > 0.0:
				return
			var buttons := _pause_buttons()
			var audio := _pause_audio_buttons()
			if action == "tap" and audio[0].has_point(pos):
				_toggle_music()
			elif action == "tap" and audio[1].has_point(pos):
				_toggle_sound()
			elif action in ["confirm", "pause", "back"] or buttons[0].has_point(pos):
				sfx.play("click")
				resume_timer = RESUME_BEATS * RESUME_BEAT
			elif buttons[1].has_point(pos):
				# Leaving mid-game: the run is dropped, not recorded.
				sfx.play("click")
				_go_to_menu()
		State.GAME_OVER:
			# A tap outside the name field closes the keyboard (and may press a button).
			name_edit.release_focus()
			if game_over_time < 0.6:
				return
			var buttons := _game_over_buttons()
			if action == "confirm" or buttons[0].has_point(pos):
				sfx.play("click")
				_start()
			elif action == "back" or buttons[1].has_point(pos):
				sfx.play("click")
				_go_to_menu()
		State.LEADERBOARD, State.ABOUT:
			# Any tap or key goes back: the whole screen is the "back" button.
			sfx.play("click")
			state = State.MENU
			fade = 0.6


func _pause() -> void:
	state = State.PAUSED
	pause_time = 0.0
	resume_timer = 0.0
	sfx.play("click")
	_set_paused(true)
	music.set_ducked(true)


func _set_paused(on: bool) -> void:
	get_tree().paused = on


## Leaving the app (home button, tab switch, lost focus) pauses a running game.
func _notification(what: int) -> void:
	if what not in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED]:
		return
	if state == State.PLAYING:
		_pause()
	elif state == State.PAUSED:
		resume_timer = 0.0 # back to the pause menu instead of resuming unattended


func _toggle_music() -> void:
	music.muted = not music.muted
	sfx.play("click")
	_save()


func _toggle_sound() -> void:
	sfx.muted = not sfx.muted
	sfx.play("click")
	_save()


func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	var center := size / 2.0
	time += delta
	fade = maxf(fade - delta * 3.0, 0.0)
	_move_dots(size, delta)
	if state == State.PAUSED:
		_process_paused(delta)
		queue_redraw()
		hud.queue_redraw()
		return
	shake = maxf(shake - delta * 30.0, 0.0)
	flash = maxf(flash - delta * 2.5, 0.0)
	score_pop = maxf(score_pop - delta * 4.0, 0.0)
	banner_time = maxf(banner_time - delta, 0.0)
	for i in 2:
		arrow_flash[i] = maxf(arrow_flash[i] - delta * 4.0, 0.0)
	world.position = center + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake

	match state:
		State.MENU, State.LEADERBOARD, State.ABOUT:
			menu_turn_timer -= delta
			if menu_turn_timer <= 0.0:
				shape.rotate_step()
				menu_turn_timer = 0.9
		State.PLAYING:
			spawn_timer -= delta
			if _balls_in_flight() >= _max_balls():
				# Board is full: wait a beat after the next hit before spawning again.
				spawn_timer = maxf(spawn_timer, 0.4)
			elif spawn_timer <= 0.0:
				_spawn_ball()
				spawn_timer = _spawn_interval()
			_check_hits()
		State.GAME_OVER:
			game_over_time += delta
			if name_edit.visible:
				var r := _name_field()
				name_edit.position = r.position
				name_edit.size = r.size
				name_edit.modulate.a = clampf(game_over_time * 3.0, 0.0, 1.0)
	queue_redraw()
	hud.queue_redraw()


## Everything in play is frozen; only the overlay and the resume countdown move.
func _process_paused(delta: float) -> void:
	pause_time += delta
	if resume_timer <= 0.0:
		return
	var beat := ceili(resume_timer / RESUME_BEAT)
	resume_timer -= delta
	if resume_timer <= 0.0:
		resume_timer = 0.0
		state = State.PLAYING
		_set_paused(false)
		music.set_ducked(false)
	elif ceili(resume_timer / RESUME_BEAT) < beat:
		sfx.play("click")


func _move_dots(size: Vector2, delta: float) -> void:
	for i in dots.size():
		var d := dots[i]
		d.y -= (6.0 + d.z * 8.0) * delta
		if d.y < -10.0:
			d = Vector3(randf() * size.x, size.y + 10.0, d.z)
		dots[i] = d


func _spawn_ball() -> void:
	var size := get_viewport_rect().size
	var dir: Vector2 = SPAWN_DIRS.pick_random()
	var dist := absf(dir.x) * size.x / 2.0 + absf(dir.y) * size.y / 2.0 + BallScript.RADIUS
	var ball := BallScript.new()
	ball.color_index = randi() % shape.sides
	ball.color = PALETTE[ball.color_index]
	ball.position = dir * dist
	# Same travel time from every edge, so a portrait screen stays fair.
	ball.velocity = -dir * (dist - ShapeScript.RADIUS) / _travel_time()
	balls.add_child(ball)


func _check_hits() -> void:
	for ball in balls.get_children():
		if ball.is_queued_for_deletion():
			continue
		var angle: float = ball.position.angle()
		if ball.position.length() - BallScript.RADIUS > shape.edge_distance(angle):
			continue
		if shape.side_at(angle) == ball.color_index:
			_on_score(ball)
		else:
			_on_miss(ball)
		ball.queue_free()
		if state != State.PLAYING:
			return


func _on_score(ball: Node2D) -> void:
	score += 1
	score_pop = 1.0
	sfx.chime(streak)
	streak += 1
	shape.pulse()
	fx.burst(ball.position, ball.color)
	fx.ring(ball.position, ball.color, 10.0, 70.0)
	fx.text(ball.position + ball.position.normalized() * 50.0, "+1", ball.color)
	if score % POINTS_PER_LEVEL == 0:
		_level_up()


func _on_miss(ball: Node2D) -> void:
	lives -= 1
	streak = 0
	shake = 14.0
	flash = 1.0
	fx.burst(ball.position, Color(0.75, 0.75, 0.8), 10, 200.0)
	fx.ring(ball.position, PALETTE[0], 10.0, 90.0)
	if lives <= 0:
		_game_over()
	else:
		sfx.play("miss")


func _level_up() -> void:
	level += 1
	music.set_level(level, _tier(level))
	var n := _sides_for_level(level)
	if n != shape.sides:
		# New figure: clear the board, give the player a moment to look at it
		# and a life back as a reward.
		for b in balls.get_children():
			b.queue_free()
		shape.setup(n, PALETTE)
		sfx.play("figure")
		fx.ring(Vector2.ZERO, Color.WHITE, 60.0, 450.0, 0.6)
		for c in shape.colors:
			fx.burst(Vector2.ZERO, c, 6, 420.0)
		spawn_timer = 1.5
		if lives < MAX_LIVES:
			lives += 1
			_show_banner("Livello %d  +1 vita" % level)
			return
	else:
		sfx.play("level")
	_show_banner("Livello %d" % level)


func _game_over() -> void:
	state = State.GAME_OVER
	game_over_time = 0.0
	sfx.play("game_over")
	music.stop()
	for b in balls.get_children():
		b.queue_free()
	for c in shape.colors:
		fx.burst(Vector2.ZERO, c, 10, 450.0)
	if score > best:
		best = score
		new_best = true
	_record_score()
	_save()
	if last_rank > 0:
		name_edit.text = player_name
		name_edit.modulate.a = 0.0
		name_edit.visible = true


## Inserts this game into the local top list, keeping it sorted and capped.
func _record_score() -> void:
	last_rank = 0
	if score <= 0:
		return
	var i := 0
	while i < top.size() and int(top[i]["score"]) >= score:
		i += 1
	if i >= TOP_SIZE:
		return
	var d := Time.get_date_dict_from_system()
	top.insert(i, {"score": score, "level": level, "date": "%02d/%02d/%d" % [d.day, d.month, d.year],
			"name": player_name})
	if top.size() > TOP_SIZE:
		top.resize(TOP_SIZE)
	last_rank = i + 1


func _show_banner(text: String) -> void:
	banner = text
	banner_time = 1.2


## Levels 1-3: triangle, 4-6: square, 7-9: pentagon, ... up to MAX_SIDES.
func _sides_for_level(lvl: int) -> int:
	return MIN_SIDES + _tier(lvl)


## Index of the current figure (0 = triangle), capped at the last one.
@warning_ignore("integer_division")
func _tier(lvl: int) -> int:
	return mini((lvl - 1) / LEVELS_PER_SIDE, MAX_SIDES - MIN_SIDES)


## Difficulty grows with every figure and with every level inside a figure.
## A new figure resets the in-figure part, so extra sides come with a slower
## pace for a while. Once the last figure is reached only speed keeps growing.
func _difficulty() -> float:
	var tier := _tier(level)
	var tier_level := level - 1 - tier * LEVELS_PER_SIDE
	return 0.7 * tier + 0.5 * tier_level


func _travel_time() -> float:
	return maxf(1.0, 3.2 - 0.25 * _difficulty())


func _spawn_interval() -> float:
	return maxf(0.5, 2.0 - 0.18 * _difficulty())


## Level 1 sends one ball at a time, level 2 two, then one more per figure.
func _max_balls() -> int:
	return mini(level, 3 + _tier(level))


func _balls_in_flight() -> int:
	var n := 0
	for b in balls.get_children():
		if not b.is_queued_for_deletion():
			n += 1
	return n


# --- Background --------------------------------------------------------------

func _draw() -> void:
	var size := get_viewport_rect().size
	var c := world.position
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(size.x, 0), size, Vector2(0, size.y)]),
			PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
	for d in dots:
		draw_circle(Vector2(d.x, d.y), d.z, Color(1, 1, 1, 0.04 + d.z * 0.03))
	# Faint radial glow behind the figure.
	for i in 6:
		draw_circle(c, 150.0 + i * 35.0, Color(1, 1, 1, 0.012))
	# The 4 lanes the balls travel along.
	for dir in SPAWN_DIRS:
		var far := absf(dir.x) * size.x / 2.0 + absf(dir.y) * size.y / 2.0
		draw_dashed_line(c + dir * 195.0, c + dir * far, Color(1, 1, 1, 0.06), 2.0, 10.0)
	# Slowly rotating dashed target ring.
	var segs := 24
	for i in segs:
		var a := time * 0.25 + i * TAU / segs
		draw_arc(c, 178.0, a, a + TAU / segs * 0.5, 6, Color(1, 1, 1, 0.1), 3.0, true)


# --- HUD ---------------------------------------------------------------------

func _draw_hud() -> void:
	var size := hud.size
	match state:
		State.MENU:
			_draw_menu(size)
		State.PLAYING:
			_draw_play(size)
		State.PAUSED:
			_draw_play(size)
			_draw_pause(size)
		State.GAME_OVER:
			_draw_play(size)
			_draw_game_over(size)
		State.LEADERBOARD:
			_draw_leaderboard(size)
		State.ABOUT:
			_draw_about(size)
	if flash > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, size), Color(1, 0.2, 0.2, 0.22 * flash))
	if fade > 0.0:
		hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, fade))


func _draw_menu(size: Vector2) -> void:
	# Title: "COLOR" one letter per palette color, bobbing; "SPIN" in white.
	var title_size := 104
	var word := "COLOR"
	var widths: Array[float] = []
	var total := 0.0
	for ch in word:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, title_size).x
		widths.append(w)
		total += w
	var x := (size.x - total) / 2.0
	var y := size.y * 0.17
	for i in word.length():
		var bob := sin(time * 3.0 + i * 0.7) * 6.0
		_text(Vector2(x, y + bob), word[i], title_size, PALETTE[i])
		x += widths[i]
	_centered("SPIN", y + 100.0, title_size, Color.WHITE)

	var cy := size.y / 2.0
	_centered("Tocca a sinistra o a destra per ruotare", cy + 232.0, 24, Color(1, 1, 1, 0.85))
	_centered("e abbina il colore delle palline", cy + 266.0, 22, Color(1, 1, 1, 0.5))

	var buttons := _menu_buttons()
	var pulse := 1.0 + sin(time * 4.0) * 0.03
	var play := buttons[0]
	play = play.grow_individual(play.size.x * (pulse - 1.0) / 2.0, play.size.y * (pulse - 1.0) / 2.0,
			play.size.x * (pulse - 1.0) / 2.0, play.size.y * (pulse - 1.0) / 2.0)
	_button(play, "GIOCA", PALETTE[2], INK)
	_button(buttons[1], "CLASSIFICA", Color(1, 1, 1, 0.1), Color.WHITE)
	if best > 0:
		_centered("RECORD  %d" % best, buttons[1].end.y + 52.0, 24, Color(1, 1, 1, 0.55))
	_draw_sound_icon(_sound_button())
	_draw_music_icon(_music_button())
	_draw_info_icon(_info_button())


func _draw_play(size: Vector2) -> void:
	# Progress towards the next level.
	hud.draw_rect(Rect2(0, 0, size.x, 6), Color(1, 1, 1, 0.08))
	var progress := float(score % POINTS_PER_LEVEL) / POINTS_PER_LEVEL
	hud.draw_rect(Rect2(0, 0, size.x * progress, 6), PALETTE[2])

	_text(Vector2(28, 84), str(score), int(56 + 18 * score_pop), Color.WHITE)
	_text(Vector2(30, 118), "LIVELLO %d" % level, 20, Color(1, 1, 1, 0.55))
	for i in MAX_LIVES:
		var p := Vector2(size.x - 36 - i * 34, 56)
		if i < lives:
			hud.draw_circle(p, 17, Color(PALETTE[0], 0.2))
			hud.draw_circle(p, 11, PALETTE[0])
			hud.draw_circle(p + Vector2(-3, -3), 3.5, Color(1, 1, 1, 0.5))
		else:
			hud.draw_arc(p, 10, 0, TAU, 24, Color(1, 1, 1, 0.2), 2.0, true)

	# Turn arrows in the bottom corners: each half of the screen turns one way.
	if state == State.PLAYING:
		_draw_pause_icon(_pause_button())
		_draw_turn_arrow(Vector2(96, size.y - 110), -1, 0.12 + 0.6 * arrow_flash[0])
		_draw_turn_arrow(Vector2(size.x - 96, size.y - 110), 1, 0.12 + 0.6 * arrow_flash[1])

	if banner_time > 0.0 and state == State.PLAYING:
		var a := clampf(banner_time / 0.4, 0.0, 1.0)
		var grow := clampf((1.2 - banner_time) / 0.15, 0.0, 1.0)
		_centered(banner, size.y * 0.22, int(lerpf(36, 52, grow)), Color(1, 1, 1, a))


func _draw_game_over(size: Vector2) -> void:
	var t := clampf(game_over_time * 3.0, 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, 0.8 * t))
	var slide := (1.0 - t) * 40.0
	_centered("GAME OVER", size.y * 0.27 + slide, 68, Color(PALETTE[0], t))
	_centered(str(score), size.y * 0.41 + slide, 130, Color(1, 1, 1, t))
	_centered("PUNTI  ·  LIVELLO %d" % level, size.y * 0.41 + 44 + slide, 22, Color(1, 1, 1, 0.55 * t))
	if new_best:
		var s := int(34 + sin(time * 6.0) * 3.0)
		_centered("NUOVO RECORD!", size.y * 0.52 + slide, s, Color(PALETTE[2], t))
	else:
		_centered("RECORD  %d" % best, size.y * 0.52 + slide, 26, Color(1, 1, 1, 0.6 * t))
	if last_rank > 0:
		_centered("%d° IN CLASSIFICA" % last_rank, size.y * 0.52 + 44 + slide, 22, Color(1, 1, 1, 0.7 * t))

	if game_over_time > 0.6:
		var buttons := _game_over_buttons()
		_button(buttons[0], "RIGIOCA", PALETTE[2], INK)
		_button(buttons[1], "MENU", Color(1, 1, 1, 0.1), Color.WHITE)


func _draw_pause(size: Vector2) -> void:
	if resume_timer > 0.0:
		# Countdown over the frozen board, so the player can see what's coming.
		var n := ceili(resume_timer / RESUME_BEAT)
		var k := fmod(resume_timer, RESUME_BEAT) / RESUME_BEAT # 1 -> 0 within a beat
		hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, 0.35))
		_centered(str(n), size.y * 0.22 + 20, int(lerpf(90, 130, k)), Color(1, 1, 1, clampf(k * 2.0, 0.0, 1.0)))
		return
	var t := clampf(pause_time * 5.0, 0.0, 1.0)
	hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, 0.8 * t))
	var slide := (1.0 - t) * 30.0
	_centered("PAUSA", size.y * 0.3 + slide, 68, Color(1, 1, 1, t))
	_centered("%d PUNTI  ·  LIVELLO %d" % [score, level], size.y * 0.3 + 48 + slide, 22,
			Color(1, 1, 1, 0.55 * t))
	var buttons := _pause_buttons()
	_button(buttons[0], "RIPRENDI", PALETTE[2], INK)
	_button(buttons[1], "MENU", Color(1, 1, 1, 0.1), Color.WHITE)
	var audio := _pause_audio_buttons()
	_draw_music_icon(audio[0])
	_draw_sound_icon(audio[1])


func _draw_leaderboard(size: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, 0.85))
	_centered("CLASSIFICA", size.y * 0.1, 60, Color.WHITE)
	_centered("I 10 migliori punteggi su questo dispositivo", size.y * 0.1 + 40, 20, Color(1, 1, 1, 0.5))
	if top.is_empty():
		_centered("Ancora nessun punteggio: gioca una partita!", size.y * 0.4, 24, Color(1, 1, 1, 0.6))
	var rows: Array = []
	for e in top:
		# Games saved before names existed, or left unnamed, show their date.
		var label := str(e.get("name", ""))
		rows.append([label if label != "" else str(e["date"]), int(e["level"]), int(e["score"])])
	_draw_rows(size, rows, last_rank - 1)
	_centered("Tocca per tornare al menu", size.y * 0.9, 22, Color(1, 1, 1, 0.5))


func _draw_about(size: Vector2) -> void:
	hud.draw_rect(Rect2(Vector2.ZERO, size), Color(BG_BOTTOM, 0.85))
	_centered("COLOR SPIN", size.y * 0.1, 60, Color.WHITE)
	_centered("Versione %s" % ProjectSettings.get_setting("application/config/version", "1.0"),
			size.y * 0.1 + 40, 20, Color(1, 1, 1, 0.5))
	var y := size.y * 0.2
	for section in ABOUT:
		_centered(section[0], y, 26, PALETTE[2])
		y += 44.0
		for line in section[1]:
			_centered(line, y, 22, Color(1, 1, 1, 0.8))
			y += 34.0
		y += 30.0
	_centered("Tocca per tornare al menu", size.y * 0.9, 22, Color(1, 1, 1, 0.5))


## rows: [label, level, score]; `highlight` is the row index to mark (-1 = none).
func _draw_rows(size: Vector2, rows: Array, highlight: int) -> void:
	var y0 := size.y * 0.17
	var w := size.x - 80.0
	for i in rows.size():
		var y := y0 + i * 66.0
		var bg := Color(PALETTE[2], 0.16) if i == highlight else Color(1, 1, 1, 0.05)
		var sb := StyleBoxFlat.new()
		sb.bg_color = bg
		sb.set_corner_radius_all(14)
		sb.anti_aliasing = true
		hud.draw_style_box(sb, Rect2(40, y, w, 56))
		var c := Vector2(76, y + 28)
		hud.draw_circle(c, 18, PALETTE[i % PALETTE.size()])
		hud.draw_string(font, Vector2(c.x - 20, y + 36), str(i + 1), HORIZONTAL_ALIGNMENT_CENTER, 40, 22, INK)
		_text(Vector2(112, y + 37), rows[i][0], 24, Color.WHITE)
		_text(Vector2(40, y + 36), "liv. %d" % rows[i][1], 18, Color(1, 1, 1, 0.45),
				HORIZONTAL_ALIGNMENT_RIGHT, w - 120)
		_text(Vector2(40, y + 39), str(rows[i][2]), 30, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, w - 22)


## Curved arrow; dir 1 = clockwise, -1 = counter-clockwise (mirrored).
func _draw_turn_arrow(center: Vector2, dir: int, alpha: float) -> void:
	var r := 34.0
	var a0 := -PI * 0.85
	var a1 := PI * 0.35
	var pts := PackedVector2Array()
	for i in 25:
		var a := lerpf(a0, a1, i / 24.0)
		pts.append(Vector2(cos(a) * r * dir, sin(a) * r))
	var col := Color(1, 1, 1, alpha)
	for i in pts.size():
		pts[i] += center
	hud.draw_polyline(pts, col, 6.0, true)
	# Arrowhead at the end, pointing along the direction of travel.
	var tip := center + Vector2(cos(a1) * r * dir, sin(a1) * r)
	var tangent := Vector2(-sin(a1) * dir, cos(a1)).normalized()
	var side := Vector2(-tangent.y, tangent.x)
	hud.draw_colored_polygon(PackedVector2Array([
		tip + tangent * 14.0, tip - tangent * 4.0 + side * 12.0, tip - tangent * 4.0 - side * 12.0,
	]), col)


func _draw_pause_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	hud.draw_circle(c, 30, Color(1, 1, 1, 0.08))
	for x in [-7.0, 7.0]:
		hud.draw_line(c + Vector2(x, -11), c + Vector2(x, 11), Color(1, 1, 1, 0.75), 7.0, true)


func _draw_info_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	var col := Color(1, 1, 1, 0.75)
	hud.draw_arc(c, 17, 0, TAU, 32, col, 3.0, true)
	hud.draw_circle(c + Vector2(0, -8), 2.8, col)
	hud.draw_line(c + Vector2(0, -2), c + Vector2(0, 9), col, 4.0, true)


## Two beamed eighth notes, crossed out when the music is off.
func _draw_music_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	var col := Color(1, 1, 1, 0.75)
	for x in [-9.0, 9.0]:
		hud.draw_circle(c + Vector2(x - 4, 10), 5.5, col)
		hud.draw_line(c + Vector2(x + 1, 10), c + Vector2(x + 1, -12), col, 3.0, true)
	hud.draw_line(c + Vector2(-8, -12), c + Vector2(10, -15), col, 5.0, true)
	if music.muted:
		hud.draw_line(c + Vector2(-20, -18), c + Vector2(20, 18), Color(BG_BOTTOM, 0.9), 7.0, true)
		hud.draw_line(c + Vector2(-20, -18), c + Vector2(20, 18), col, 3.0, true)


func _draw_sound_icon(rect: Rect2) -> void:
	var c := rect.get_center()
	var col := Color(1, 1, 1, 0.75)
	hud.draw_colored_polygon(PackedVector2Array([
		c + Vector2(-16, -6), c + Vector2(-8, -6), c + Vector2(2, -15),
		c + Vector2(2, 15), c + Vector2(-8, 6), c + Vector2(-16, 6),
	]), col)
	if sfx.muted:
		hud.draw_line(c + Vector2(8, -7), c + Vector2(20, 7), col, 3.0, true)
		hud.draw_line(c + Vector2(8, 7), c + Vector2(20, -7), col, 3.0, true)
	else:
		hud.draw_arc(c + Vector2(2, 0), 9, -PI / 3, PI / 3, 12, col, 3.0, true)
		hud.draw_arc(c + Vector2(2, 0), 16, -PI / 3, PI / 3, 16, col, 3.0, true)


func _menu_buttons() -> Array[Rect2]:
	var size := hud.size
	return [
		Rect2(size.x / 2.0 - 160, size.y * 0.77 - 48, 320, 96),
		Rect2(size.x / 2.0 - 150, size.y * 0.77 + 64, 300, 88),
	]


func _sound_button() -> Rect2:
	return Rect2(hud.size.x - 92, 24, 68, 68)


func _music_button() -> Rect2:
	return Rect2(hud.size.x - 168, 24, 68, 68)


func _info_button() -> Rect2:
	return Rect2(24, 24, 68, 68)


## Top center, between the score and the lives.
func _pause_button() -> Rect2:
	return Rect2(hud.size.x / 2.0 - 34, 22, 68, 68)


func _pause_buttons() -> Array[Rect2]:
	var size := hud.size
	return [
		Rect2(size.x / 2.0 - 150, size.y * 0.45, 300, 88),
		Rect2(size.x / 2.0 - 150, size.y * 0.45 + 108, 300, 88),
	]


## Music and sound effects toggles, side by side under the pause buttons.
func _pause_audio_buttons() -> Array[Rect2]:
	var y := hud.size.y * 0.45 + 232
	return [Rect2(hud.size.x / 2.0 - 84, y, 68, 68), Rect2(hud.size.x / 2.0 + 16, y, 68, 68)]


## Right under the rank line; the buttons move down to make room for it.
func _name_field() -> Rect2:
	return Rect2(hud.size.x / 2.0 - 170, hud.size.y * 0.62 - 6, 340, 66)


func _game_over_buttons() -> Array[Rect2]:
	var size := hud.size
	var y := size.y * 0.62 + (NAME_ROW if name_edit.visible else 0.0)
	return [
		Rect2(size.x / 2.0 - 150, y, 300, 88),
		Rect2(size.x / 2.0 - 150, y + 108, 300, 88),
	]


func _button(rect: Rect2, label: String, bg: Color, fg: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(int(rect.size.y / 2.0))
	sb.anti_aliasing = true
	if bg.a >= 1.0:
		sb.shadow_color = Color(bg, 0.35)
		sb.shadow_size = 14
	else:
		sb.border_color = Color(1, 1, 1, 0.35)
		sb.set_border_width_all(2)
	hud.draw_style_box(sb, rect)
	var fs := int(rect.size.y * 0.4)
	var baseline := rect.get_center().y + (font.get_ascent(fs) - font.get_descent(fs)) / 2.0
	hud.draw_string(font, Vector2(rect.position.x, baseline), label, HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x, fs, fg)


## Text with a soft drop shadow.
func _text(pos: Vector2, text: String, font_size: int, color: Color,
		align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	hud.draw_string(font, pos + Vector2(0, 4), text, align, width, font_size, Color(0, 0, 0, 0.35 * color.a))
	hud.draw_string(font, pos, text, align, width, font_size, color)


func _centered(text: String, y: float, font_size: int, color: Color) -> void:
	_text(Vector2(0, y), text, font_size, color, HORIZONTAL_ALIGNMENT_CENTER, hud.size.x)


# --- Save --------------------------------------------------------------------

func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	best = cfg.get_value("score", "best", 0)
	sfx.muted = cfg.get_value("settings", "muted", false)
	music.muted = cfg.get_value("settings", "music_muted", false)
	player_name = cfg.get_value("settings", "name", "")
	top.clear()
	for e in cfg.get_value("score", "top", []):
		if e is Dictionary:
			top.append(e)


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("score", "best", best)
	cfg.set_value("score", "top", top)
	cfg.set_value("settings", "muted", sfx.muted)
	cfg.set_value("settings", "music_muted", music.muted)
	cfg.set_value("settings", "name", player_name)
	cfg.save(SAVE_PATH)
