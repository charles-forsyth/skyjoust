class_name ModelFit
## Helpers for dropping generated GLBs into the game at a known size.


## Clear owner recursively before reparenting a subtree out of an instantiated PackedScene.
static func detach(n: Node) -> void:
	if n.get_parent() != null:
		n.get_parent().remove_child(n)
	n.owner = null
	for c in n.find_children("*", "", true, false):
		c.owner = null


static func aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var t: Transform3D = n.global_transform.affine_inverse() * m.global_transform if n.is_inside_tree() else _rel(n, m)
		var b: AABB = t * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


static func _rel(root: Node3D, m: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = m
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Scale so the model is `height` tall, feet at y=0, centred on x/z.
static func fit(m: Node3D, height: float, yaw: float) -> void:
	m.rotation.y = yaw
	var b := aabb(m)
	if b.size.y <= 0.0001:
		return
	var s: float = height / b.size.y
	m.scale = Vector3.ONE * s
	var c := b.get_center()
	m.position = Vector3(-c.x * s, -b.position.y * s, -c.z * s)


## Hunyuan GLBs import fully metallic; make them read as painted toys.
static func matte(m: Node) -> void:
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		for i in inst.mesh.get_surface_count():
			var mat := inst.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var sm := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				sm.metallic = 0.0
				sm.metallic_specular = 0.3
				sm.roughness = 0.75
				sm.rim_enabled = true
				sm.rim = 0.6
				sm.rim_tint = 0.4
				inst.set_surface_override_material(i, sm)


## Add an inverted-hull outline pass to every mesh (handles material_override and surface materials,
## duplicates shared imported materials safely, and shares one ShaderMaterial across the model).
static func outline(m: Node, col: Color, width: float) -> void:
	var o := ShaderMaterial.new()
	o.shader = load("res://shaders/outline.gdshader")
	o.set_shader_parameter("color", col)
	o.set_shader_parameter("width", width)
	var seen := {}
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.material_override != null:
			var mo := inst.material_override
			if not seen.has(mo):
				mo.next_pass = o
				seen[mo] = true
			continue
		if inst.mesh == null:
			continue
		for i in inst.mesh.get_surface_count():
			var mat := inst.get_surface_override_material(i)
			if mat == null:
				var base := inst.mesh.surface_get_material(i)
				if base == null:
					continue
				mat = base.duplicate()
				inst.set_surface_override_material(i, mat)
			if not seen.has(mat):
				mat.next_pass = o
				seen[mat] = true
