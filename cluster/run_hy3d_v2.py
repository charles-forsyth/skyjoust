# Image -> high-detail textured GLB with Hunyuan3D-2 (octree 512 + paint, configurable seed).
# Usage: HY_OCT=512 HY_FACES=100000 HY_SEED=7 python run_hy3d_v2.py <img> <out.glb>
import gc, os, sys, time, traceback
from PIL import Image

t0 = time.time()
src, out = sys.argv[1], sys.argv[2]
octree = int(os.environ.get("HY_OCT", "512"))
max_faces = int(os.environ.get("HY_FACES", "100000"))
seed = int(os.environ.get("HY_SEED", "7"))

sys.path.insert(0, os.environ.get("HY3D", "Hunyuan3D-2"))
import torch
from hy3dgen.rembg import BackgroundRemover
from hy3dgen.shapegen import (
    DegenerateFaceRemover,
    FaceReducer,
    FloaterRemover,
    Hunyuan3DDiTFlowMatchingPipeline,
)

img = Image.open(src).convert("RGB")
img = BackgroundRemover()(img)
img.save(out.replace(".glb", "_cut.png"))
print(f"STAGE rembg {time.time()-t0:.0f}s", flush=True)

shape = Hunyuan3DDiTFlowMatchingPipeline.from_pretrained("tencent/Hunyuan3D-2")
print(f"STAGE shape_loaded {time.time()-t0:.0f}s", flush=True)
try:
    mesh = shape(
        image=img,
        num_inference_steps=50,
        octree_resolution=octree,
        num_chunks=20000,
        generator=torch.manual_seed(seed),
    )[0]
except torch.cuda.OutOfMemoryError:
    print(f"WARN OOM at octree={octree}; retrying at octree=384", flush=True)
    torch.cuda.empty_cache()
    octree = 384
    mesh = shape(
        image=img,
        num_inference_steps=50,
        octree_resolution=octree,
        num_chunks=16000,
        generator=torch.manual_seed(seed),
    )[0]
mesh = FloaterRemover()(mesh)
mesh = DegenerateFaceRemover()(mesh)
print(f"STAGE shape oct={octree} seed={seed} faces={len(mesh.faces)} {time.time()-t0:.0f}s", flush=True)
mesh.export(out.replace(".glb", "_shape_raw.glb"))
mesh = FaceReducer()(mesh, max_facenum=max_faces)
mesh.export(out.replace(".glb", "_shape.glb"))
del shape
gc.collect()
torch.cuda.empty_cache()

try:
    import diffusers
    _fp = diffusers.DiffusionPipeline.from_pretrained.__func__
    diffusers.DiffusionPipeline.from_pretrained = classmethod(
        lambda cls, *a, **k: _fp(cls, *a, **{"trust_remote_code": True, **k})
    )
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
