#!/usr/bin/env bash
set -euo pipefail

SOLAR_MODEL_DIR="${SOLAR_MODEL_DIR:-/mnt/d/models/solar-open2-250b/IQ1_M}"
BASE_URL="https://huggingface.co/prometheusAIR/Solar-Open2-250B-GGUF/resolve/main/IQ1_M"

mkdir -p "$SOLAR_MODEL_DIR"
declare -A EXPECTED_SIZE=(
  [Solar-Open2-250B-IQ1_M-00001-of-00002.gguf]=44746120576
  [Solar-Open2-250B-IQ1_M-00002-of-00002.gguf]=15704597056
)

for shard in "${!EXPECTED_SIZE[@]}"; do
  destination="$SOLAR_MODEL_DIR/$shard"
  current_size="$(stat -c %s "$destination" 2>/dev/null || printf 0)"
  if [[ "$current_size" == "${EXPECTED_SIZE[$shard]}" ]]; then
    echo "Already complete: $destination ($current_size bytes)"
    continue
  fi
  # HF's large Xet bridge occasionally cancels long-lived HTTP/2 streams.
  # Force HTTP/1.1 and retry transport errors while preserving the partial file.
  curl --http1.1 -fL --retry 20 --retry-all-errors --retry-delay 5 \
    --continue-at - \
    "$BASE_URL/$shard" -o "$destination"
  actual_size="$(stat -c %s "$destination")"
  if [[ "$actual_size" != "${EXPECTED_SIZE[$shard]}" ]]; then
    echo "Size mismatch for $destination: $actual_size != ${EXPECTED_SIZE[$shard]}" >&2
    exit 1
  fi
done

du -h "$SOLAR_MODEL_DIR"/*.gguf
