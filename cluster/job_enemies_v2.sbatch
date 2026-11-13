#!/bin/bash
#SBATCH --job-name=joust-enemies-v2
#SBATCH --array=0-5
#SBATCH --output=slurm-%A_%a.out
#SBATCH --partition=gpu
#SBATCH --nodes=1
#SBATCH --gres=gpu:1
#SBATCH --time=01:00:00
# Hunyuan3D-2 octree-512 2-seed pass for the 3 enemy riders (side-profile concepts).
# Unpacks staged tarball into per-task /tmp to avoid NFS races across array tasks.
set -euo pipefail
echo "START $(hostname) $(date -u +%FT%TZ) task=${SLURM_ARRAY_TASK_ID:-0}"
nvidia-smi -L
module load apptainer

A=$HOME/apps/hy3d
export HF_HOME=$A/hf U2NET_HOME=$A/u2net
SIF="${CUDA_SIF:-cuda-12.4-devel.sif}"
X=$A/xlibs

[ -f "$A/.deps" ] || { echo "ERROR: ~/apps/hy3d missing"; exit 1; }
[ -f "$X/.ok" ] || { echo "ERROR: ~/apps/hy3d/xlibs missing"; exit 1; }

WORK="/tmp/joust_hy3d_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID:-0}"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK"
for t in "$SLURM_SUBMIT_DIR"/inputs/*.tar; do
  tar -xf "$t" -C "$WORK"
done

IN="apptainer exec --nv -B $A,$SLURM_SUBMIT_DIR,$WORK $SIF env CUDA_HOME=/usr/local/cuda TORCH_CUDA_ARCH_LIST=8.9 HF_HOME=$HF_HOME U2NET_HOME=$U2NET_HOME HY3D=$A/Hunyuan3D-2 PYTHONPATH=$A/Hunyuan3D-2/hy3dgen/texgen/differentiable_renderer LD_LIBRARY_PATH=/.singularity.d/libs:$X/root/usr/lib/x86_64-linux-gnu $A/venv/bin/python"

$IN -c "import torch, custom_rasterizer, mesh_processor, pymeshlab, cv2, rembg; assert torch.cuda.is_available(); print('env ok', torch.cuda.get_device_name(0))"

cd "$SLURM_SUBMIT_DIR"
mkdir -p out
mapfile -t ALL < <(ls "$WORK"/*_concept.png | sort)
SEEDS=(7 21)
idx=${SLURM_ARRAY_TASK_ID:-0}
img="${ALL[$((idx / 2))]}"
seed="${SEEDS[$((idx % 2))]}"
name="$(basename "$img" _concept.png)_s${seed}"

echo "== generating $name from $(basename "$img") (octree=512, seed=$seed)"
fail=0
if ${IN/ env / env HY_OCT=512 HY_FACES=100000 HY_SEED=$seed } "$WORK/run_hy3d_v2.py" "$img" "out/${name}.glb" > "out/${name}.log" 2>&1; then
  grep -E "STAGE|DONE|FAILED" "out/${name}.log" || true
else
  echo "MODEL FAILED: $name"
  tail -30 "out/${name}.log"
  fail=1
fi
[ -s "out/${name}.glb" ] || [ -s "out/${name}_shape.glb" ] || { echo "NO GLB for $name"; fail=1; }
echo "END $(date -u +%FT%TZ) fail=$fail"
exit $fail
