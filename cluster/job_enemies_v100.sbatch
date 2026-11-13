#!/bin/bash
#SBATCH --job-name=joust-enemies-v100
#SBATCH --array=0-2
#SBATCH --output=slurm-%A_%a.out
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=00:45:00
# Hunyuan3D-2 on Tesla V100 (sm_70): 3 tasks (1 per enemy rider), each runs seeds 7 & 21.
set -euo pipefail
echo "START $(hostname) $(date -u +%FT%TZ) task=${SLURM_ARRAY_TASK_ID:-0}"
nvidia-smi -L
module load apptainer

A=$HOME/apps/hy3d
export HF_HOME=$A/hf U2NET_HOME=$A/u2net
SIF="${CUDA_SIF:-cuda-12.4-devel.sif}"
X=$A/xlibs

[ -x "$A/venv/bin/python" ] || { echo "ERROR: ~/apps/hy3d/venv missing"; exit 1; }
[ -d "$X/root" ] || { echo "ERROR: ~/apps/hy3d/xlibs missing"; exit 1; }

IN="apptainer exec --nv -B $A,$SLURM_SUBMIT_DIR $SIF env CUDA_HOME=/usr/local/cuda HF_HOME=$HF_HOME U2NET_HOME=$U2NET_HOME HY3D=$A/Hunyuan3D-2 PYTHONPATH=$A/Hunyuan3D-2/hy3dgen/texgen/differentiable_renderer LD_LIBRARY_PATH=/.singularity.d/libs:$X/root/usr/lib/x86_64-linux-gnu $A/venv/bin/python"
CHECK="import torch, custom_rasterizer, mesh_processor; assert torch.cuda.is_available(), 'no CUDA in container'; print('texture extensions ok', torch.cuda.get_device_name(0))"

# Ensure sm_70 (7.0;8.9) fat build is present for V100
exec 9>"$A/.build.lock"; flock 9
if [ ! -f "$A/.arch70" ] || ! $IN -c "$CHECK" 2>/dev/null; then
  echo "== compiling texture extensions fat 7.0+8.9 (in container)"
  apptainer exec --nv -B "$A" "$SIF" bash -c "set -e
    export CUDA_HOME=/usr/local/cuda PATH=/usr/local/cuda/bin:\$PATH TORCH_CUDA_ARCH_LIST='7.0;8.9'
    . $A/venv/bin/activate
    cd $A/Hunyuan3D-2/hy3dgen/texgen/custom_rasterizer && rm -rf build *.egg-info && python -m pip install --no-build-isolation -e . 2>&1 | tail -3
    cd ../differentiable_renderer && rm -rf build && python setup.py build_ext --inplace 2>&1 | tail -3"
  $IN -c "$CHECK" && touch "$A/.arch70"
fi
flock -u 9

WORK="/tmp/joust_hy3d_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID:-0}"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"
for t in "$SLURM_SUBMIT_DIR"/inputs/*.tar; do
  tar -xf "$t" -C "$WORK"
done

IN="apptainer exec --nv -B $A,$SLURM_SUBMIT_DIR,$WORK $SIF env CUDA_HOME=/usr/local/cuda HF_HOME=$HF_HOME U2NET_HOME=$U2NET_HOME HY3D=$A/Hunyuan3D-2 PYTHONPATH=$A/Hunyuan3D-2/hy3dgen/texgen/differentiable_renderer LD_LIBRARY_PATH=/.singularity.d/libs:$X/root/usr/lib/x86_64-linux-gnu $A/venv/bin/python"
$IN -c "import pymeshlab, cv2, rembg; print('runtime imports ok')"

cd "$SLURM_SUBMIT_DIR"
mkdir -p out
mapfile -t ALL < <(ls "$WORK"/*_concept.png | sort)
idx=${SLURM_ARRAY_TASK_ID:-0}
img="${ALL[$idx]}"
base="$(basename "$img" _concept.png)"

fail=0
for seed in 7 21; do
  name="${base}_s${seed}"
  echo "== generating $name from $(basename "$img") (seed=$seed)"
  if ${IN/ env / env HY_OCT=512 HY_FACES=80000 HY_SEED=$seed } "$WORK/run_hy3d_v2.py" "$img" "out/${name}.glb" > "out/${name}.log" 2>&1; then
    grep -E "STAGE|WARN|DONE|FAILED" "out/${name}.log" || true
  else
    echo "MODEL FAILED: $name"
    tail -30 "out/${name}.log"
    fail=1
  fi
  [ -s "out/${name}.glb" ] || [ -s "out/${name}_shape.glb" ] || { echo "NO GLB for $name"; fail=1; }
done
echo "END $(date -u +%FT%TZ) fail=$fail"
exit $fail
