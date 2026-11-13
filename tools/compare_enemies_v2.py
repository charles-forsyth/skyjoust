# Render concept + batch1 GLB + batch2 s7 GLB + batch2 s21 GLB side-by-side for QA.
# Run: env -u PYTHONPATH blender -b --factory-startup -P tools/compare_enemies_v2.py -- <v2_glb_dir> <out_png>
import bpy, math, os, sys
from mathutils import Vector

v2_dir, out_png = sys.argv[sys.argv.index("--") + 1 :][:2]
root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
b1_dir = os.path.join(root_dir, "cluster", "out")

sc = bpy.context.scene
sc.render.engine = "BLENDER_EEVEE"
sc.render.resolution_x = 1800
sc.render.resolution_y = 1350
sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.78, 0.78, 0.81, 1)
sc.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)

names = ["enemy_bounder", "enemy_hunter", "enemy_shadowlord"]
cols = [
    ("b1", lambda n: os.path.join(b1_dir, f"{n}.glb")),
    ("s7", lambda n: os.path.join(v2_dir, f"{n}_s7.glb")),
    ("s21", lambda n: os.path.join(v2_dir, f"{n}_s21.glb")),
]

CELL = 3.2
for ri, name in enumerate(names):
    for ci, (tag, fn) in enumerate(cols):
        p = fn(name)
        if not os.path.exists(p):
            continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=p)
        added = [o for o in bpy.data.objects if o not in before]
        ms = [o for o in added if o.type == "MESH"]
        if not ms:
            continue
        # make matte so metallic=1.0 doesn't darken shadow faces
        for m in ms:
            for slot in m.material_slots:
                mat = slot.material
                if mat and mat.use_nodes:
                    for nd in mat.node_tree.nodes:
                        if nd.type == "BSDF_PRINCIPLED":
                            nd.inputs["Metallic"].default_value = 0.0
                            nd.inputs["Roughness"].default_value = 0.75
        bpy.context.view_layer.update()
        pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
        lo = Vector([min(pt[i] for pt in pts) for i in range(3)])
        hi = Vector([max(pt[i] for pt in pts) for i in range(3)])
        sz = max((hi - lo).x, (hi - lo).y, (hi - lo).z, 1e-4)
        s = 2.2 / sz
        holder = bpy.data.objects.new(f"{name}_{tag}", None)
        sc.collection.objects.link(holder)
        for o in added:
            if o.parent is None:
                o.parent = holder
        # auto-orient long horizontal axis along +X if Z/Y is longer
        holder.scale = (s, s, s)
        ctr = (lo + hi) * 0.5
        gx = (ci - 1.0) * CELL
        gz = (1.0 - ri) * CELL
        holder.location = Vector((gx - ctr.x * s, -ctr.y * s, gz - ctr.z * s))
        holder.rotation_euler = (0.0, 0.0, math.radians(-25))

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = CELL * 3.15
cam.location = Vector((0.0, -12.0, 0.0))
cam.rotation_euler = (math.radians(90), 0.0, 0.0)

sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.2
sun.rotation_euler = (math.radians(55), 0.0, math.radians(25))
sc.collection.objects.link(sun)

fill = bpy.data.objects.new("fill", bpy.data.lights.new("fill", "SUN"))
fill.data.energy = 1.1
fill.rotation_euler = (math.radians(75), 0.0, math.radians(-135))
sc.collection.objects.link(fill)

os.makedirs(os.path.dirname(os.path.abspath(out_png)), exist_ok=True)
sc.render.filepath = out_png
bpy.ops.render.render(write_still=True)
print("COMPARE DONE", out_png)
