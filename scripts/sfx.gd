extends Node
## Procedural sound effects: every sound is synthesized at startup into an
## AudioStreamWAV, so the project needs no audio files.

const RATE := 22050
const VOICES := 8
## Major pentatonic from C5: consecutive hits climb this scale.
const PENTA: Array[float] = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5, 1174.66, 1318.51]

var muted := false
var _streams := {}
var _chimes: Array[AudioStreamWAV] = []
var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_streams["turn_left"] = _to_wav(_blip(540.0, 400.0, 0.06, 0.02, 0.3))
	_streams["turn_right"] = _to_wav(_blip(640.0, 480.0, 0.06, 0.02, 0.3))
	_streams["click"] = _to_wav(_blip(900.0, 600.0, 0.05, 0.015, 0.25))
	_streams["miss"] = _to_wav(_buzz(170.0, 60.0, 0.32, 0.12, 0.45))
	_streams["level"] = _to_wav(_arp([659.25, 783.99, 1046.5], 0.08, 0.3, 0.1, 0.3, 0.3))
	_streams["figure"] = _to_wav(_arp([523.25, 659.25, 783.99, 1046.5, 1318.51], 0.07, 0.35, 0.12, 0.28, 0.3))
	_streams["game_over"] = _to_wav(_arp([392.0, 311.13, 261.63, 196.0], 0.16, 0.4, 0.18, 0.35, 0.5))
	for f in PENTA:
		_chimes.append(_to_wav(_blip(f, f, 0.35, 0.12, 0.35, 0.3)))


func play(sound: String) -> void:
	_play(_streams[sound])


## Hit sound; `step` is the current streak, so a run of hits climbs the scale.
func chime(step: int) -> void:
	_play(_chimes[clampi(step, 0, _chimes.size() - 1)])


func _play(stream: AudioStreamWAV) -> void:
	if muted:
		return
	var p := _players[_next]
	_next = (_next + 1) % VOICES
	p.stream = stream
	p.play()


# --- Synthesis -----------------------------------------------------------------

func _env(t: float, attack: float, decay: float) -> float:
	return minf(t / attack, 1.0) * exp(-t / decay)


## Sine sweep from f0 to f1 with a percussive envelope; `harm` adds an octave.
func _blip(f0: float, f1: float, dur: float, decay: float, amp: float, harm := 0.0) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / dur) / RATE
		out[i] = (sin(phase) + harm * sin(2.0 * phase)) * amp * _env(t, 0.003, decay)
	return out


## Low, rough, falling tone with a bit of noise: the "wrong color" sound.
func _buzz(f0: float, f1: float, dur: float, decay: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(f0, f1, t / dur) / RATE
		var s := sin(phase) + 0.5 * sin(2.0 * phase) + 0.33 * sin(3.0 * phase) + randf_range(-0.15, 0.15)
		out[i] = s * amp * 0.6 * _env(t, 0.005, decay)
	return out


## Notes played one after the other, each `gap` seconds after the previous.
func _arp(freqs: Array, gap: float, note_dur: float, decay: float, amp: float, harm: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(int((gap * (freqs.size() - 1) + note_dur) * RATE))
	for k in freqs.size():
		var note := _blip(freqs[k], freqs[k], note_dur, decay, amp, harm)
		var offset := int(k * gap * RATE)
		for i in note.size():
			out[offset + i] += note[i]
	return out


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var fade := mini(int(0.005 * RATE), n) # short fade-out, avoids a click at the end
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var v := samples[i]
		if i >= n - fade:
			v *= float(n - 1 - i) / fade
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = data
	return wav
