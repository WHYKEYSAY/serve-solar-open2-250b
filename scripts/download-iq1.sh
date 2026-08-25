#!/usr/bin/env bash
set -euo pipefail

SOLAR_MODEL_DIR="${SOLAR_MODEL_DIR:-/mnt/d/models/solar-open2-250b/IQ1_M}"
BASE_URL="https://huggingface.co/prometheusAIR/Solar-Open2-250B-GGUF/resolve/main/IQ1_M"

mkdir -p "$SOLAR_MODEL_DIR"
for shard in \
  Solar-Open2-250B-IQ1_M-00001-of-00002.gguf \
  Solar-Open2-250B-IQ1_M-00002-of-00002.gguf
do
  curl -fL --retry 5 --retry-delay 5 --continue-at - \
    "$BASE_URL/$shard" -o "$SOLAR_MODEL_DIR/$shard"
done

du -h "$SOLAR_MODEL_DIR"/*.gguf

