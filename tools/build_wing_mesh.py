# Build stylized feathered left & right wings (inner arm + hinged wrist + 9 feathers per wing) in Blender.
# Both sides have recalculated outward normals (no negative scale in Godot).
# Run: env -u PYTHONPATH blender -b --factory-startup -P tools/build_wing_mesh.py -- game/assets/models/wing_feathered.glb
import bpy, bmesh, math, os, sys

out_glb = sys.argv[sys.argv.index("--") + 1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)

sc = bpy.context.scene


def make_feather(name: str, length: float, width: float, thick: float, camber: float, side: float) -> bpy.types.Mesh:
    # side = +1.0 -> Godot +Z (right wing); side = -1.0 -> Godot -Z (left wing), i.e. Blender Y = -side * z
    bm = bmesh.new()
    rings = 7
    segs = 8
    ring_verts = []
    for i in range(rings):
        t = i / (rings - 1)
        profile = math.sin(min(t * 1.15, 1.0) * math.pi * 0.88) * 0.85 + (1.0 - t) * 0.35
        if i == rings - 1:
            profile = 0.08
        w = width * profile
        th = thick * (1.0 - 0.65 * t)
        z = length * t
        x_off = -0.08 * length * (t * t)
        y_off = camber * math.sin(t * math.pi)
        vs = []
        for j in range(segs):
            a = (j / segs) * math.tau
            px = math.cos(a) * w * (0.55 if math.cos(a) > 0 else 0.75) + x_off
            pz = math.sin(a) * th + y_off
            vs.append(bm.verts.new((px, -side * z, pz)))
        ring_verts.append(vs)
    for i in range(rings - 1):
        for j in range(segs):
            jn = (j + 1) % segs
            bm.faces.new([ring_verts[i][j], ring_verts[i][jn], ring_verts[i + 1][jn], ring_verts[i + 1][j]])
    bm.faces.new(list(reversed(ring_verts[0])))
    bm.faces.new(ring_verts[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for p in me.polygons:
        p.use_smooth = True
    return me


mat_inner = bpy.data.materials.new("WingInner")
mat_inner.use_nodes = True
bsdf_i = mat_inner.node_tree.nodes["Principled BSDF"]
bsdf_i.inputs["Base Color"].default_value = (0.78, 0.78, 0.82, 1.0)
bsdf_i.inputs["Roughness"].default_value = 0.75
bsdf_i.inputs["Metallic"].default_value = 0.0

mat_tip = bpy.data.materials.new("WingTip")
mat_tip.use_nodes = True
bsdf_t = mat_tip.node_tree.nodes["Principled BSDF"]
bsdf_t.inputs["Base Color"].default_value = (1.0, 0.98, 0.96, 1.0)
bsdf_t.inputs["Roughness"].default_value = 0.70
bsdf_t.inputs["Metallic"].default_value = 0.0

for tag, side in [("Right", 1.0), ("Left", -1.0)]:
    root = bpy.data.objects.new(f"Wing{tag}", None)
    sc.collection.objects.link(root)

    arm_me = make_feather(f"CovertArm_{tag}", 0.54, 0.19, 0.052, 0.028, side)
    arm_ob = bpy.data.objects.new(f"InnerArm_{tag}", arm_me)
    arm_ob.data.materials.append(mat_inner)
    arm_ob.location = (0.08, 0.0, 0.01)
    arm_ob.parent = root
    sc.collection.objects.link(arm_ob)

    for k in range(4):
        u = k / 3.0
        fme = make_feather(f"Sec_{tag}_{k}", 0.42 + 0.05 * u, 0.125, 0.03, 0.018, side)
        fob = bpy.data.objects.new(f"Secondary_{tag}_{k}", fme)
        fob.data.materials.append(mat_inner)
        fob.location = (-0.04 - 0.08 * u, -side * (0.08 + 0.11 * u), -0.008 * k)
        fob.rotation_euler = (0.0, 0.0, math.radians(side * (-18 - 10 * u)))
        fob.parent = root
        sc.collection.objects.link(fob)

    wrist = bpy.data.objects.new(f"Wrist{tag}", None)
    wrist.location = (0.04, -side * 0.46, 0.01)
    wrist.parent = root
    sc.collection.objects.link(wrist)

    for k in range(5):
        u = k / 4.0
        plen = 0.58 - 0.15 * u
        pme = make_feather(f"Pri_{tag}_{k}", plen, 0.105 - 0.014 * u, 0.024, 0.022, side)
        pob = bpy.data.objects.new(f"Primary_{tag}_{k}", pme)
        pob.data.materials.append(mat_tip if k < 3 else mat_inner)
        pob.location = (0.03 - 0.07 * u, -side * (0.02 * u), -0.007 * k)
        pob.rotation_euler = (math.radians(side * 2 * u), 0.0, math.radians(side * (-6 - 13 * u)))
        pob.parent = wrist
        sc.collection.objects.link(pob)

os.makedirs(os.path.dirname(os.path.abspath(out_glb)), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=out_glb, export_format="GLB", export_yup=True)
print("WINGS EXPORTED", out_glb)
