#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:-single-5090}"
SOLAR_BUILD_DIR="${SOLAR_BUILD_DIR:-/opt/llama-solar/build-solar}"
SOLAR_MODEL_DIR="${SOLAR_MODEL_DIR:-/mnt/d/models/solar-open2-250b/IQ1_M}"
SOLAR_PORT="${SOLAR_PORT:-8025}"
MODEL="$SOLAR_MODEL_DIR/Solar-Open2-250B-IQ1_M-00001-of-00002.gguf"

COMMON=(
  --model "$MODEL"
  --host 0.0.0.0 --port "$SOLAR_PORT"
  --alias solar-open2-250b-iq1
  --ctx-size 4096
  --flash-attn on
  --batch-size 512 --ubatch-size 512
  --parallel 1 --threads 16
  --no-mmap --jinja
)

case "$PROFILE" in
  single-5090)
    # llama.cpp enumerates CUDA0=5090 and CUDA1=5080 on this rig. This differs
    # from nvidia-smi's physical index display, so do not remap visibility.
    unset CUDA_VISIBLE_DEVICES
    exec "$SOLAR_BUILD_DIR/bin/llama-server" "${COMMON[@]}" \
      --device CUDA0 --n-gpu-layers 999 --n-cpu-moe 29
    ;;
  dual-layer-split)
    # Experimental: offload complete early layers to CPU and distribute the
    # remaining layers 1:2 across the 5080 and 5090. Do not combine this profile
    # with --n-cpu-moe until placement has been inspected.
    unset CUDA_VISIBLE_DEVICES
    exec "$SOLAR_BUILD_DIR/bin/llama-server" "${COMMON[@]}" \
      --split-mode layer --n-gpu-layers 36 --tensor-split 2,1
    ;;
  *)
    echo "Unknown profile: $PROFILE (use single-5090 or dual-layer-split)" >&2
    exit 2
    ;;
esac
