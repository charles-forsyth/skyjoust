# Prepare fast, matte-shaded, yaw-aligned web GLBs for <model-viewer> in docs/models/.
# Converts Hunyuan3D's raw metallic=1.0 materials to painted-miniature matte (metallic=0.0, roughness=0.72),
# aligns forward yaw, centers at origin, decimates to ~24k faces, and compresses embedded textures to JPEG.
import bpy, math, os, sys

src_dir, out_dir = sys.argv[sys.argv.index("--") + 1 : sys.argv.index("--") + 3]
os.makedirs(out_dir, exist_ok=True)

ASSETS = [
    ("player_ostrich", 0.0, 24000, None),
    ("enemy_hunter", 0.0, 26000, None),
    ("enemy_bounder", 0.0, 26000, None),
    ("enemy_shadowlord", 0.0, 26000, None),
    ("pterodactyl", math.pi * 0.5, 22000, None),
    ("buzzard_riderless", math.pi * 0.5, 22000, None),
    ("egg", 0.0, 16000, None),
    ("platform_long", 0.0, 22000, None),
    ("spawn_pad", 0.0, 18000, None),
    ("wing_feathered", 0.0, 99999, (0.42, 0.58, 0.86, 1.0)),
]

for name, yaw, target_faces, tint in ASSETS:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    in_p = os.path.join(src_dir, f"{name}.glb")
    out_p = os.path.join(out_dir, f"{name}.glb")
    bpy.ops.import_scene.gltf(filepath=in_p)

    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    # Fix materials: matte painted miniature look (never metallic=1.0 dark chrome)
    for m in bpy.data.materials:
        if not m.use_nodes or not m.node_tree:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED":
                n.inputs["Metallic"].default_value = 0.0
                n.inputs["Roughness"].default_value = 0.72
                if tint is not None and "Tip" not in m.name:
                    n.inputs["Base Color"].default_value = tint

    # Apply yaw on root objects & decimate dense AI meshes cleanly
    roots = [o for o in bpy.data.objects if o.parent is None]
    for r in roots:
        r.rotation_mode = "XYZ"
        r.rotation_euler[2] += yaw

    total_faces = sum(len(o.data.polygons) for o in meshes)
    if total_faces > target_faces and len(meshes) == 1:
        ob = meshes[0]
        bpy.context.view_layer.objects.active = ob
        mod = ob.modifiers.new("WebDecimate", "DECIMATE")
        mod.ratio = target_faces / float(total_faces)
        bpy.ops.object.modifier_apply(modifier=mod.name)

    bpy.ops.export_scene.gltf(
        filepath=out_p,
        export_format="GLB",
        export_yup=True,
        export_image_format="JPEG",
        export_jpeg_quality=88,
    )
    new_faces = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    print(f"WEB GLB {name:20s}  {os.path.getsize(out_p)/1024:6.1f} KB  faces={new_faces}")
