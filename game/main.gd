extends Node3D
## Skyjoust: a modern Joust-style single-screen arena. All gameplay is deterministic
## 2D maths in the x/y plane; the 3D scene only mirrors it.
## Run flags (after --): --demo (autopilot + scripted captures), --sim=SECONDS (headless playtest).

const HALF := 15.0          # arena spans x in [-HALF, HALF) and wraps
const LAVA_Y := -1.2        # below this you are in the lava
const JOUST_MARGIN := 0.22  # lance height difference needed to win outright
const PTERO_AFTER := 40.0   # seconds into a wave before the pterodactyl hunts you

const PLATS: Array[Rect2] = [
	Rect2(-9.0, -0.4, 18.0, 1.6),     # base bridge (top y=1.2)
	Rect2(-15.0, 4.6, 4.6, 0.7),      # left edge ledge (wraps with the right one)
	Rect2(10.4, 4.6, 4.6, 0.7),
	Rect2(-4.0, 6.2, 7.5, 0.7),       # centre ledge
	Rect2(-11.5, 9.4, 5.5, 0.7),      # upper left
	Rect2(6.0, 8.9, 6.0, 0.7),        # upper right
	Rect2(-15.0, 12.4, 3.4, 0.7),     # top edge ledge (wraps)
	Rect2(11.6, 12.4, 3.4, 0.7),
	Rect2(-2.0, 12.6, 5.0, 0.7),      # top centre
]
const SPAWNS: Array[Vector2] = [
	Vector2(-5.5, 1.2), Vector2(5.5, 1.2), Vector2(-0.3, 6.9),
	Vector2(-8.7, 10.1), Vector2(9.0, 9.6),
]
const KILL_SCORE := {Rider.Kind.BOUNDER: 500, Rider.Kind.HUNTER: 750, Rider.Kind.SHADOW: 1500}
const EGG_SCORE: Array[int] = [250, 500, 750, 1000]

enum State { TITLE, PLAY, WAVE_CLEAR, DEAD, GAME_OVER }
enum Mode { CLASSIC, DAILY, PEACEFUL }

var state: int = State.TITLE
var mode: int = Mode.CLASSIC
var player: Rider
var enemies: Array[Rider] = []
var eggs: Array[Egg] = []
var score := 0
var lives := 5
var wave := 0
var wave_t := 0.0
var state_t := 0.0
var egg_streak := 0
var next_life := 20000
var pending_spawns: Array[int] = []
var spawn_timer := 0.0
var hitstop := 0.0
var slowmo_t := 0.0
var shake := 0.0
var rng := RandomNumberGenerator.new()
var vis_rng := RandomNumberGenerator.new()

var ptero: Node3D
var ptero_pos := Vector2.ZERO
var ptero_vel := Vector2.ZERO
var ptero_alive := false
var ptero_next_t := PTERO_AFTER
var fleeing_mounts: Array = []   # [node:Node3D, wings:Array, pos:Vector2, vx:float, t:float]

var powerups: Array = []   # [node, pos:Vector2, kind:String, t]
var shield := 0.0
var long_lance := 0.0
var plat_nodes: Array[Node3D] = []
var plat_on: Array[bool] = []
var plat_stand: Array[float] = []
var plat_down: Array[float] = []
var live_plats: Array[Rect2] = []
const CRUMBLE := [1, 2, 6, 7]
var hand: Node3D
var hand_knuckles: Array[Node3D] = []
var hand_x := 0.0
var hand_t := 0.0
var hand_target: Rider = null
var hand_cd := 6.0
var hand_grip := false

const THEMES := [
	{"bd": "backdrop", "sun": Color(1.0, 0.86, 0.68), "amb": Color(0.85, 0.78, 0.9), "bg": Color(0.98, 0.78, 0.62), "haze": Color(1.0, 0.62, 0.36), "tint": Color(1, 1, 1), "amb_e": 0.55, "rim": Color(1, 0.9, 0.7, 0.5), "name": "SUNSET ISLES"},
	{"bd": "backdrop_dusk", "sun": Color(0.75, 0.7, 1.0), "amb": Color(0.7, 0.6, 0.95), "bg": Color(0.35, 0.2, 0.45), "haze": Color(0.75, 0.35, 0.55), "tint": Color(1.0, 0.7, 0.9), "amb_e": 0.8, "rim": Color(1, 0.8, 1.0, 1.1), "name": "MOONLIT RUINS"},
	{"bd": "backdrop_storm", "sun": Color(0.85, 0.95, 1.0), "amb": Color(0.7, 0.85, 0.95), "bg": Color(0.25, 0.35, 0.4), "haze": Color(0.42, 0.5, 0.55), "tint": Color(0.75, 0.6, 1.0), "amb_e": 0.9, "rim": Color(1.0, 0.85, 0.55, 1.4), "name": "STORM CRAGS"},
	{"bd": "backdrop_ember", "sun": Color(1.0, 0.6, 0.4), "amb": Color(0.9, 0.55, 0.45), "bg": Color(0.5, 0.15, 0.08), "haze": Color(0.9, 0.35, 0.15), "tint": Color(1.1, 0.9, 0.8), "amb_e": 0.6, "rim": Color(1, 0.95, 0.8, 0.7), "name": "EMBER PEAKS"},
]
var theme_idx := -1
var backdrop_mat: StandardMaterial3D
var sun_light: DirectionalLight3D
var env_res: Environment
var lava_mat: ShaderMaterial

var cam: Camera3D
var cam_base := Vector3.ZERO
var hud_score: Label
var hud_lives: Label
var hud_powers: Label
var hud_wave: Label
var banner: Label
var sub: Label
var popups: Node3D
var banner_tw: Tween
var saved_banner_txt := ""
var saved_banner_a := 0.0
var help_saved_vis := [false, false]
var toast_seq := 0
var pctl: Node

var demo := false
var sim_seconds := 0.0
var sfx: Sfx
var max_wave_seen := 0
var hand_grabs := 0
var best := 0
var daily_best := 0
var daily_key := ""
var peaceful_eggs := 0
var hud_best: Label
var help_panel: PanelContainer
var stats := {"kills": 0, "deaths": 0, "eggs": 0, "hatched": 0, "waves": 0, "ptero": 0, "bounces": 0}


func _daily_info() -> Array:
	var d := Time.get_date_dict_from_system()
	var k := "%04d-%02d-%02d" % [d.get("year", 2026), d.get("month", 1), d.get("day", 1)]
	var s: int = int(d.get("year", 2026)) * 10000 + int(d.get("month", 1)) * 100 + int(d.get("day", 1))
	return [k, s]


func _ready() -> void:
	rng.seed = 1982
	vis_rng.seed = 1982
	var di := _daily_info()
	daily_key = di[0]
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			demo = true
		elif a.begins_with("--sim="):
			sim_seconds = float(a.substr(6))
	_build_world()
	_build_hud()
	sfx = Sfx.new()
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(sfx)
	pctl = (load("res://pause_ctl.gd") as GDScript).new()
	add_child(pctl)
	pctl.toggle_music.connect(_on_toggle_music)
	pctl.toggle_mute.connect(_on_toggle_mute)
	pctl.toggle_pause.connect(_on_toggle_pause)
	pctl.toggle_help.connect(_on_toggle_help)
	pctl.quit_to_title.connect(_return_to_title)
	var cfg := ConfigFile.new()
	if cfg.load("user://settings.cfg") == OK:
		best = cfg.get_value("score", "best", 0)
		if cfg.get_value("daily", "date", "") == daily_key:
			daily_best = cfg.get_value("daily", "best", 0)
	_update_hud()
	if sim_seconds <= 0.0 and (not demo or OS.has_environment("SJ_AUDIO")):
		sfx.start_ambience()
	elif demo and not OS.has_environment("SJ_AUDIO"):
		AudioServer.set_bus_mute(0, true)
	if sim_seconds > 0.0:
		_run_sim()
		await get_tree().process_frame
		get_tree().quit()
		return
	if demo:
		_start_game()
		if OS.has_environment("SJ_START_WAVE"):
			wave = int(OS.get_environment("SJ_START_WAVE")) - 1
			for e in enemies:
				e.queue_free()
			enemies.clear()
			_next_wave()
			if OS.has_environment("SJ_POWER"):
				_drop_power(Vector2(-3, 8), "shield")
				_drop_power(Vector2(4, 9), "lance")


# ===================================================================== world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.98, 0.78, 0.62)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.78, 0.9)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.ssao_enabled = true
	env.environment = e
	add_child(env)
	env_res = e

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.86, 0.68)
	sun.light_energy = 1.25
	sun.rotation_degrees = Vector3(-38, -32, 0)
	sun.shadow_enabled = true
	sun_light = sun
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.6, 0.65, 1.0)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-20, 150, 0)
	add_child(fill)
	var lava_light := OmniLight3D.new()
	lava_light.light_color = Color(1.0, 0.45, 0.15)
	lava_light.light_energy = 3.0
	lava_light.omni_range = 22.0
	lava_light.position = Vector3(0, -3.0, 4)
	var l2 := lava_light.duplicate() as OmniLight3D
	l2.position = Vector3(-12, -3.0, 4)
	add_child(l2)
	var l3 := lava_light.duplicate() as OmniLight3D
	l3.position = Vector3(12, -3.0, 4)
	add_child(l3)
	add_child(lava_light)

	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = 50.0
	cam_base = Vector3(0, 7.4, 15.4 / tan(deg_to_rad(25.0)))
	cam.position = cam_base
	add_child(cam)

	# painted backdrop on a big quad far behind the arena
	var bd_path := "res://assets/art/backdrop.png"
	if ResourceLoader.exists(bd_path):
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(110, 61.4)
		q.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(bd_path)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material_override = m
		backdrop_mat = m
		q.position = Vector3(0, 9.0, -60)
		add_child(q)

	_build_lava()
	for i in PLATS.size():
		_build_platform(PLATS[i], i)
	for s: Vector2 in SPAWNS:
		_build_pad(s)
	popups = Node3D.new()
	add_child(popups)
	live_plats = PLATS.duplicate()


func _build_lava() -> void:
	# a facing band the camera actually sees, plus a floor plane receding behind it
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/lava.gdshader")
	lava_mat = sm
	var band := MeshInstance3D.new()
	var qm := PlaneMesh.new()
	qm.size = Vector2(90, 6)
	qm.subdivide_width = 140
	qm.subdivide_depth = 8
	qm.orientation = PlaneMesh.FACE_Z
	band.mesh = qm
	band.material_override = sm
	band.position = Vector3(0, LAVA_Y - 2.9, 2.5)
	band.rotation.x = deg_to_rad(-35)
	add_child(band)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(110, 40)
	floor.mesh = pm
	floor.material_override = sm
	floor.position = Vector3(0, LAVA_Y - 0.6, -18)
	add_child(floor)
	# embers drifting up out of the lava
	var em := CPUParticles3D.new()
	em.amount = 70
	em.lifetime = 3.5
	em.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	em.emission_box_extents = Vector3(18, 0.3, 1.5)
	em.direction = Vector3(0, 1, 0)
	em.spread = 12.0
	em.initial_velocity_min = 1.2
	em.initial_velocity_max = 2.8
	em.gravity = Vector3(0.3, 0.2, 0)
	em.scale_amount_min = 0.5
	em.scale_amount_max = 1.3
	var eq := QuadMesh.new()
	eq.size = Vector2(0.3, 0.3)
	eq.material = _soft_mat(Color(1.0, 0.45, 0.1), 2.0)
	em.mesh = eq
	em.color_ramp = _fade_ramp()
	em.position = Vector3(0, LAVA_Y - 0.4, 0.5)
	add_child(em)


var _soft_tex: Texture2D
var _fade_grad: Gradient
var _puff_quad: QuadMesh
var _ring_quad: QuadMesh
var _ring_mat_proto: StandardMaterial3D


func _soft() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.8))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_tex = t
	return _soft_tex


func _soft_mat(c: Color, emis: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = _soft()
	m.albedo_color = c * emis
	m.vertex_color_use_as_albedo = true
	return m


func _fade_ramp() -> Gradient:
	if _fade_grad == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 0.3, 0.1, 0))
		_fade_grad = g
	return _fade_grad


func _build_platform(r: Rect2, idx: int) -> void:
	var root := Node3D.new()
	root.position = Vector3(r.get_center().x, r.end.y, 0)
	add_child(root)
	plat_nodes.append(root)
	plat_on.append(true)
	plat_stand.append(0.0)
	plat_down.append(0.0)
	var wide: bool = r.size.x > 12.0
	var model := "platform_base" if wide else ("platform_long" if (r.size.x > 4.5) != (idx % 3 == 0) else "platform_short")
	var path := "res://assets/models/%s.glb" % model
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(m)
		_fit_platform(m, r, not wide and idx % 2 == 1)
		if not wide:
			var dy: float = [1.0, 1.35, 0.8, 0.55, 0.9, 1.15, 0.75, 1.25, 0.85][idx % 9]
			m.scale.y *= dy
			m.position.y *= dy
		ModelFit.matte(m)
		return
	# placeholder: grassy top slab over a tapering rock
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(r.size.x, 0.28, 2.2)
	top.mesh = tb
	top.material_override = _flat(Color(0.42, 0.72, 0.32))
	top.position.y = -0.14
	root.add_child(top)
	var rock := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 0.35
	cm.height = 1.0
	cm.radial_segments = 7
	rock.mesh = cm
	var depth: float = 1.8 if wide else 1.4 + float(idx % 3) * 0.3
	rock.scale = Vector3(r.size.x * 0.5, depth, 1.1)
	rock.position.y = -0.28 - depth * 0.5
	rock.material_override = _flat(Color(0.48, 0.33, 0.26))
	root.add_child(rock)


func _fit_platform(m: Node3D, r: Rect2, flip := false) -> void:
	var b := ModelFit.aabb(m)
	if b.size.x <= 0.0001:
		return
	# generated ledges may face any way; put the long axis along x and rotate alternate ledges 180 deg
	var yaw: float = PI * 0.5 if b.size.z > b.size.x else 0.0
	if flip:
		yaw += PI
	m.rotation.y = yaw
	b = ModelFit.aabb(m)
	var sx: float = r.size.x / b.size.x
	var sz: float = 2.4 / maxf(b.size.z, 0.001)
	var sy: float = clampf(sx, 0.5, 2.5)
	m.scale = Vector3(sx, sy, sz)
	var c := b.get_center()
	m.position = Vector3(-c.x * sx, -b.end.y * sy, -c.z * sz)


func _build_pad(p: Vector2) -> void:
	var pad_path := "res://assets/models/spawn_pad.glb"
	if ResourceLoader.exists(pad_path):
		var root := Node3D.new()
		root.position = Vector3(p.x, p.y - 0.24, 0)
		root.scale = Vector3(1.25, 1.0, 1.25)
		add_child(root)
		var m: Node3D = (load(pad_path) as PackedScene).instantiate()
		root.add_child(m)
		ModelFit.fit(m, 0.32, 0.0)
		ModelFit.matte(m)
	var ring := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 0.52
	t.outer_radius = 0.66
	ring.mesh = t
	ring.material_override = _flat(Color(0.2, 0.95, 0.9), 2.0)
	ring.position = Vector3(p.x, p.y + 0.04, 0)
	ring.scale = Vector3(1, 0.25, 1)
	add_child(ring)


func _flat(c: Color, emis := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	return m


# ======================================================================= HUD

var _font: Font


func _label(size: int, anchor_preset: int, txt := "") -> Label:
	if _font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Avenir Next", "Futura", "Helvetica Neue"])
		sf.font_weight = 800
		_font = sf
	var l := Label.new()
	l.add_theme_font_override("font", _font)
	l.text = txt
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 0.98, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0.2))
	l.add_theme_constant_override("outline_size", maxi(size / 6, 4))
	l.set_anchors_and_offsets_preset(anchor_preset, Control.PRESET_MODE_MINSIZE, 24)
	return l


func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var bar := TextureRect.new()
	var gt := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.15, 0.06, 0.16, 0.55))
	gr.set_color(1, Color(0.15, 0.06, 0.16, 0.0))
	gt.gradient = gr
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	bar.texture = gt
	bar.stretch_mode = TextureRect.STRETCH_SCALE
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 110
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(bar)
	hud_score = _label(40, Control.PRESET_TOP_LEFT, "0")
	hud_lives = _label(32, Control.PRESET_TOP_RIGHT, "")
	hud_wave = _label(30, Control.PRESET_CENTER_TOP, "")
	hud_best = _label(22, Control.PRESET_TOP_LEFT, "")
	hud_best.offset_top += 62
	cl.add_child(hud_best)
	hud_powers = _label(22, Control.PRESET_TOP_RIGHT, "")
	hud_powers.offset_top += 58
	hud_powers.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_powers.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud_powers.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	cl.add_child(hud_powers)
	hud_lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud_lives.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hud_wave.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hud_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [hud_score, hud_lives, hud_wave]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.18, 0.07, 0.2, 0.55)
		sb.set_corner_radius_all(18)
		sb.content_margin_left = 18
		sb.content_margin_right = 18
		sb.content_margin_top = 4
		sb.content_margin_bottom = 6
		sb.border_color = Color(1, 0.85, 0.55, 0.7)
		sb.set_border_width_all(2)
		l.add_theme_stylebox_override("normal", sb)
		l.add_theme_color_override("font_color", Color(1, 0.93, 0.7))
		cl.add_child(l)
	banner = _label(84, Control.PRESET_CENTER, "SKYJOUST")
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	cl.add_child(banner)
	sub = _label(28, Control.PRESET_CENTER, "")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.offset_top += 96
	sub.offset_bottom += 96
	cl.add_child(sub)
	sub.text = _title_sub_text()
	_build_help_card(cl)


func _title_sub_text() -> String:
	return "SPACE / ENTER: Classic Arcade     C: Daily Challenge     F: Peaceful Flight\n\nA / D or Arrows: steer     SPACE / W: flap     SHIFT / J: air-dash\nHigher lance wins. Catch golden eggs before they hatch.\n\nH: Help & Rules     ESC: Pause     M: Music (off)     N: Mute"


func _build_help_card(cl: CanvasLayer) -> void:
	help_panel = PanelContainer.new()
	help_panel.set_anchors_preset(Control.PRESET_CENTER)
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	help_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	help_panel.custom_minimum_size = Vector2(980, 440)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.04, 0.13, 0.98)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	sb.border_color = Color(1.0, 0.85, 0.52, 0.85)
	sb.set_border_width_all(3)
	help_panel.add_theme_stylebox_override("panel", sb)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 44)
	help_panel.add_child(cols)
	var left := _label(22, Control.PRESET_TOP_LEFT,
		"CONTROLS\n\n" +
		"Steer:   A / D, Left / Right, Left Stick\n" +
		"Flap:    SPACE, W, Up, Gamepad A\n" +
		"Dash:    SHIFT, J, Gamepad X / RB\n" +
		"Pause:   ESC or P  (Q returns to Title)\n" +
		"Audio:   M toggles Music   N Mutes all\n" +
		"Help:    H or F1 closes this card")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var right := _label(22, Control.PRESET_TOP_LEFT,
		"ARENA RULES & MODES\n\n" +
		"Higher lance tip wins every joust.\n" +
		"Air-Dash surges forward + breaks ties.\n" +
		"Catch falling eggs in mid-air (+500).\n" +
		"Wave 3+: Lava Troll Hand grabs low riders.\n" +
		"Wave 6+: Side ledges crumble under feet.\n" +
		"Modes: Classic, Daily Seed (C), Peaceful (F).")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	cols.add_child(right)
	help_panel.visible = false
	cl.add_child(help_panel)


func _save_best() -> void:
	if demo or mode == Mode.PEACEFUL:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://settings.cfg")
	if mode == Mode.DAILY:
		if score <= daily_best:
			return
		daily_best = score
		cfg.set_value("daily", "date", daily_key)
		cfg.set_value("daily", "best", daily_best)
	else:
		if score <= best:
			return
		best = score
		cfg.set_value("score", "best", best)
	cfg.save("user://settings.cfg")


func _toast(t: String) -> void:
	toast_seq += 1
	var seq := toast_seq
	hud_wave.text = t
	hud_wave.visible = true
	get_tree().create_timer(1.2, true).timeout.connect(func() -> void:
		if seq == toast_seq:
			_update_hud()
	)


func _update_hud() -> void:
	hud_score.text = "%d" % score
	if hud_best != null:
		if mode == Mode.DAILY:
			hud_best.text = "DAILY BEST %d" % maxi(daily_best, score)
		elif mode == Mode.PEACEFUL:
			hud_best.text = "PEACEFUL SKY"
		else:
			hud_best.text = "BEST %d" % maxi(best, score)
	hud_lives.text = "RELAX" if mode == Mode.PEACEFUL else ("LIVES  %d" % lives)
	if hud_powers != null:
		var ps: Array[String] = []
		if state == State.PLAY and player != null:
			ps.append("DASH %.1fs" % player.dash_cd if player.dash_cd > 0.05 else "DASH READY")
		if shield > 0.0:
			ps.append("SHIELD")
		if long_lance > 0.0:
			ps.append("LONG LANCE %ds" % ceili(long_lance))
		hud_powers.text = "   ".join(ps)
	if toast_seq == 0 or not hud_wave.text.begins_with("Music") and not hud_wave.text.begins_with("Sound"):
		if mode == Mode.PEACEFUL and state != State.TITLE:
			hud_wave.text = "EGGS %d" % peaceful_eggs
		elif mode == Mode.DAILY and wave > 0:
			hud_wave.text = "DAILY %s  WAVE %d" % [daily_key, wave]
		else:
			hud_wave.text = "WAVE %d" % wave if wave > 0 else ""
	hud_wave.visible = hud_wave.text != ""


# ================================================================ game flow

func _restore_all_platforms() -> void:
	for i in plat_on.size():
		plat_on[i] = true
		plat_stand[i] = 0.0
		plat_down[i] = 0.0
		var r: Rect2 = PLATS[i]
		var n: Node3D = plat_nodes[i]
		n.position = Vector3(r.get_center().x, r.end.y, 0)
		n.scale = Vector3.ONE
		n.visible = true
	live_plats = PLATS.duplicate()


func _start_game(m: int = Mode.CLASSIC) -> void:
	mode = m
	var di := _daily_info()
	daily_key = di[0]
	if mode == Mode.DAILY:
		rng.seed = int(di[1])
	elif not demo and sim_seconds <= 0.0:
		rng.randomize()
	_restore_all_platforms()
	score = 0
	lives = 5
	wave = 0
	peaceful_eggs = 0
	next_life = 20000
	shield = 0.0
	long_lance = 0.0
	hitstop = 0.0
	slowmo_t = 0.0
	shake = 0.0
	if help_panel != null:
		help_panel.visible = false
	stats["_died_this_wave"] = false
	hand_target = null
	hand_grip = false
	hand_cd = 6.0
	if hand != null:
		hand.visible = false
		hand.position.y = LAVA_Y - 3.0
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for g in eggs:
		g.queue_free()
	eggs.clear()
	for pu in powerups:
		(pu[0] as Node).queue_free()
	powerups.clear()
	for fm in fleeing_mounts:
		(fm[0] as Node).queue_free()
	fleeing_mounts.clear()
	pending_spawns.clear()
	_kill_ptero()
	_spawn_player()
	if mode == Mode.PEACEFUL:
		_apply_theme(0)
		_replenish_peaceful_eggs()
		_flash("PEACEFUL FLIGHT\nGATHER GOLDEN EGGS", 1.8)
	else:
		_next_wave()
	state = State.PLAY


func _replenish_peaceful_eggs() -> void:
	while eggs.size() < 5:
		var idx: int = 1 + rng.randi_range(0, PLATS.size() - 2)
		var p: Rect2 = PLATS[idx]
		var x: float = clampf(p.get_center().x + rng.randf_range(-p.size.x * 0.35, p.size.x * 0.35), p.position.x + 0.4, p.end.x - 0.4)
		_drop_egg(Vector2(x, p.end.y + 0.14), Vector2.ZERO, 0)


func _return_to_title() -> void:
	if demo:
		return
	if help_panel != null:
		help_panel.visible = false
	get_tree().paused = false
	if banner_tw != null and banner_tw.is_valid():
		banner_tw.kill()
	for e in enemies:
		e.queue_free()
	enemies.clear()
	for g in eggs:
		g.queue_free()
	eggs.clear()
	for pu in powerups:
		(pu[0] as Node).queue_free()
	powerups.clear()
	for fm in fleeing_mounts:
		(fm[0] as Node).queue_free()
	fleeing_mounts.clear()
	pending_spawns.clear()
	_kill_ptero()
	if player != null:
		player.queue_free()
		player = null
	if hand != null:
		hand.visible = false
	_restore_all_platforms()
	_apply_theme(0)
	mode = Mode.CLASSIC
	wave = 0
	score = 0
	shield = 0.0
	long_lance = 0.0
	slowmo_t = 0.0
	state = State.TITLE
	state_t = 0.0
	banner.text = "SKYJOUST"
	banner.modulate.a = 1.0
	banner.visible = true
	sub.text = _title_sub_text()
	sub.visible = true
	_update_hud()


func _spawn_player() -> void:
	if player != null:
		player.queue_free()
	player = Rider.new()
	add_child(player)
	player.setup(Rider.Kind.PLAYER, Vector2(0.0, 1.2), 1)
	player.spawn_t = 1.0
	player.invuln = 2.5


func _next_wave() -> void:
	wave += 1
	wave_t = 0.0
	ptero_next_t = PTERO_AFTER
	egg_streak = 0
	stats["waves"] = wave
	pending_spawns.clear()
	var n: int = mini(3 + wave, 9)
	for i in n:
		var r := rng.randf()
		var k: int = Rider.Kind.BOUNDER
		if wave >= 3 and r < 0.15 + 0.05 * wave:
			k = Rider.Kind.SHADOW if wave >= 5 and r < 0.06 * (wave - 3) else Rider.Kind.HUNTER
		pending_spawns.append(k)
	spawn_timer = 0.8
	var title := "WAVE %d" % wave
	var ti: int = ((wave - 1) / 4) % THEMES.size()
	if ti != theme_idx:
		_apply_theme(ti)
		if wave > 1:
			title = THEMES[ti]["name"] + "\n" + title
	if wave % 5 == 0:
		title += "\nEGG WAVE"
		# egg wave: restore any crumbled ledges, then place eggs across all 8 elevated ledges
		_restore_all_platforms()
		pending_spawns.clear()
		for i in 8:
			var p: Rect2 = PLATS[1 + (i % (PLATS.size() - 1))]
			_drop_egg(Vector2(p.get_center().x + rng.randf_range(-0.8, 0.8), p.end.y + 0.12), Vector2.ZERO, 0)
	_flash(title, 1.8)
	if sfx != null:
		sfx.play("wave", 0.0)
	_kill_ptero()


func _apply_theme(i: int) -> void:
	if i == theme_idx or backdrop_mat == null:
		return
	theme_idx = i
	var th: Dictionary = THEMES[i % THEMES.size()]
	var path := "res://assets/art/%s.png" % th["bd"]
	if ResourceLoader.exists(path):
		backdrop_mat.albedo_texture = load(path)
	sun_light.light_color = th["sun"]
	env_res.ambient_light_color = th["amb"]
	env_res.background_color = th["bg"]
	lava_mat.set_shader_parameter("haze", th["haze"])
	lava_mat.set_shader_parameter("tint", th["tint"])
	env_res.ambient_light_energy = th["amb_e"]


func _apply_wave_scaling(e: Rider) -> void:
	e.max_vx *= 1.0 + minf(0.04 * float(wave - 1), 0.4)
	e.ai_flap_cd *= maxf(1.0 - 0.03 * float(wave - 1), 0.7)


func _spawn_enemy(k: int) -> void:
	var best_pad := SPAWNS[0]
	var far := -1.0
	for s: Vector2 in SPAWNS:
		var d: float = s.distance_to(player.pos) + rng.randf() * 4.0
		if d > far:
			far = d
			best_pad = s
	var e := Rider.new()
	add_child(e)
	e.setup(k, best_pad, -1 if best_pad.x > 0.0 else 1)
	e.spawn_t = 1.2
	e.ai_dir = e.facing
	_apply_wave_scaling(e)
	e.ai_alt = rng.randf_range(4.0, 12.5)
	enemies.append(e)


func _flash(txt: String, secs: float) -> void:
	if banner_tw != null and banner_tw.is_valid():
		banner_tw.kill()
	banner.text = txt
	banner.visible = true
	sub.visible = false
	banner.modulate.a = 1.0
	banner_tw = create_tween()
	banner_tw.tween_interval(secs)
	banner_tw.tween_property(banner, "modulate:a", 0.0, 0.4)


# ================================================================== update

func _physics_process(dt: float) -> void:
	if sim_seconds > 0.0 or get_tree().paused:
		return
	_tick(dt, _player_input())
	_update_visuals(dt)
	if OS.has_environment("SJ_DEBUG") and Engine.get_physics_frames() % 60 == 0:
		print("DBG f=%d state=%d p=%s spawn=%.2f vis=%s e=%d e0=%s" % [Engine.get_physics_frames(), state, str(player.pos), player.spawn_t, str(player.vis.scale), enemies.size(), str(enemies[0].pos) if enemies.size() > 0 else "-"])


func _player_input() -> Array:
	if demo:
		return _autopilot()
	var ix := Input.get_axis("ui_left", "ui_right")
	var joy := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	if absf(joy) > 0.3:
		ix += joy
	if Input.is_key_pressed(KEY_A):
		ix -= 1.0
	if Input.is_key_pressed(KEY_D):
		ix += 1.0
	ix = clampf(ix, -1.0, 1.0)
	var flap := Input.is_action_just_pressed("flap")
	var dash := Input.is_action_just_pressed("dash")
	return [ix, flap, dash]


func _on_toggle_help() -> void:
	if demo or help_panel == null:
		return
	if not help_panel.visible:
		help_saved_vis = [banner.visible, sub.visible]
		banner.visible = false
		sub.visible = false
		help_panel.visible = true
	else:
		help_panel.visible = false
		banner.visible = bool(help_saved_vis[0])
		sub.visible = bool(help_saved_vis[1])


func _on_toggle_music() -> void:
	if demo:
		return
	sfx.toggle_music()
	_toast("Music " + ("on" if sfx.music_on else "off"))


func _on_toggle_mute() -> void:
	if demo:
		return
	sfx.toggle_mute()
	_toast("Sound " + ("off" if sfx.muted else "on"))


func _on_toggle_pause() -> void:
	if demo:
		return
	if state != State.PLAY and state != State.DEAD and state != State.WAVE_CLEAR:
		return
	if help_panel != null and help_panel.visible:
		_on_toggle_help()
	if not get_tree().paused:
		saved_banner_txt = banner.text
		saved_banner_a = banner.modulate.a
		get_tree().paused = true
		banner.text = "PAUSED"
		banner.visible = true
		banner.modulate.a = 1.0
		sub.text = "ESC to resume     Q to Title     H help     M music     N mute"
		sub.visible = true
	else:
		get_tree().paused = false
		banner.text = saved_banner_txt
		banner.modulate.a = saved_banner_a
		sub.visible = false


func _unhandled_input(ev: InputEvent) -> void:
	if demo or get_tree().paused:
		return
	var on_menu: bool = state == State.TITLE or (state == State.GAME_OVER and state_t > 1.5)
	if not on_menu:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_C:
			_start_game(Mode.DAILY)
			return
		if ev.keycode == KEY_F:
			_start_game(Mode.PEACEFUL)
			return
	if ev.is_action_pressed("flap") or ev.is_action_pressed("ui_accept"):
		_start_game(mode if state == State.GAME_OVER else Mode.CLASSIC)


func _tick(raw_dt: float, inp: Array) -> void:
	if hitstop > 0.0:
		hitstop -= raw_dt
		return
	var dt: float = raw_dt * 0.32 if slowmo_t > 0.0 else raw_dt
	slowmo_t = maxf(slowmo_t - raw_dt, 0.0)
	var dash_in: bool = bool(inp[2]) if inp.size() > 2 else false
	state_t += raw_dt
	match state:
		State.TITLE:
			return
		State.GAME_OVER:
			return
		State.DEAD:
			if state_t > 1.6:
				if lives > 0:
					_spawn_player()
					state = State.PLAY
				else:
					state = State.GAME_OVER
					state_t = 0.0
					banner.modulate.a = 1.0
					var ref_best: int = daily_best if mode == Mode.DAILY else best
					var new_best: bool = score > ref_best and not demo
					_save_best()
					ref_best = daily_best if mode == Mode.DAILY else best
					banner.text = "NEW HIGH SCORE!" if new_best else "GAME OVER"
					banner.visible = true
					sub.text = "Score %d     Best %d\n\nSPACE: Retry     C: Daily     F: Peaceful" % [score, ref_best]
					sub.visible = true
	wave_t += dt
	if state == State.PLAY:
		player.step(dt, inp[0], inp[1], live_plats, HALF, dash_in)
		if player.pos.y < LAVA_Y:
			if mode == Mode.PEACEFUL:
				player.pos.y = LAVA_Y + 0.25
				player.vel.y = 10.5
				_burst(Vector2(player.pos.x, LAVA_Y + 0.3), Color(1.0, 0.78, 0.3), 16)
				sfx.play("flap", 0.2)
			else:
				_player_dies("lava")
	if mode == Mode.PEACEFUL:
		_eggs_tick(dt)
		_power_tick(dt)
		if state == State.PLAY:
			_collisions()
			_replenish_peaceful_eggs()
		_update_hud()
		return
	spawn_timer -= dt
	if not pending_spawns.is_empty() and spawn_timer <= 0.0:
		_spawn_enemy(pending_spawns.pop_front())
		spawn_timer = 1.1
	for e in enemies:
		var ai := _enemy_ai(e, dt)
		e.step(dt, ai[0], ai[1], live_plats, HALF)
		if e.pos.y < LAVA_Y and not (hand_grip and hand_target == e):
			e.pos.y = LAVA_Y + 0.2
			e.vel.y = 9.0
	_crumble_tick(dt)
	_eggs_tick(dt)
	_ptero_tick(dt)
	_hand_tick(dt)
	_power_tick(dt)
	if state == State.PLAY:
		_collisions()
	if state == State.PLAY and enemies.is_empty() and eggs.is_empty() and pending_spawns.is_empty():
		state = State.WAVE_CLEAR
		state_t = 0.0
		var bonus := 3000 if stats.get("_died_this_wave", false) == false else 0
		if bonus > 0:
			_add_score(bonus, player.pos + Vector2(0, 3), "SURVIVAL BONUS")
		_flash("WAVE %d CLEAR" % wave, 1.4)
	if state == State.WAVE_CLEAR:
		player.step(dt, inp[0], inp[1], live_plats, HALF, dash_in)
		if state_t > 2.0:
			stats["_died_this_wave"] = false
			_next_wave()
			state = State.PLAY
	_update_hud()


func _enemy_ai(e: Rider, dt: float) -> Array:
	if not e.active():
		return [0.0, false]
	e.ai_t -= dt
	if e.ai_t <= 0.0:
		e.ai_t = rng.randf_range(1.2, 3.0)
		if rng.randf() < 0.25:
			e.ai_dir = -e.ai_dir
		match e.kind:
			Rider.Kind.BOUNDER:
				e.ai_alt = rng.randf_range(3.5, 13.0)
			Rider.Kind.HUNTER:
				e.ai_alt = clampf(player.pos.y + rng.randf_range(0.5, 3.0), 3.0, 13.5)
				e.ai_dir = 1 if _wrap_dx(e.pos.x, player.pos.x) > 0.0 else -1
			Rider.Kind.SHADOW:
				e.ai_alt = clampf(player.pos.y + 1.6, 3.0, 13.8)
				e.ai_dir = 1 if _wrap_dx(e.pos.x, player.pos.x) > 0.0 else -1
	var target: float = e.ai_alt
	if e.pos.y < 2.5 and absf(e.pos.x) > 8.5:
		target = 6.0  # never coast into the lava
	# shadow lords climb when the player is close and level
	if e.kind == Rider.Kind.SHADOW and absf(_wrap_dx(e.pos.x, player.pos.x)) < 4.0 and player.lance_y() > e.lance_y() - 0.3:
		target = player.pos.y + 2.5
	e.ai_flap_t -= dt
	var flap := false
	if e.ai_flap_t <= 0.0 and (e.pos.y < target - 0.3 or e.vel.y < -7.0):
		flap = true
		e.ai_flap_t = e.ai_flap_cd * rng.randf_range(0.8, 1.6)
	if e.grounded and rng.randf() < 0.02:
		flap = true
	return [float(e.ai_dir), flap]


func _wrap_x(x: float) -> float:
	while x >= HALF:
		x -= HALF * 2.0
	while x < -HALF:
		x += HALF * 2.0
	return x


func _wrap_dx(a: float, b: float) -> float:
	var d := b - a
	if d > HALF:
		d -= HALF * 2.0
	elif d < -HALF:
		d += HALF * 2.0
	return d


func _overlap(a: Rider, b: Rider) -> bool:
	return absf(_wrap_dx(a.pos.x, b.pos.x)) < Rider.W * 0.95 and absf(a.pos.y - b.pos.y) < Rider.H * 0.85


func _collisions() -> void:
	if not player.active():
		return
	for e in enemies.duplicate():
		if not e.active() or not _overlap(player, e):
			continue
		var diff: float = player.lance_y() - e.lance_y() + (0.5 if long_lance > 0.0 else 0.0) + (0.20 if player.dashing() else 0.0)
		if player.invuln > 0.0 and diff <= JOUST_MARGIN:
			continue
		if diff > JOUST_MARGIN:
			_enemy_dies(e)
		elif diff < -JOUST_MARGIN:
			if shield > 0.0:
				shield = 0.0
				_bounce(player, e)
				player.invuln = 1.2
				_flash("SHIELD BROKEN", 0.6)
				continue
			_player_dies("lance")
			return
		elif player.bounce_cd <= 0.0:
			_bounce(player, e)
	# enemies bump each other so they don't stack
	for i in enemies.size():
		for j in range(i + 1, enemies.size()):
			var a := enemies[i]
			var b := enemies[j]
			if a.active() and b.active() and _overlap(a, b) and a.bounce_cd <= 0.0:
				_bounce(a, b)
	for g in eggs.duplicate():
		if absf(_wrap_dx(player.pos.x, g.pos.x)) < 0.95 and g.pos.y > player.pos.y - 0.4 and g.pos.y < player.pos.y + Rider.H:
			_collect_egg(g)


func _bounce(a: Rider, b: Rider) -> void:
	var dx := _wrap_dx(a.pos.x, b.pos.x)
	var s: float = -1.0 if dx > 0.0 else 1.0
	a.vel.x = s * maxf(absf(a.vel.x), 6.0)
	b.vel.x = -s * maxf(absf(b.vel.x), 6.0)
	a.vel.y += 2.0
	b.vel.y += 2.0
	a.bounce_cd = 0.25
	b.bounce_cd = 0.25
	if a == player or b == player:
		stats["bounces"] += 1
		sfx.play("clash")
		shake = maxf(shake, 0.15)
		var at := Vector2(_wrap_x(a.pos.x + dx * 0.5), (a.lance_y() + b.lance_y()) * 0.5)
		_burst(at, Color(1, 0.95, 0.7), 22)
		_ring(at)


func _enemy_dies(e: Rider) -> void:
	stats["kills"] += 1
	sfx.play("kill")
	_add_score(KILL_SCORE[e.kind], e.pos + Vector2(0, 2.2))
	var tier: int = 0 if e.kind == Rider.Kind.BOUNDER else (1 if e.kind == Rider.Kind.HUNTER else 2)
	_drop_egg(e.pos + Vector2(0, 1.0), Vector2(e.vel.x * 0.5, 3.0), tier)
	_spawn_fleeing_mount(e.pos, -1 if _wrap_dx(e.pos.x, player.pos.x) > 0.0 else 1)
	if rng.randf() < 0.14:
		_drop_power(e.pos + Vector2(0, 2.0), "shield" if rng.randf() < 0.5 else "lance")
	_burst(e.pos + Vector2(0, 1.2), Rider.COLORS[e.kind][0], 34)
	_burst(e.pos + Vector2(0, 1.2), Color(1, 0.95, 0.75), 18)
	_ring(e.pos + Vector2(0, 1.2))
	_feathers(e.pos + Vector2(0, 1.2), Rider.COLORS[e.kind][0])
	enemies.erase(e)
	e.queue_free()
	hitstop = 0.07
	if enemies.is_empty() and pending_spawns.is_empty():
		slowmo_t = 0.22
	shake = maxf(shake, 0.3)
	player.vel.y = maxf(player.vel.y, 3.0)


func _player_dies(why: String) -> void:
	if state != State.PLAY:
		return
	var death_pos := player.pos
	var in_lava: bool = why == "lava" or why == "hand"
	shield = 0.0
	long_lance = 0.0
	stats["deaths"] += 1
	stats["d_" + why] = stats.get("d_" + why, 0) + 1
	sfx.play("sizzle" if in_lava else "death")
	stats["_died_this_wave"] = true
	lives -= 1
	_burst(death_pos + Vector2(0, 1.2), Color(0.5, 0.65, 1.0), 36)
	if in_lava:
		_burst(Vector2(death_pos.x, maxf(death_pos.y, LAVA_Y + 0.2)), Color(1, 0.5, 0.1), 28)
	player.visible = false
	player.pos = Vector2(0, -50)
	state = State.DEAD
	state_t = 0.0
	hitstop = 0.12
	shake = 0.5


func _add_score(n: int, at: Vector2, label := "") -> void:
	score += n
	if score >= next_life:
		lives += 1
		next_life += 20000
		sfx.play("life", 0.0)
		label = "EXTRA LIFE"
	_popup(at, ("+%d" % n) + ("\n" + label if label != "" else ""))


# ===================================================================== eggs

func _drop_egg(p: Vector2, v: Vector2, tier: int) -> void:
	var g := Egg.new()
	add_child(g)
	g.setup(p, v, tier)
	eggs.append(g)


func _collect_egg(g: Egg) -> void:
	stats["eggs"] += 1
	sfx.play("egg", 0.03 * float(egg_streak))
	var bonus: int = EGG_SCORE[mini(egg_streak, EGG_SCORE.size() - 1)]
	egg_streak += 1
	var mid_air: bool = not g.grounded
	if mid_air:
		bonus += 500
	_add_score(bonus, g.pos + Vector2(0, 1.5), "CATCH!" if mid_air else "")
	_burst(g.pos + Vector2(0, 0.4), Color(1, 0.85, 0.3), 14)
	eggs.erase(g)
	g.queue_free()
	if mode == Mode.PEACEFUL:
		peaceful_eggs += 1
		if peaceful_eggs % 10 == 0:
			var nti: int = (peaceful_eggs / 10) % THEMES.size()
			_apply_theme(nti)
			_flash(THEMES[nti]["name"], 1.4)


func _eggs_tick(dt: float) -> void:
	for g in eggs.duplicate():
		g.step(dt, live_plats, HALF)
		if g.pos.y < LAVA_Y:
			eggs.erase(g)
			g.queue_free()
			continue
		if mode == Mode.PEACEFUL:
			# eggs never hatch into enemies in Peaceful Flight; keep pulse gentle
			g.t = minf(g.t, 4.0)
			continue
		if g.t >= g.hatch_time():
			stats["hatched"] += 1
			sfx.play("hatch")
			var k: int = [Rider.Kind.HUNTER, Rider.Kind.SHADOW, Rider.Kind.SHADOW][clampi(g.tier, 0, 2)]
			var e := Rider.new()
			add_child(e)
			e.setup(k, g.pos, 1 if rng.randf() < 0.5 else -1)
			e.spawn_t = 0.9
			e.ai_dir = e.facing
			_apply_wave_scaling(e)
			e.ai_alt = rng.randf_range(4.0, 12.5)
			enemies.append(e)
			_burst(g.pos + Vector2(0, 0.5), Color(1, 0.9, 0.5), 18)
			eggs.erase(g)
			g.queue_free()


# =========================================================== crumbling ledges

func _crumble_tick(dt: float) -> void:
	var active: bool = wave >= 6 and state != State.TITLE
	var changed := false
	for i in CRUMBLE:
		if i >= plat_nodes.size():
			continue
		var r: Rect2 = PLATS[i]
		var n: Node3D = plat_nodes[i]
		if plat_on[i]:
			var stood := false
			if active:
				for rd in [player] + enemies:
					if rd != null and rd.active() and rd.grounded and absf(rd.pos.y - r.end.y) < 0.05 and rd.pos.x > r.position.x - 0.3 and rd.pos.x < r.end.x + 0.3:
						stood = true
			plat_stand[i] = plat_stand[i] + dt if stood else maxf(plat_stand[i] - dt * 0.5, 0.0)
			# shake as a warning
			var k: float = plat_stand[i] / 1.3
			n.position.x = r.get_center().x + (sin(Time.get_ticks_msec() * 0.06) * 0.06 * k if k > 0.2 else 0.0)
			if plat_stand[i] > 1.3:
				plat_on[i] = false
				plat_down[i] = 0.0
				changed = true
				stats["crumbles"] = stats.get("crumbles", 0) + 1
				_burst(Vector2(r.get_center().x, r.end.y - 0.5), Color(0.75, 0.55, 0.4), 30)
				sfx.play("clash", 0.2)
		else:
			plat_down[i] += dt
			n.position.y = r.end.y - plat_down[i] * plat_down[i] * 6.0
			n.visible = plat_down[i] < 1.5
			if plat_down[i] > 7.0:
				plat_on[i] = true
				plat_stand[i] = 0.0
				n.position = Vector3(r.get_center().x, r.end.y, 0)
				n.visible = true
				n.scale = Vector3.ONE * 0.01
				create_tween().tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK)
				changed = true
	if changed:
		live_plats.clear()
		for i in PLATS.size():
			if plat_on[i]:
				live_plats.append(PLATS[i])


# ================================================================= power-ups

func _drop_power(p: Vector2, kind: String) -> void:
	var n := Node3D.new()
	add_child(n)
	var mi := MeshInstance3D.new()
	var mesh: Mesh
	var col: Color
	if kind == "shield":
		var sm := SphereMesh.new()
		sm.radius = 0.38
		sm.height = 0.76
		mesh = sm
		col = Color(0.3, 0.85, 1.0)
	else:
		var pm := PrismMesh.new()
		pm.size = Vector3(0.5, 0.75, 0.25)
		mesh = pm
		col = Color(1.0, 0.8, 0.2)
	mi.mesh = mesh
	mi.material_override = _flat(col, 2.2)
	n.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "SHIELD" if kind == "shield" else "LONG LANCE"
	lbl.font_size = 40
	lbl.pixel_size = 0.008
	lbl.outline_size = 10
	lbl.position.y = 0.75
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	n.add_child(lbl)
	n.position = Vector3(p.x, p.y, 0.4)
	powerups.append([n, p, kind, 0.0])


func _power_tick(dt: float) -> void:
	shield = maxf(shield - dt, 0.0) if shield < 900.0 else shield
	long_lance = maxf(long_lance - dt, 0.0)
	for pu in powerups.duplicate():
		pu[3] += dt
		var n: Node3D = pu[0]
		var p: Vector2 = pu[1]
		n.position.y = p.y + sin(pu[3] * 3.0) * 0.25
		n.rotation.y += dt * 2.0
		var gone: bool = pu[3] > 9.0
		if state == State.PLAY and player.active() and absf(_wrap_dx(player.pos.x, p.x)) < 1.0 and absf(player.pos.y + 0.9 - p.y) < 1.4:
			if pu[2] == "shield":
				shield = 999.0   # lasts until hit
				_flash("SHIELD", 0.6)
			else:
				long_lance = 12.0
				_flash("LONG LANCE", 0.6)
			sfx.play("life", 0.0)
			gone = true
		elif pu[3] > 6.5:
			n.visible = fmod(pu[3], 0.25) < 0.15
		if gone:
			n.queue_free()
			powerups.erase(pu)
	if player != null:
		player.shield_on = shield > 0.0
		player.long_lance_on = long_lance > 0.0


# ================================================================ lava hand

const HAND_ZONE_Y := 2.6     # riders below this, outside the base bridge, can be grabbed


func _hand_tick(dt: float) -> void:
	if state != State.PLAY or wave < 3:
		if hand != null:
			hand.visible = false
		return
	if hand == null:
		hand = _build_hand()
	hand_cd -= dt
	if hand_target == null:
		hand.position.y = move_toward(hand.position.y, LAVA_Y - 3.0, 6.0 * dt)
		if hand.position.y <= LAVA_Y - 2.9:
			hand.visible = false
		if hand_cd > 0.0:
			return
		# pick the lowest rider over open lava
		var cands: Array[Rider] = []
		if player.active():
			cands.append(player)
		cands.append_array(enemies)
		for r in cands:
			if r.active() and r.pos.y < HAND_ZONE_Y and absf(r.pos.x) > 9.4:
				hand_target = r
				hand_x = r.pos.x
				hand_t = 0.0
				hand_grabs += 1
				break
		return
	if not hand.visible:
		_burst(Vector2(hand_target.pos.x, LAVA_Y + 0.2), Color(1.0, 0.5, 0.1), 24)
		sfx.play("sizzle")
	hand_t += dt
	hand.visible = true
	var r := hand_target
	if not is_instance_valid(r) or not r.active() or (r == player and state != State.PLAY):
		hand_target = null
		hand_grip = false
		hand_cd = 3.0
		return
	hand_x = _wrap_x(hand_x + _wrap_dx(hand_x, r.pos.x) * (1.0 - exp(-dt * 4.0)))
	# fingers open while reaching, clench when gripping
	var curl: float = 1.5 if hand_grip else 0.35 + 0.25 * sin(hand_t * 10.0)
	for k in hand_knuckles:
		k.rotation.x = lerpf(k.rotation.x, curl, 1.0 - exp(-dt * 12.0))
	var reach: float = minf(hand_t * 3.2, 1.0)
	hand.position = Vector3(hand_x, LAVA_Y - 2.8 + reach * 3.4, 0.2)
	var hand_top: float = hand.position.y + 2.9
	if not hand_grip and absf(_wrap_dx(hand_x, r.pos.x)) < 1.1 and r.pos.y < hand_top and r.pos.y > hand_top - 2.4:
		hand_grip = true
	if hand_grip:
		# grabbed: dragged down; flapping hard enough breaks free
		r.vel.y = minf(r.vel.y, 1.5) - 9.0 * dt
		r.vel.x *= 0.9
		hand.position.y = minf(hand.position.y, r.pos.y - 2.4)
		if r.flapped and rng.randf() < 0.18:
			hand_grip = false
			hand_target = null
			hand_cd = 3.0
			return
		if r.pos.y < LAVA_Y:
			if r == player:
				_player_dies("hand")
			else:
				enemies.erase(r)
				_burst(r.pos + Vector2(0, 1.0), Color(1, 0.5, 0.1), 30)
				sfx.play("sizzle")
				r.queue_free()
			hand_target = null
			hand_grip = false
			hand_cd = 4.0
			return
	elif hand_t > 2.4 or r.pos.y > HAND_ZONE_Y + 1.0:
		hand_target = null
		hand_cd = 3.5


func _build_hand() -> Node3D:
	# a molten rock troll hand: tapered forearm, palm, curled fingers + thumb, glowing seams
	var h := Node3D.new()
	add_child(h)
	var rock := ShaderMaterial.new()
	rock.shader = load("res://shaders/magma_rock.gdshader")
	var arm := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.7
	cm.height = 3.2
	cm.radial_segments = 10
	arm.mesh = cm
	arm.material_override = rock
	h.add_child(arm)
	var palm := MeshInstance3D.new()
	var pm := SphereMesh.new()
	pm.radius = 0.55
	pm.height = 0.9
	palm.mesh = pm
	palm.material_override = rock
	palm.position = Vector3(0, 1.75, 0)
	palm.scale = Vector3(1.15, 1.0, 0.7)
	h.add_child(palm)
	for i in 4:
		var a: float = lerpf(-0.55, 0.55, float(i) / 3.0)
		var base := Node3D.new()
		base.position = Vector3(sin(a) * 0.5, 2.05, 0)
		base.rotation.z = -a * 0.7
		h.add_child(base)
		var seg1 := MeshInstance3D.new()
		var c1 := CapsuleMesh.new()
		c1.radius = 0.13
		c1.height = 0.62
		seg1.mesh = c1
		seg1.material_override = rock
		seg1.position.y = 0.28
		base.add_child(seg1)
		var knuckle := Node3D.new()
		knuckle.position.y = 0.55
		knuckle.rotation.x = 0.5
		knuckle.name = "k%d" % i
		base.add_child(knuckle)
		hand_knuckles.append(knuckle)
		var seg2 := MeshInstance3D.new()
		var c2 := CapsuleMesh.new()
		c2.radius = 0.11
		c2.height = 0.55
		seg2.mesh = c2
		seg2.material_override = rock
		seg2.position.y = 0.24
		knuckle.add_child(seg2)
		var claw := MeshInstance3D.new()
		var cc := CylinderMesh.new()
		cc.top_radius = 0.0
		cc.bottom_radius = 0.09
		cc.height = 0.22
		claw.mesh = cc
		claw.material_override = _flat(Color(1.0, 0.75, 0.3), 2.5)
		claw.position.y = 0.55
		knuckle.add_child(claw)
	var thumb := MeshInstance3D.new()
	var tc := CapsuleMesh.new()
	tc.radius = 0.14
	tc.height = 0.7
	thumb.mesh = tc
	thumb.material_override = rock
	thumb.position = Vector3(-0.6, 1.7, 0.15)
	thumb.rotation.z = 1.0
	h.add_child(thumb)
	ModelFit.outline(h, Color(0.08, 0.02, 0.02), 0.04)
	h.position = Vector3(0, LAVA_Y - 3.0, 0.2)
	h.visible = false
	return h


# =============================================================== pterodactyl

func _ptero_tick(dt: float) -> void:
	if state != State.PLAY:
		return
	if not ptero_alive:
		if wave_t > ptero_next_t and (not enemies.is_empty() or not eggs.is_empty()):
			_spawn_ptero()
		return
	# swoop toward the player's lance height (ptero_pos is centered on the pterodactyl body/beak)
	var dy: float = player.lance_y() - ptero_pos.y
	ptero_vel.y = move_toward(ptero_vel.y, clampf(dy * 1.5, -6.0, 6.0), 10.0 * dt)
	ptero_pos += ptero_vel * dt
	ptero_pos.x = _wrap_x(ptero_pos.x)
	ptero_pos.y = clampf(ptero_pos.y, 1.8, 15.0)
	ptero.position = Vector3(ptero_pos.x, ptero_pos.y, 0)
	ptero.rotation.y = 0.0 if ptero_vel.x > 0.0 else PI
	var body := ptero.get_child(0) as Node3D
	var flap_f: float = sin(wave_t * 10.0)
	body.position.y = flap_f * 0.14
	body.rotation.z = cos(wave_t * 10.0) * 0.12
	body.scale = Vector3(1.0, 1.0 + flap_f * 0.18, 1.0 - flap_f * 0.08)
	if not player.active() or player.invuln > 0.0:
		return
	var dx := _wrap_dx(player.pos.x, ptero_pos.x)
	var reach: float = 2.1 if long_lance > 0.0 else 1.6
	var beak_tol: float = 0.65 if long_lance > 0.0 else 0.50
	if absf(dx) < reach and absf(ptero_pos.y - player.lance_y()) < 1.05:
		# only a lance straight into the open beak works: facing it, at beak height
		var facing_it: bool = (dx > 0.0) == (player.facing > 0) and (ptero_vel.x > 0.0) != (player.facing > 0)
		if facing_it and absf(ptero_pos.y - player.lance_y()) < beak_tol:
			stats["ptero"] += 1
			sfx.play("kill")
			_add_score(1000, ptero_pos + Vector2(0, 1.2), "PTERODACTYL!")
			_burst(ptero_pos, Color(1, 0.4, 0.2), 40)
			_ring(ptero_pos)
			hitstop = 0.15
			slowmo_t = 0.22
			ptero_next_t = wave_t + 25.0
			_kill_ptero()
		elif shield > 0.0:
			shield = 0.0
			player.invuln = 1.2
			player.vel.x = (-1.0 if dx > 0.0 else 1.0) * 7.5
			player.vel.y = 4.0
			sfx.play("clash")
			_burst(player.pos + Vector2(0, 1.2), Color(0.3, 0.85, 1.0), 24)
			_flash("SHIELD BROKEN", 0.6)
		else:
			_player_dies("ptero")


func _spawn_ptero() -> void:
	ptero_alive = true
	var side: float = -1.0 if rng.randf() < 0.5 else 1.0
	ptero_pos = Vector2(-side * (HALF - 0.1), rng.randf_range(5.0, 13.0))
	ptero_vel = Vector2(side * 10.5, 0.0)
	ptero = Node3D.new()
	add_child(ptero)
	var path := "res://assets/models/pterodactyl.glb"
	var body := Node3D.new()
	ptero.add_child(body)
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		body.add_child(m)
		ModelFit.fit(m, 1.8, PI * 0.5)
		m.position.y -= 0.9
		ModelFit.matte(m)
		ModelFit.outline(m, Color(0.15, 0.02, 0.02), 0.025)
	else:
		var b := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(2.6, 0.6, 3.6)
		b.mesh = pm
		b.material_override = _flat(Color(0.9, 0.35, 0.15))
		b.rotation.x = PI * 0.5
		body.add_child(b)
	_flash("BEWARE THE PTERODACTYL", 1.2)
	sfx.play("screech", 0.0)


func _kill_ptero() -> void:
	if ptero != null:
		ptero.queue_free()
		ptero = null
	ptero_alive = false


func _spawn_fleeing_mount(p: Vector2, dir: int) -> void:
	if sim_seconds > 0.0:
		return
	var path := "res://assets/models/buzzard_riderless.glb"
	if not ResourceLoader.exists(path):
		return
	var root := Node3D.new()
	root.position = Vector3(p.x, p.y, -0.35)
	root.rotation.y = 0.0 if dir > 0 else PI
	add_child(root)
	var m: Node3D = (load(path) as PackedScene).instantiate()
	root.add_child(m)
	ModelFit.fit(m, Rider.H * 0.9, PI * 0.5)
	ModelFit.matte(m)
	ModelFit.outline(m, Color(0.14, 0.06, 0.04), 0.03)
	var ws: Array[Node3D] = []
	var wing_path := "res://assets/models/wing_feathered.glb"
	if ResourceLoader.exists(wing_path):
		var src: Node3D = (load(wing_path) as PackedScene).instantiate()
		var wmat := _flat(Color(0.46, 0.30, 0.19))
		for idx in 2:
			var tag: String = "Right" if idx == 0 else "Left"
			var side: float = 1.0 if idx == 0 else -1.0
			var sh := Node3D.new()
			sh.position = Vector3(-0.05, 0.85, 0.18 * side)
			sh.scale = Vector3.ONE * 0.82
			root.add_child(sh)
			var wnode := src.find_child("Wing" + tag, true, false) as Node3D
			if wnode != null:
				ModelFit.detach(wnode)
				sh.add_child(wnode)
				wnode.position = Vector3.ZERO
				for mi in wnode.find_children("*", "MeshInstance3D", true, false):
					(mi as MeshInstance3D).material_override = wmat
			ModelFit.outline(sh, Color(0.14, 0.06, 0.04), 0.025)
			ws.append(sh)
		src.free()
	else:
		var feather := SphereMesh.new()
		feather.radius = 0.45
		feather.height = 0.9
		for side in [1.0, -1.0]:
			var sh := Node3D.new()
			sh.position = Vector3(-0.05, 0.85, 0.22 * side)
			root.add_child(sh)
			var w := MeshInstance3D.new()
			w.mesh = feather
			w.scale = Vector3(0.7, 0.1, 0.75)
			w.position = Vector3(-0.06, 0.0, 0.34 * side)
			w.material_override = _flat(Color(0.46, 0.30, 0.19))
			sh.add_child(w)
			ws.append(sh)
	fleeing_mounts.append([root, ws, p, float(dir) * 11.5, 0.0])


# ================================================================== visuals

func _update_visuals(raw_dt: float) -> void:
	var dt: float = raw_dt * 0.32 if slowmo_t > 0.0 else raw_dt
	if player != null:
		player.sync_visual(dt)
		if player.flapped and player.visible:
			sfx.play("flap", 0.12)
			_puff(player.pos + Vector2(-player.facing * 0.2, 0.6))
		if player.dashed and player.visible:
			sfx.play("dash", 0.06)
			_burst(player.pos + Vector2(-player.facing * 0.6, 1.1), Color(0.55, 0.92, 1.0), 18)
	for e in enemies:
		e.sync_visual(dt)
	for fm in fleeing_mounts.duplicate():
		fm[4] += dt
		var n: Node3D = fm[0]
		var ws: Array = fm[1]
		var fp: Vector2 = fm[2]
		fp.x += float(fm[3]) * dt
		fp.y += 2.2 * dt
		fm[2] = fp
		n.position = Vector3(fp.x, fp.y + sin(float(fm[4]) * 18.0) * 0.12, -0.35)
		var wa: float = 0.35 + 1.1 * sin(float(fm[4]) * 22.0)
		for i in ws.size():
			(ws[i] as Node3D).rotation.x = (1.0 if i == 0 else -1.0) * wa
		if absf(fp.x) > HALF + 3.5 or fp.y > 20.0:
			n.queue_free()
			fleeing_mounts.erase(fm)
	shake = maxf(shake - dt * 1.6, 0.0)
	if shake > 0.0:
		var s: float = shake * shake
		cam.position = cam_base + Vector3(vis_rng.randf_range(-1, 1) * s, vis_rng.randf_range(-1, 1) * s, 0)
	else:
		cam.position = cam_base


func _burst(at: Vector2, c: Color, n: int) -> void:
	if sim_seconds > 0.0:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = n
	p.lifetime = 0.9
	p.explosiveness = 0.95
	p.spread = 180.0
	p.direction = Vector3(0, 1, 0)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 8.0
	p.gravity = Vector3(0, -12, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.45, 0.45)
	q.material = _soft_mat(c, 1.6)
	p.mesh = q
	p.color_ramp = _fade_ramp()
	p.scale_amount_curve = null
	p.position = Vector3(at.x, at.y, 0.6)
	add_child(p)
	get_tree().create_timer(1.5, false).timeout.connect(p.queue_free)


func _puff(at: Vector2) -> void:
	if sim_seconds > 0.0:
		return
	if _puff_quad == null:
		_puff_quad = QuadMesh.new()
		_puff_quad.size = Vector2(0.35, 0.35)
		_puff_quad.material = _soft_mat(Color(1, 1, 1), 0.5)
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 5
	p.lifetime = 0.45
	p.explosiveness = 1.0
	p.direction = Vector3(0, -1, 0)
	p.spread = 50.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 3.0
	p.gravity = Vector3.ZERO
	p.mesh = _puff_quad
	p.color_ramp = _fade_ramp()
	p.position = Vector3(at.x, at.y, 0.3)
	add_child(p)
	get_tree().create_timer(0.8, false).timeout.connect(p.queue_free)


func _feathers(at: Vector2, c: Color) -> void:
	if sim_seconds > 0.0:
		return
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 16
	p.lifetime = 2.2
	p.explosiveness = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -2.5, 0)
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.angle_max = 360.0
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.5)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = _soft()
	m.albedo_color = c.lightened(0.15)
	m.vertex_color_use_as_albedo = true
	q.material = m
	p.mesh = q
	p.color_ramp = _fade_ramp()
	p.position = Vector3(at.x, at.y, 0.8)
	add_child(p)
	get_tree().create_timer(2.6, false).timeout.connect(p.queue_free)


func _ring(at: Vector2) -> void:
	if sim_seconds > 0.0:
		return
	if _ring_quad == null:
		_ring_quad = QuadMesh.new()
		_ring_quad.size = Vector2(1, 1)
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0), Color(1, 0.95, 0.8, 1), Color(1, 1, 1, 0)])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_ring_mat_proto = StandardMaterial3D.new()
		_ring_mat_proto.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_ring_mat_proto.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ring_mat_proto.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_ring_mat_proto.albedo_texture = t
	var q := MeshInstance3D.new()
	q.mesh = _ring_quad
	var m := _ring_mat_proto.duplicate() as StandardMaterial3D
	q.material_override = m
	q.position = Vector3(at.x, at.y, 1.2)
	add_child(q)
	var tw := create_tween()
	tw.tween_property(q, "scale", Vector3.ONE * 5.0, 0.35).from(Vector3.ONE * 0.5)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.35)
	tw.tween_callback(q.queue_free)


func _popup(at: Vector2, txt: String) -> void:
	if sim_seconds > 0.0:
		return
	var l := Label3D.new()
	l.text = txt
	l.font_size = 72
	l.pixel_size = 0.008
	l.outline_size = 16
	l.modulate = Color(1, 0.95, 0.6)
	l.outline_modulate = Color(0.3, 0.1, 0.15)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	var n_live: int = popups.get_child_count()
	l.position = Vector3(at.x, at.y + 0.9 * float(n_live % 3), 1.0)
	popups.add_child(l)
	var tw := create_tween()
	tw.tween_property(l, "position:y", l.position.y + 1.6, 0.9)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.tween_callback(l.queue_free)


# ====================================================== autopilot + playtest

func _autopilot() -> Array:
	# demo bot: attack enemies from ABOVE (get higher, then dive across), grab eggs, avoid lava
	if player == null or not player.active():
		return [0.0, false]
	var target := Vector2(0, 9)
	var best := 1e9
	var tgt_enemy: Rider = null
	for g in eggs:
		var d: float = absf(_wrap_dx(player.pos.x, g.pos.x)) + absf(g.pos.y - player.pos.y)
		if d < best:
			best = d
			target = g.pos
	for pu in powerups:
		var pp: Vector2 = pu[1]
		var d: float = (absf(_wrap_dx(player.pos.x, pp.x)) + absf(pp.y - player.pos.y)) * 0.6
		if d < best:
			best = d
			target = pp - Vector2(0, 0.9)
	for e in enemies:
		if not e.active():
			continue
		var d: float = absf(_wrap_dx(player.pos.x, e.pos.x)) + absf(e.pos.y - player.pos.y) * 0.5
		if d < best:
			best = d
			target = e.pos
			tgt_enemy = e
	var dx := _wrap_dx(player.pos.x, target.x)
	var want_y: float = target.y + 0.4
	var ix: float = signf(dx) if absf(dx) > 0.4 else 0.0
	if tgt_enemy != null:
		var above: float = player.lance_y() - tgt_enemy.lance_y()
		if above < 0.9:
			# not high enough: climb, and back off if close so we don't trade lances level
			want_y = tgt_enemy.pos.y + 2.2
			if absf(dx) < 3.0:
				ix = -signf(dx)
		else:
			want_y = tgt_enemy.pos.y + 1.0
	if player.pos.y < 2.2 and absf(player.pos.x) > 8.0:
		want_y = 7.0
	var flap: bool = player.pos.y < want_y and player.vel.y < 2.5 and player.flap_cd <= 0.0
	var dash := false
	if tgt_enemy != null and player.dash_cd <= 0.0:
		var above_d: float = player.lance_y() - tgt_enemy.lance_y()
		if above_d > 0.35 and absf(dx) > 2.0 and absf(dx) < 5.0 and signf(dx) == float(player.facing):
			dash = true
	return [ix, flap, dash]


func _run_sim() -> void:
	demo = true
	_start_game()
	var dt := 1.0 / 60.0
	var t := 0.0
	var next_print := 30.0
	while t < sim_seconds:
		_tick(dt, _autopilot())
		t += dt
		if state == State.GAME_OVER:
			print("SIM game over at t=%.0f; restarting" % t)
			_start_game()
		max_wave_seen = maxi(max_wave_seen, wave)
		if t >= next_print:
			next_print += 30.0
			print("SIM t=%4.0f wave=%d score=%d lives=%d enemies=%d eggs=%d %s" % [t, wave, score, lives, enemies.size(), eggs.size(), str(stats)])
	print("SIM DONE ", stats)
	print("SIM max wave reached: ", max_wave_seen, " hand grabs attempted: ", hand_grabs)
