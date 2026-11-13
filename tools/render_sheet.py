import bpy, sys, glob, os, math
from mathutils import Vector
# blender -b -P render_sheet.py -- <glb_dir> <out_dir>
src, out = sys.argv[sys.argv.index('--')+1:][:2]
os.makedirs(out, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = 'BLENDER_EEVEE_NEXT' if 'BLENDER_EEVEE_NEXT' in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties['engine'].enum_items] else 'BLENDER_EEVEE'
sc.render.resolution_x = sc.render.resolution_y = 512
sc.world = bpy.data.worlds.new('w'); sc.world.use_nodes = True
sc.world.node_tree.nodes['Background'].inputs[0].default_value = (0.75, 0.75, 0.78, 1)
sc.world.node_tree.nodes['Background'].inputs[1].default_value = 1.0
for f in sorted(glob.glob(os.path.join(src, '*.glb'))):
    if '_shape' in f: continue
    n = os.path.basename(f)[:-4]
    bpy.ops.wm.read_factory_settings(use_empty=True) if False else None
    for o in list(bpy.data.objects): bpy.data.objects.remove(o, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=f)
    ms = [o for o in bpy.data.objects if o.type == 'MESH']
    pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
    lo = Vector([min(p[i] for p in pts) for i in range(3)]); hi = Vector([max(p[i] for p in pts) for i in range(3)])
    c = (lo+hi)/2; r = (hi-lo).length/2
    cam = bpy.data.objects.new('cam', bpy.data.cameras.new('cam')); sc.collection.objects.link(cam); sc.camera = cam
    # RTS-ish view: 40 deg down, 3/4
    d = r*3.2; el = math.radians(40); az = math.radians(35)
    cam.location = c + Vector((d*math.cos(el)*math.sin(az), -d*math.cos(el)*math.cos(az), d*math.sin(el)))
    cam.rotation_euler = (c-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.lens = 50
    sun = bpy.data.objects.new('sun', bpy.data.lights.new('sun','SUN')); sun.data.energy = 3.5
    sun.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(sun)
    sc.render.filepath = os.path.join(out, n + '.png'); bpy.ops.render.render(write_still=True)
print('DONE')
