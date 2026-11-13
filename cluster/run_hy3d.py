# Image -> textured GLB with Hunyuan3D-2 (shape + paint). Usage: python run_hy3d.py <img> <out.glb>
import sys, time, os, traceback
from PIL import Image
t0 = time.time()
src, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.environ.get("HY3D", "Hunyuan3D-2"))
from hy3dgen.rembg import BackgroundRemover
from hy3dgen.shapegen import Hunyuan3DDiTFlowMatchingPipeline, FaceReducer, FloaterRemover, DegenerateFaceRemover
img = Image.open(src).convert("RGB")
img = BackgroundRemover()(img)
img.save(out.replace(".glb", "_cut.png"))
print(f"STAGE rembg {time.time()-t0:.0f}s", flush=True)
shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2")
print(f"STAGE shape_loaded {time.time()-t0:.0f}s", flush=True)
mesh = shape(image=img, num_inference_steps=50, octree_resolution=384, num_chunks=20000, generator=__import__("torch").manual_seed(7))[0]
mesh = FloaterRemover()(mesh); mesh = DegenerateFaceRemover()(mesh)
print(f"STAGE shape faces={len(mesh.faces)} {time.time()-t0:.0f}s", flush=True)
mesh.export(out.replace(".glb", "_shape_raw.glb"))
mesh = FaceReducer()(mesh, max_facenum=60000)
mesh.export(out.replace(".glb", "_shape.glb"))
del shape; __import__("torch").cuda.empty_cache()
try:
    # newer diffusers refuses the bundled hunyuanpaint custom pipeline unless trusted
    import diffusers
    _fp = diffusers.DiffusionPipeline.from_pretrained.__func__
    diffusers.DiffusionPipeline.from_pretrained = classmethod(lambda cls, *a, **k: _fp(cls, *a, **{"trust_remote_code": True, **k}))
    from hy3dgen.texgen import Hunyuan3DPaintPipeline
    paint = Hunyuan3DPaintPipeline.from_pretrained("tencent/Hunyuan3D-2")
    print(f"STAGE paint_loaded {time.time()-t0:.0f}s", flush=True)
    mesh = paint(mesh, image=img)
    mesh.export(out)
    print(f"STAGE paint {time.time()-t0:.0f}s", flush=True)
except Exception:
    traceback.print_exc()
    print("PAINT FAILED (shape-only GLB kept)", flush=True)
print(f"HY3D DONE {time.time()-t0:.0f}s", flush=True)
