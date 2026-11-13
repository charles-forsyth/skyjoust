class_name Egg
extends Node3D
## Dropped by a beaten rider. Collect it before it hatches into a tougher one.

const G := 22.0
const R := 0.38
const H := 0.76
const HATCH := [7.0, 6.0, 5.0]   # seconds, by tier the egg came from

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var tier: int = 0               # 0 bounder, 1 hunter, 2 shadow
var t := 0.0
var grounded := false
var mesh: MeshInstance3D


func setup(p: Vector2, v: Vector2, from_tier: int) -> void:
	pos = p
	vel = v
	tier = from_tier
	var path := "res://assets/models/egg.glb"
	if ResourceLoader.exists(path):
		var m: Node3D = (load(path) as PackedScene).instantiate()
		add_child(m)
		ModelFit.fit(m, R * 2.3, 0.0)
		ModelFit.matte(m)
		ModelFit.outline(m, Color(0.22, 0.10, 0.02), 0.025)
	else:
		mesh = MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = R
		s.height = R * 2.6
		mesh.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.82, 0.3)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.7, 0.2)
		mat.emission_energy_multiplier = 0.6
		mat.roughness = 0.35
		mesh.material_override = mat
		mesh.position.y = R * 1.3
		add_child(mesh)


func hatch_time() -> float:
	return HATCH[clampi(tier, 0, 2)]


func _hits(r: Rect2) -> bool:
	return pos.x + R > r.position.x and pos.x - R < r.end.x \
		and pos.y + H > r.position.y and pos.y < r.end.y


func step(dt: float, plats: Array[Rect2], half: float) -> void:
	t += dt
	vel.y = maxf(vel.y - G * dt, -14.0)
	vel.x = move_toward(vel.x, 0.0, (6.0 if grounded else 0.6) * dt)
	pos.x += vel.x * dt
	for r: Rect2 in plats:
		if _hits(r):
			if vel.x > 0.0:
				pos.x = r.position.x - R - 0.001
			else:
				pos.x = r.end.x + R + 0.001
			vel.x = -vel.x * 0.5
	if pos.x >= half:
		pos.x -= half * 2.0
	elif pos.x < -half:
		pos.x += half * 2.0
	grounded = false
	var prev_y := pos.y
	pos.y += vel.y * dt
	for r: Rect2 in plats:
		if pos.x + R * 0.6 > r.position.x and pos.x - R * 0.6 < r.end.x:
			if vel.y <= 0.0 and prev_y >= r.end.y - 0.05 and pos.y < r.end.y:
				pos.y = r.end.y
				if vel.y < -4.0:
					vel.y = -vel.y * 0.3   # one small bounce
				else:
					vel.y = 0.0
					grounded = true
			elif vel.y > 0.0 and prev_y + H <= r.position.y + 0.05 and pos.y + H > r.position.y:
				pos.y = r.position.y - H - 0.001
				vel.y = -absf(vel.y) * 0.35
	position = Vector3(pos.x, pos.y, 0.0)
	# wobble harder as hatching nears
	var left := hatch_time() - t
	var w: float = 0.0 if left > 2.0 else (2.0 - left) * 0.25
	rotation.z = sin(t * 30.0) * w
