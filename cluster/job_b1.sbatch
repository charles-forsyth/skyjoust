#!/bin/bash
#SBATCH --job-name=joust-img3d-b1
#SBATCH --array=0-10
#SBATCH --output=slurm-%A_%a.out
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=02:00:00
# Hunyuan3D-2 image -> textured GLB, one model per inputs/*_concept.png, on an NVIDIA L4/V100 GPU.
# Installs into ~/apps/hy3d once (venv + repo + compiled texture extensions); reruns reuse it.
set -euo pipefail
echo "START $(hostname) $(date -u +%FT%TZ)"; nvidia-smi -L
module load apptainer
A=$HOME/apps/hy3d; mkdir -p $A; export HF_HOME=$A/hf U2NET_HOME=$A/u2net
cd $A
UV=$HOME/.local/bin/uv
[ -x $UV ] || curl -LsSf https://astral.sh/uv/install.sh | sh
# Step 1: Python deps (skipped when the venv already passes the version check)
if [ "$(cat $A/.deps 2>/dev/null)" != "v4" ] && ! ( . $A/venv/bin/activate 2>/dev/null && python -c "import torch, transformers, hy3dgen; assert torch.__version__.startswith('2.6.0')" 2>/dev/null ); then
  echo "== deps install"; t=$(date +%s)
  [ -d Hunyuan3D-2 ] || git clone --depth 1 https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git
  # uv-managed Python lives under $HOME, so the same venv works inside the CUDA devel container
  rm -rf venv; $UV venv --python 3.11 --python-preference only-managed venv
  . venv/bin/activate
  printf '%s\n' torch==2.6.0 torchvision==0.21.0 'transformers>=4.48,<5' 'numpy<2' > $A/constraints.txt
  $UV pip install -c $A/constraints.txt torch torchvision --index-url https://download.pytorch.org/whl/cu124
  $UV pip install -c $A/constraints.txt -r Hunyuan3D-2/requirements.txt setuptools wheel pip pybind11 ninja
  $UV pip install -c $A/constraints.txt -e Hunyuan3D-2
  python -c "import torch, diffusers, transformers; print('deps', torch.__version__, diffusers.__version__, transformers.__version__); assert torch.__version__.startswith('2.6.0'); assert transformers.__version__.startswith('4.')"
  echo v4 > $A/.deps
  echo "== deps took $(( $(date +%s)-t ))s"
fi
. $A/venv/bin/activate
# Step 2: build AND run inside the CUDA 12.4 devel container. Extensions built there link
# against its glibc 2.35; the Rocky 8 host has glibc 2.28, so they can't be imported outside it.
SIF="${CUDA_SIF:-cuda-12.4-devel.sif}"
# Step 1b: X11/GL runtime libs (pymeshlab and opencv need libX11/libGL; the CUDA devel image has none).
# Fetched as Ubuntu 22.04 debs with apt as a normal user and unpacked under $A/xlibs (no root needed).
X=$A/xlibs
if [ ! -f $X/.ok ]; then
  echo "== fetching X11/GL libs"; t=$(date +%s)
  rm -rf $X; mkdir -p $X/debs $X/root $X/apt/lists/partial $X/apt/cache/archives/partial
  apptainer exec -B $A $SIF bash -c "set -e; cd $X/debs
    O='-qq -o Dir::State::Lists=$X/apt/lists -o Dir::Cache=$X/apt/cache -o Debug::NoLocking=1 -o APT::Sandbox::User=$(id -un)'
    apt-get \$O update
    apt-get \$O download libx11-6 libxcb1 libxau6 libxdmcp6 libbsd0 libmd0 libxext6 libxrender1 libsm6 libice6 libuuid1 \
      libgl1 libglx0 libglvnd0 libopengl0 libegl1 libglu1-mesa libglib2.0-0 libxi6 libxfixes3 libxkbcommon0 libgomp1
    for d in *.deb; do dpkg-deb -x \$d $X/root; done"
  ls $X/root/usr/lib/x86_64-linux-gnu/libX11.so.6
  touch $X/.ok
  echo "== xlibs took $(( $(date +%s)-t ))s"
fi
IN="apptainer exec --nv -B $A,$SLURM_SUBMIT_DIR $SIF env CUDA_HOME=/usr/local/cuda TORCH_CUDA_ARCH_LIST=8.9 HF_HOME=$HF_HOME U2NET_HOME=$U2NET_HOME HY3D=$A/Hunyuan3D-2 PYTHONPATH=$A/Hunyuan3D-2/hy3dgen/texgen/differentiable_renderer LD_LIBRARY_PATH=/.singularity.d/libs:$X/root/usr/lib/x86_64-linux-gnu $A/venv/bin/python"
CHECK="import torch, custom_rasterizer, mesh_processor; assert torch.cuda.is_available(), 'no CUDA in container'; print('texture extensions ok')"
if ! $IN -c "$CHECK" 2>/dev/null; then
  echo "== compiling texture extensions (in container)"; t=$(date +%s)
  apptainer exec --nv -B $A $SIF bash -c "set -e
    export CUDA_HOME=/usr/local/cuda PATH=/usr/local/cuda/bin:\$PATH TORCH_CUDA_ARCH_LIST=8.9
    . $A/venv/bin/activate
    cd $A/Hunyuan3D-2/hy3dgen/texgen/custom_rasterizer && python -m pip install --no-build-isolation -e . 2>&1 | tail -3
    cd ../differentiable_renderer && python setup.py build_ext --inplace 2>&1 | tail -3"
  $IN -c "$CHECK"
  echo "== compile took $(( $(date +%s)-t ))s"
fi
cd "$SLURM_SUBMIT_DIR"
# inputs may arrive as one tarball (one upload for many files): unpack once, under a lock
if ls inputs/*.tar >/dev/null 2>&1; then
  flock inputs/.unpack.lock bash -c 'if [ ! -f inputs/.unpacked ]; then for t in inputs/*.tar; do tar -xf "$t" -C inputs; done; touch inputs/.unpacked; fi'
fi
# fail fast with the missing library list instead of a traceback per model
$IN -c "import pymeshlab, cv2, rembg; print('runtime imports ok')" || { $IN -c "import pymeshlab,os;print(os.path.dirname(pymeshlab.__file__))" 2>/dev/null; apptainer exec -B $A $SIF env LD_LIBRARY_PATH=$X/root/usr/lib/x86_64-linux-gnu bash -c "ldd $A/venv/lib/python3.11/site-packages/pymeshlab/pmeshlab*.so | grep 'not found'"; exit 1; }
$IN -c "import torch;print('torch',torch.__version__,'cuda',torch.cuda.is_available(),torch.cuda.get_device_name(0))"
# shared model cache: one task downloads, the others wait on the lock (no-op once cached)
flock $A/.hf.lock $IN -c "from huggingface_hub import snapshot_download as d; d('tencent/Hunyuan3D-2', allow_patterns=['hunyuan3d-dit-v2-0/*','hunyuan3d-delight-v2-0/*','hunyuan3d-paint-v2-0/*']); print('weights ok')"
mkdir -p out
fail=0
# array task N takes the Nth concept (sorted); without an array, do them all
mapfile -t ALL < <(ls inputs/*_concept.png | sort)
if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then LIST=("${ALL[$SLURM_ARRAY_TASK_ID]}"); else LIST=("${ALL[@]}"); fi
for img in "${LIST[@]}"; do
  n=$(basename $img _concept.png)
  echo "== $n"
  if $IN inputs/run_hy3d.py $img out/$n.glb > out/$n.log 2>&1; then
    grep -E "STAGE|DONE|FAILED" out/$n.log || true
  else
    echo "MODEL FAILED: $n"; tail -30 out/$n.log; fail=1
  fi
  [ -s out/$n.glb ] || [ -s out/${n}_shape.glb ] || { echo "NO GLB for $n"; fail=1; }
done
ls -la out
echo "END $(date -u +%FT%TZ) fail=$fail"
exit $fail
