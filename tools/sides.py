import bpy, sys, os, math
from mathutils import Vector
# blender -b --factory-startup -P sides.py -- <glb> <out.png>
# Renders the model from 4 horizontal directions (glTF +Z fwd / Godot -Z ... we just label by angle)
glb, out = sys.argv[sys.argv.index('--') + 1:][:2]
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 1600
sc.render.resolution_y = 400
sc.world = bpy.data.worlds.new('w'); sc.world.use_nodes = True
sc.world.node_tree.nodes['Background'].inputs[0].default_value = (0.8, 0.8, 0.82, 1)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=glb)
ms = [o for o in bpy.data.objects if o.type == 'MESH']
pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
c = (lo + hi) / 2; r = (hi - lo).length / 2
root = bpy.data.objects.new('root', None); sc.collection.objects.link(root)
for o in ms:
    if o.parent is None:
        o.parent = root
# 4 copies side by side, each rotated about Blender Z (glTF Y-up) by 0/90/180/270
copies = []
for i in range(4):
    for o in ms:
        if i == 0:
            continue
for i, ang in enumerate([0, 90, 180, 270]):
    if i == 0:
        holder = root
    else:
        holder = bpy.data.objects.new(f'h{i}', None); sc.collection.objects.link(holder)
        for o in ms:
            d = o.copy(); d.data = o.data; sc.collection.objects.link(d); d.parent = holder
            d.matrix_parent_inverse = o.matrix_parent_inverse.copy()
    holder.location = Vector(((i - 1.5) * r * 2.4, 0, 0)) - Vector((c.x, c.y, 0))
    holder.rotation_euler = (0, 0, math.radians(ang))
cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = 'ORTHO'; cam.data.ortho_scale = r * 2.4 * 4
cam.location = Vector((0, -r * 10, c.z)); cam.rotation_euler = (math.radians(90), 0, 0)
sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun', 'SUN')); sun.data.energy = 3.5
sun.rotation_euler = (math.radians(60), 0, math.radians(20)); sc.collection.objects.link(sun)
sc.render.filepath = out
bpy.ops.render.render(write_still=True)
print('DONE')
