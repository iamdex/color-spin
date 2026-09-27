extends Node
## Procedural background music, soft synth-pop in A minor / C major.
## Every note is synthesized once at startup, on a worker thread so the game
## doesn't wait for it; a step sequencer then mixes them in real time into an AudioStreamGenerator, so tempo and instrument layers can
## follow the game. No audio files.

const RATE := 22050
const BUFFER := 0.2        # seconds of audio queued ahead
const STEPS_PER_BAR := 16  # sixteenth notes
const BARS := 4
const OUT_GAIN := 0.5      # music sits under the sound effects
const FADE := 1.5          # layer / master gain change per second
const MENU_BPM := 92.0
const DUCKED := 0.3        # master level while the game is paused

enum Layer { PAD, BASS, DRUMS, ARP, LEAD, CLAP }

## Am - F - C - G, one chord per bar (MIDI notes).
const CHORDS := [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]]
const ROOTS := [45, 41, 48, 43]
## Arpeggio: index into [3rd-lowest chord tone + 12, ..., root + 24], one per 16th.
const ARP := [0, 1, 2, 3, 2, 1, 2, 3, 0, 1, 2, 3, 2, 1, 2, 1]
## Lead melody over the 4 bars: step in the loop -> MIDI note.
const LEAD := {
	0: 76, 4: 74, 6: 72, 8: 69, 12: 72, 14: 74,
	16: 72, 20: 69, 24: 72, 26: 74, 28: 76,
	32: 79, 36: 76, 38: 74, 40: 72, 44: 76, 46: 79,
	48: 74, 52: 76, 54: 74, 56: 74, 60: 71, 62: 74,
}

var muted := false:
	set(v):
		muted = v
		_update_master()

var _playback: AudioStreamGeneratorPlayback
var _render_task := -1
var _rendered := false
var _pad: Array[PackedFloat32Array] = []   # one pre-mixed chord per bar
var _bass := {}
var _arp := {}
var _lead := {}
var _kick: PackedFloat32Array
var _hat: PackedFloat32Array
var _clap: PackedFloat32Array
var _voices: Array = []                    # [samples, position, layer]
var _layer_gain: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _layer_target: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
var _master := 0.0
var _master_target := 0.0
var _playing := false
var _ducked := false
var _bpm := MENU_BPM
var _step := 0
var _to_next_step := 0.0                   # samples until the next 16th


func _ready() -> void:
	_render_task = WorkerThreadPool.add_task(_render)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = BUFFER
	var player := AudioStreamPlayer.new()
	player.stream = gen
	add_child(player)
	player.play()
	_playback = player.get_stream_playback()


## Calm version for the menu: pad, a little bass and the arpeggio.
func play_menu() -> void:
	_begin()
	_bpm = MENU_BPM
	_set_layers([1.0, 0.6, 0.0, 0.7, 0.0, 0.0])


## One more instrument with every new figure (tier), a bit faster every level.
func play_game(level: int, tier: int) -> void:
	_begin()
	set_level(level, tier)


func set_level(level: int, tier: int) -> void:
	_bpm = minf(100.0 + 2.0 * (level - 1), 128.0)
	var on := func(t: int) -> float: return 1.0 if tier >= t else 0.0
	_set_layers([1.0, 1.0, on.call(1), on.call(2), on.call(3), on.call(4)])


func set_ducked(on: bool) -> void:
	_ducked = on
	_update_master()


## Fades out; the next play_* starts again from the first bar.
func stop() -> void:
	_playing = false
	_update_master()


func _begin() -> void:
	if not _playing or _master < 0.01:
		_step = 0
		_to_next_step = 0.0
		_voices.clear()
		for i in _layer_gain.size():
			_layer_gain[i] = 0.0
	_playing = true
	_ducked = false
	_update_master()


func _set_layers(targets: Array) -> void:
	for i in targets.size():
		_layer_target[i] = targets[i]


func _update_master() -> void:
	if muted or not _playing:
		_master_target = 0.0
	else:
		_master_target = DUCKED if _ducked else 1.0


func _exit_tree() -> void:
	if _render_task >= 0 and not _rendered:
		WorkerThreadPool.wait_for_task_completion(_render_task)


# --- Sequencer and mixer -------------------------------------------------------

func _process(delta: float) -> void:
	var fade := FADE * delta
	_master = move_toward(_master, _master_target, fade)
	for i in _layer_gain.size():
		_layer_gain[i] = move_toward(_layer_gain[i], _layer_target[i], fade)
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	var out := PackedVector2Array()
	out.resize(n)
	if not _rendered and WorkerThreadPool.is_task_completed(_render_task):
		WorkerThreadPool.wait_for_task_completion(_render_task)
		_rendered = true
	if not _rendered or (_master <= 0.0 and _master_target <= 0.0):
		_voices.clear() # silent or not ready: feed zeros, don't advance the song
		_playback.push_buffer(out)
		return
	var buf := PackedFloat32Array()
	buf.resize(n)
	var i := 0
	while i < n:
		if _to_next_step <= 0.0:
			_trigger(_step)
			_step = (_step + 1) % (STEPS_PER_BAR * BARS)
			_to_next_step += RATE * 60.0 / _bpm / 4.0
		var chunk := mini(n - i, ceili(_to_next_step))
		_mix(buf, i, chunk)
		i += chunk
		_to_next_step -= chunk
	var g := _master * OUT_GAIN
	for k in n:
		var v := buf[k] * g
		out[k] = Vector2(v, v)
	_playback.push_buffer(out)


@warning_ignore("integer_division")
func _trigger(step: int) -> void:
	var bar := step / STEPS_PER_BAR
	var s := step % STEPS_PER_BAR
	if s == 0:
		_voice(_pad[bar], Layer.PAD)
	if s % 2 == 0:
		_voice(_bass[ROOTS[bar] + (12 if s == 6 or s == 14 else 0)], Layer.BASS)
	if s == 0 or s == 8:
		_voice(_kick, Layer.DRUMS)
	if s % 4 == 2:
		_voice(_hat, Layer.DRUMS)
	if s == 4 or s == 12:
		_voice(_clap, Layer.CLAP)
	_voice(_arp[_arp_note(bar, s)], Layer.ARP)
	if LEAD.has(step):
		_voice(_lead[LEAD[step]], Layer.LEAD)


func _arp_note(bar: int, s: int) -> int:
	var c: Array = CHORDS[bar]
	var tones := [c[0] + 12, c[1] + 12, c[2] + 12, c[0] + 24]
	return tones[ARP[s]]


## Silent layers don't start new notes, so muted parts cost nothing.
func _voice(samples: PackedFloat32Array, layer: int) -> void:
	if _layer_target[layer] > 0.0 or _layer_gain[layer] > 0.0:
		_voices.append([samples, 0, layer])


func _mix(buf: PackedFloat32Array, from: int, count: int) -> void:
	for vi in range(_voices.size() - 1, -1, -1):
		var v: Array = _voices[vi]
		var s: PackedFloat32Array = v[0]
		var pos: int = v[1]
		var g: float = _layer_gain[v[2]]
		var m := mini(count, s.size() - pos)
		for k in m:
			buf[from + k] += s[pos + k] * g
		pos += m
		if pos >= s.size():
			_voices.remove_at(vi)
		else:
			v[1] = pos


# --- Instruments -----------------------------------------------------------------

func _render() -> void:
	for c in CHORDS:
		var chord := PackedFloat32Array()
		chord.resize(int(2.8 * RATE))
		for m in c:
			_add(chord, _pad_note(_freq(m)))
		_pad.append(chord)
	for r in ROOTS:
		_bass[r] = _tone(_freq(r), 0.4, 0.005, 0.18, 0.32, [1.0, 0.5, 0.25])
		_bass[r + 12] = _tone(_freq(r + 12), 0.4, 0.005, 0.18, 0.28, [1.0, 0.5, 0.25])
	for bar in BARS:
		for s in STEPS_PER_BAR:
			var m := _arp_note(bar, s)
			if not _arp.has(m):
				_arp[m] = _tone(_freq(m), 0.3, 0.002, 0.07, 0.1, [1.0, 0.3])
	for m in LEAD.values():
		if not _lead.has(m):
			_lead[m] = _lead_note(_freq(m))
	_kick = _sweep(150.0, 45.0, 0.25, 0.12, 0.5)
	_hat = _noise(0.05, 0.015, 0.07, true)
	_clap = _noise(0.15, 0.05, 0.12, false)


func _freq(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


func _env(t: float, attack: float, decay: float) -> float:
	return minf(t / attack, 1.0) * exp(-t / decay)


func _add(into: PackedFloat32Array, s: PackedFloat32Array) -> void:
	for i in mini(into.size(), s.size()):
		into[i] += s[i]


## A plucked or held note: harmonics[k] is the level of harmonic k + 1.
func _tone(f: float, dur: float, attack: float, decay: float, amp: float, harmonics: Array) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var inc := TAU * f / RATE
	for i in n:
		var ph := inc * i
		var v := 0.0
		for h in harmonics.size():
			v += harmonics[h] * sin(ph * (h + 1))
		out[i] = v * amp * _env(float(i) / RATE, attack, decay)
	return out


## Soft chord pad: two slightly detuned oscillators for a chorus effect.
func _pad_note(f: float) -> PackedFloat32Array:
	var n := int(2.8 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var inc1 := TAU * f / RATE
	var inc2 := TAU * f * 1.004 / RATE
	for i in n:
		var a := inc1 * i
		var b := inc2 * i
		var v := sin(a) + 0.35 * sin(2.0 * a) + sin(b) + 0.15 * sin(3.0 * b)
		out[i] = v * 0.045 * _env(float(i) / RATE, 0.35, 1.6)
	return out


## Lead voice with a gentle vibrato that fades in.
func _lead_note(f: float) -> PackedFloat32Array:
	var n := int(0.7 * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * f * (1.0 + 0.004 * sin(TAU * 5.5 * t) * minf(t / 0.15, 1.0)) / RATE
		var v := sin(phase) + 0.25 * sin(2.0 * phase) + 0.1 * sin(3.0 * phase)
		out[i] = v * 0.14 * _env(t, 0.01, 0.3)
	return out


func _sweep(f0: float, f1: float, dur: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / dur) / RATE
		out[i] = sin(phase) * amp * _env(t, 0.003, decay)
	return out


## Noise burst; `bright` keeps only the highs (hi-hat) instead of the full band (clap).
func _noise(dur: float, decay: float, amp: float, bright: bool) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var prev := 0.0
	for i in n:
		var x := randf_range(-1.0, 1.0)
		var v := x - prev if bright else x
		prev = x
		out[i] = v * amp * _env(float(i) / RATE, 0.002, decay)
	return out
