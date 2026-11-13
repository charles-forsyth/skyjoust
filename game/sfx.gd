class_name Sfx
extends Node
## Tiny sound manager: pooled one-shots, ambience loop, music (OFF by default, saved toggle).

const CFG := "user://settings.cfg"
const VOL := {
	"flap": -14.0, "dash": -6.0, "clash": -6.0, "kill": -4.0, "egg": -6.0, "hatch": -6.0, "death": -3.0,
	"sizzle": -6.0, "screech": -4.0, "wave": -8.0, "life": -6.0,
}

var streams := {}
var pool: Array[AudioStreamPlayer] = []
var amb: AudioStreamPlayer
var music: AudioStreamPlayer
var music_on := false
var muted := false


func _ready() -> void:
	for k in VOL.keys():
		var path := "res://assets/sfx/%s.mp3" % k
		if ResourceLoader.exists(path):
			streams[k] = load(path)
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		pool.append(p)
	amb = AudioStreamPlayer.new()
	add_child(amb)
	if ResourceLoader.exists("res://assets/sfx/ambience.mp3"):
		var a: AudioStreamMP3 = load("res://assets/sfx/ambience.mp3")
		a.loop = true
		amb.stream = a
		amb.volume_db = -16.0
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		music_on = cfg.get_value("audio", "music", false)
		muted = cfg.get_value("audio", "muted", false)
	_apply()


func start_ambience() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if amb.stream != null and not amb.playing:
		amb.play()


func play(name: String, pitch_jitter := 0.06) -> void:
	if muted or DisplayServer.get_name() == "headless" or not streams.has(name):
		return
	for p in pool:
		if not p.playing:
			p.stream = streams[name]
			p.volume_db = VOL.get(name, -6.0)
			p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
			p.play()
			return


func toggle_music() -> void:
	music_on = not music_on
	_apply()
	_save()


func toggle_mute() -> void:
	muted = not muted
	_apply()
	_save()


func _apply() -> void:
	AudioServer.set_bus_mute(0, muted)
	if music_on:
		if music == null:
			# only create the music player when music is wanted
			music = AudioStreamPlayer.new()
			add_child(music)
			var m: AudioStreamMP3 = load("res://assets/music/theme.mp3")
			m.loop = true
			music.stream = m
			music.volume_db = -12.0
		if not music.playing:
			music.play()
	elif music != null:
		music.stop()


func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "muted", muted)
	cfg.save(CFG)


func _exit_tree() -> void:
	for p in pool:
		p.stop()
		p.stream = null
	if amb != null:
		amb.stop()
		amb.stream = null
	if music != null:
		music.stop()
		music.stream = null
	streams.clear()
