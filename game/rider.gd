class_name Rider
extends Node3D
## A mounted knight (player or enemy). Owns its own deterministic 2D physics in the
## arena plane (x right, y up, feet at pos); the 3D node just mirrors it.

enum Kind { PLAYER, BOUNDER, HUNTER, SHADOW }

const W := 1.1
const H := 1.7
const LANCE := 1.35
const G := 24.0
const FLAP := 7.6
const VY_MAX := 9.0
const FALL_MAX := -14.0
const AIR_ACC := 7.0
const GROUND_ACC := 20.0
const GROUND_FRIC := 14.0
const AIR_DRAG := 0.8
const CEIL := 16.4
const DASH_V := 15.5
const DASH_DUR := 0.18
const DASH_CD := 2.2

const COLORS := {
	Kind.PLAYER: [Color(0.30, 0.55, 1.00), Color(0.92, 0.94, 1.00), Color(0.10, 0.45, 1.00)],
	Kind.BOUNDER: [Color(0.85, 0.22, 0.12), Color(0.35, 0.30, 0.30), Color(1.00, 0.75, 0.15)],
	Kind.HUNTER: [Color(0.25, 0.27, 0.32), Color(0.80, 0.82, 0.86), Color(0.95, 0.95, 0.30)],
	Kind.SHADOW: [Color(0.16, 0.11, 0.22), Color(0.12, 0.10, 0.16), Color(0.65, 0.25, 1.00)],
}
const WING_COLORS := {
	Kind.PLAYER: Color(0.42, 0.56, 0.80),
	Kind.BOUNDER: Color(0.46, 0.30, 0.19),
	Kind.HUNTER: Color(0.36, 0.39, 0.45),
	Kind.SHADOW: Color(0.22, 0.13, 0.32),
}
## yaw (rad) that turns each generated model to face +X (measured from tools/sides.py renders)
const MODEL_YAW := {
	Kind.PLAYER: 0.0, Kind.BOUNDER: 0.0, Kind.HUNTER: 0.0, Kind.SHADOW: 0.0,
}
const MODELS := {
	Kind.PLAYER: "player_ostrich", Kind.BOUNDER: "enemy_bounder",
	Kind.HUNTER: "enemy_hunter", Kind.SHADOW: "enemy_shadowlord",
}

var kind: int = Kind.PLAYER
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var facing: int = 1
var grounded := false
var spawn_t := 0.0
var invuln := 0.0
var flap_cd := 0.0
var flap_anim := 0.0
var bounce_cd := 0.0
var max_vx := 9.0
var run_phase := 0.0
var flapped := false
var dash_t := 0.0
var dash_cd := 0.0
var dashed := false
# AI state (enemies)
var ai_dir: int = 1
var ai_alt := 8.0
var ai_t := 0.0
var ai_flap_cd := 0.2
var ai_flap_t := 0.0

var vis: Node3D
var wings: Array[Node3D] = []
var wrists: Array[Node3D] = []
var legs: Array[Node3D] = []
var turn := 0.0
var model: Node3D
var shield_on := false
var long_lance_on := false
var halo_fx: MeshInstance3D
var shield_fx: MeshInstance3D
var lance_fx: Node3D
var clock := 0.0


func setup(k: int, p: Vector2, f: int = 1) -> void:
	kind = k
	pos = p
	facing = f
	turn = 0.0 if f > 0 else -PI
	match k:
		Kind.PLAYER:
			max_vx = 9.0
		Kind.BOUNDER:
			max_vx = 5.0
			ai_flap_cd = 0.26
		Kind.HUNTER:
			max_vx = 7.0
			ai_flap_cd = 0.18
		Kind.SHADOW:
			max_vx = 8.5
			ai_flap_cd = 0.13
	_build_visual()
	sync_visual(0.0)


func lance_y() -> float:
	return pos.y + LANCE


func active() -> bool:
	return spawn_t <= 0.0


func dashing() -> bool:
	return dash_t > 0.0


func step(dt: float, ix: float, flap: bool, plats: Array[Rect2], half: float, dash := false) -> void:
	flap_cd -= dt
	bounce_cd -= dt
	invuln -= dt
	dash_cd = maxf(dash_cd - dt, 0.0)
	dash_t = maxf(dash_t - dt, 0.0)
	flapped = false
	dashed = false
	flap_anim = maxf(flap_anim - dt * 3.5, 0.0)
	if spawn_t > 0.0:
		spawn_t -= dt
		return
	if ix != 0.0:
		facing = 1 if ix > 0.0 else -1
	if dash and dash_cd <= 0.0 and kind == Kind.PLAYER:
		dash_t = DASH_DUR
		dash_cd = DASH_CD
		dashed = true
		flap_anim = maxf(flap_anim, 0.75)
		vel.x = float(facing) * DASH_V
		vel.y = maxf(vel.y, 0.8)
	var acc: float = GROUND_ACC if grounded else AIR_ACC
	if dash_t > 0.0:
		vel.x = float(facing) * DASH_V
	elif ix != 0.0:
		vel.x += ix * acc * dt
	elif grounded:
		vel.x = move_toward(vel.x, 0.0, GROUND_FRIC * dt)
	else:
		vel.x = move_toward(vel.x, 0.0, AIR_DRAG * dt)
	var cap_vx: float = DASH_V if dash_t > 0.0 else max_vx
	vel.x = clampf(vel.x, -cap_vx, cap_vx)
	if flap and flap_cd <= 0.0:
		vel.y = clampf(vel.y + FLAP, FLAP * 0.55, VY_MAX)
		flap_cd = 0.11
		flap_anim = 1.0
		flapped = true
		if not grounded and ix != 0.0 and dash_t <= 0.0:
			vel.x = clampf(vel.x + ix * 1.2, -max_vx, max_vx)
	var grav: float = G * 0.25 if dash_t > 0.0 else G
	vel.y = maxf(vel.y - grav * dt, FALL_MAX)
	_move(dt, plats, half)
	if grounded and absf(vel.x) > 0.1:
		run_phase += absf(vel.x) * dt * 0.9


func _hits(r: Rect2) -> bool:
	return pos.x + W * 0.5 > r.position.x and pos.x - W * 0.5 < r.end.x \
		and pos.y + H > r.position.y and pos.y < r.end.y


func _move(dt: float, plats: Array[Rect2], half: float) -> void:
	pos.x += vel.x * dt
	for r: Rect2 in plats:
		if _hits(r):
			if vel.x > 0.0:
				pos.x = r.position.x - W * 0.5 - 0.001
			else:
				pos.x = r.end.x + W * 0.5 + 0.001
			vel.x = -vel.x * 0.5
	if pos.x >= half:
		pos.x -= half * 2.0
	elif pos.x < -half:
		pos.x += half * 2.0
	grounded = false
	pos.y += vel.y * dt
	for r: Rect2 in plats:
		if _hits(r):
			if vel.y <= 0.0:
				pos.y = r.end.y
				vel.y = 0.0
				grounded = true
			else:
				pos.y = r.position.y - H - 0.001
				vel.y = -absf(vel.y) * 0.3
	if pos.y + H > CEIL:
		pos.y = CEIL - H
		vel.y = minf(vel.y, -1.0)


# ---------------------------------------------------------------- visuals

func sync_visual(dt: float) -> void:
	clock += dt
	position = Vector3(pos.x, pos.y, 0.0)
	var target: float = 0.0 if facing > 0 else -PI
	if dt <= 0.0:
		turn = target
	else:
		turn = lerpf(turn, target, 1.0 - exp(-dt * 12.0))
	vis.rotation.y = turn
	# materialise on spawn, blink while invulnerable
	var s: float = clampf(1.0 - spawn_t / 1.2, 0.05, 1.0)
	vis.scale = Vector3.ONE * s
	visible = invuln <= 0.0 or fmod(clock, 0.2) < 0.13
	# wings: big beat on a flap, glide-up while falling, folded on the ground
	var wa: float
	if grounded:
		wa = 0.1
	else:
		wa = 0.35 + 1.25 * sin(flap_anim * PI) + (0.35 if vel.y < -2.0 else 0.0)
	if halo_fx != null:
		halo_fx.scale = Vector3.ONE * s
	if shield_fx != null:
		shield_fx.visible = shield_on
		shield_fx.scale = Vector3.ONE * s
		shield_fx.rotation.y += dt * 1.5
	if lance_fx != null:
		lance_fx.visible = long_lance_on or dash_t > 0.0
		var pulse: float = 1.0 + 0.12 * sin(clock * 14.0)
		lance_fx.scale = Vector3(0.75 if not long_lance_on else 1.0, pulse, pulse)
	if model != null:
		var bob: float = 0.0
		var tilt: float = 0.0
		var sq: float = 1.0
		if grounded:
			bob = absf(sin(run_phase * TAU)) * 0.08 * clampf(absf(vel.x) / 4.0, 0.0, 1.0)
			tilt = -0.06 * clampf(absf(vel.x) / max_vx, 0.0, 1.0)
		else:
			tilt = clampf(vel.y * 0.035, -0.3, 0.25)
			sq = 1.0 + 0.12 * sin(flap_anim * PI)
		if dash_t > 0.0:
			tilt -= 0.16
		model.position.y = bob
		model.rotation.z = tilt
		model.scale = Vector3(1.0 / sqrt(sq), sq, 1.0)
	var wrist_a: float = 0.18 if flap_anim > 0.35 else -0.42
	for i in wings.size():
		var side: float = 1.0 if i == 0 else -1.0
		wings[i].visible = model == null or not grounded
		wings[i].rotation.x = side * wa
		if i < wrists.size() and wrists[i] != null:
			wrists[i].rotation.x = side * wrist_a
	for i in legs.size():
		var ph: float = run_phase * TAU + (PI if i == 1 else 0.0)
		legs[i].rotation.z = sin(ph) * 0.8 if grounded else 0.9


func _mat(c: Color, emis: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.65
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	return m


func _part(mesh: Mesh, c: Color, p: Vector3, parent: Node3D, s := Vector3.ONE, emis := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(c, emis)
	mi.position = p
	mi.scale = s
	parent.add_child(mi)
	return mi


func _build_visual() -> void:
	vis = Node3D.new()
	add_child(vis)
	var cols: Array = COLORS[kind]
	var mount: Color = cols[0]
	var armour: Color = cols[1]
	var accent: Color = cols[2]
	var model_path := "res://assets/models/%s.glb" % MODELS[kind]
	if ResourceLoader.exists(model_path):
		var m: Node3D = (load(model_path) as PackedScene).instantiate()
		var holder := Node3D.new()
		vis.add_child(holder)
		holder.add_child(m)
		ModelFit.fit(m, H * 1.25, MODEL_YAW[kind])
		ModelFit.matte(m)
		var oc: Color = Color(0.75, 0.92, 1.0) if kind == Kind.PLAYER else Color(0.12, 0.03, 0.05)
		ModelFit.outline(m, oc, 0.055 if kind == Kind.PLAYER else 0.04)
		model = holder
		_attach_flight_wings(holder, oc)
		if kind == Kind.PLAYER:
			_player_halo()
			_shield_bubble()
			_lance_beam()
		return
	# placeholder mount: body, neck, head, beak
	var sphere := SphereMesh.new()
	_part(sphere, mount, Vector3(0, 0.95, 0), vis, Vector3(0.95, 0.62, 0.55))
	var neck := CylinderMesh.new()
	neck.top_radius = 0.07
	neck.bottom_radius = 0.11
	neck.height = 0.75
	var n := _part(neck, mount, Vector3(0.38, 1.32, 0), vis)
	n.rotation.z = -0.45
	_part(sphere, mount, Vector3(0.56, 1.66, 0), vis, Vector3(0.26, 0.22, 0.2))
	var beak := BoxMesh.new()
	beak.size = Vector3(0.24, 0.07, 0.08)
	_part(beak, Color(0.95, 0.7, 0.2), Vector3(0.74, 1.64, 0), vis)
	# legs pivot at the hip
	var leg := CylinderMesh.new()
	leg.top_radius = 0.05
	leg.bottom_radius = 0.04
	leg.height = 0.7
	for z in [0.14, -0.14]:
		var hip := Node3D.new()
		hip.position = Vector3(0.0, 0.7, z)
		vis.add_child(hip)
		_part(leg, Color(0.9, 0.65, 0.25), Vector3(0, -0.35, 0), hip)
		legs.append(hip)
	# wings pivot at the shoulder, on each side
	var wing := BoxMesh.new()
	wing.size = Vector3(0.7, 0.06, 0.75)
	for side in [1.0, -1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(-0.05, 1.12, 0.22 * side)
		vis.add_child(sh)
		_part(wing, mount.darkened(0.15), Vector3(0, 0, 0.38 * side), sh)
		wings.append(sh)
	# knight: torso, helmet, plume, lance
	var torso := BoxMesh.new()
	torso.size = Vector3(0.32, 0.46, 0.34)
	_part(torso, armour, Vector3(-0.08, 1.48, 0), vis)
	_part(sphere, armour, Vector3(-0.06, 1.86, 0), vis, Vector3(0.24, 0.26, 0.24))
	var plume := BoxMesh.new()
	plume.size = Vector3(0.28, 0.1, 0.06)
	_part(plume, accent, Vector3(-0.2, 2.02, 0), vis, Vector3.ONE, 0.6)
	var lance := CylinderMesh.new()
	lance.top_radius = 0.025
	lance.bottom_radius = 0.06
	lance.height = 1.6
	var l := _part(lance, accent.lightened(0.3), Vector3(0.55, LANCE, 0.18), vis)
	l.rotation.z = -PI * 0.5
	if kind == Kind.PLAYER:
		_player_halo()
		_shield_bubble()
		_lance_beam()


func _player_halo() -> void:
	# soft blue halo behind the player so it reads instantly among the enemies
	var g := Gradient.new()
	g.set_color(0, Color(0.35, 0.65, 1.0, 0.55))
	g.set_color(1, Color(0.35, 0.65, 1.0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	halo_fx = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.8, 2.8)
	halo_fx.mesh = qm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_texture = t
	halo_fx.material_override = m
	halo_fx.position = Vector3(0, 1.1, -0.9)
	add_child(halo_fx)


func _shield_bubble() -> void:
	shield_fx = MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 1.3
	s.height = 2.6
	s.radial_segments = 28
	s.rings = 16
	shield_fx.mesh = s
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/shield.gdshader")
	shield_fx.material_override = sm
	shield_fx.position.y = 1.05
	shield_fx.visible = false
	add_child(shield_fx)


func _lance_beam() -> void:
	# glowing forward energy spearhead when LONG LANCE is active; attached to vis so it flips with facing
	lance_fx = Node3D.new()
	lance_fx.position = Vector3(1.15, LANCE, 0.08)
	lance_fx.visible = false
	vis.add_child(lance_fx)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.015
	cm.bottom_radius = 0.11
	cm.height = 1.35
	beam.mesh = cm
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(1.0, 0.85, 0.3, 0.9)
	beam.material_override = m
	beam.rotation.z = -PI * 0.5
	lance_fx.add_child(beam)


func _attach_flight_wings(parent: Node3D, outline_col: Color) -> void:
	# Hinged multi-feather flight wings (WingRight/WingLeft + WristRight/WristLeft from wing_feathered.glb).
	var wc: Color = WING_COLORS[kind]
	var wing_path := "res://assets/models/wing_feathered.glb"
	if ResourceLoader.exists(wing_path):
		var src: Node3D = (load(wing_path) as PackedScene).instantiate()
		var inner_mat := _mat(wc)
		inner_mat.rim_enabled = true
		inner_mat.rim = 0.5
		var tip_mat := _mat(wc.lightened(0.24))
		tip_mat.rim_enabled = true
		tip_mat.rim = 0.55
		for idx in 2:
			var tag: String = "Right" if idx == 0 else "Left"
			var side: float = 1.0 if idx == 0 else -1.0
			var sh := Node3D.new()
			sh.position = Vector3(-0.08, 1.04, 0.20 * side)
			sh.scale = Vector3.ONE * 0.92
			parent.add_child(sh)
			var wnode := src.find_child("Wing" + tag, true, false) as Node3D
			if wnode != null:
				ModelFit.detach(wnode)
				sh.add_child(wnode)
				wnode.position = Vector3.ZERO
				for mi in wnode.find_children("*", "MeshInstance3D", true, false):
					var inst := mi as MeshInstance3D
					var use_tip: bool = inst.name.begins_with("Primary_0") or inst.name.begins_with("Primary_1") or inst.name.begins_with("Primary_2")
					inst.material_override = tip_mat.duplicate() if use_tip else inner_mat.duplicate()
				wrists.append(wnode.find_child("Wrist" + tag, true, false) as Node3D)
			else:
				wrists.append(null)
			ModelFit.outline(sh, outline_col, 0.025)
			wings.append(sh)
		src.free()
		return
	var feather := SphereMesh.new()
	feather.radius = 0.5
	feather.height = 1.0
	feather.radial_segments = 14
	feather.rings = 8
	for side in [1.0, -1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(-0.08, 1.02, 0.24 * side)
		parent.add_child(sh)
		var inner := _part(feather, wc, Vector3(-0.05, 0.0, 0.36 * side), sh, Vector3(0.78, 0.11, 0.82))
		inner.material_override.rim_enabled = true
		inner.material_override.rim = 0.5
		var tip := _part(feather, wc.lightened(0.18), Vector3(-0.18, 0.02, 0.72 * side), sh, Vector3(0.55, 0.08, 0.58))
		tip.rotation.y = -0.22 * side
		ModelFit.outline(sh, outline_col, 0.03)
		wings.append(sh)
		wrists.append(null)
