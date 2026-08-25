#!/usr/bin/env bash
set -euo pipefail

SOLAR_MODEL_DIR="${SOLAR_MODEL_DIR:-/mnt/d/models/solar-open2-250b/IQ1_M}"
PARTS="${PARTS:-8}"
SHARD="Solar-Open2-250B-IQ1_M-00001-of-00002.gguf"
DESTINATION="$SOLAR_MODEL_DIR/$SHARD"
TOTAL_SIZE=44746120576
URL="https://huggingface.co/prometheusAIR/Solar-Open2-250B-GGUF/resolve/main/IQ1_M/$SHARD"

prefix_size="$(stat -c %s "$DESTINATION")"
if [[ "$prefix_size" -ge "$TOTAL_SIZE" ]]; then
  echo "Shard is already complete."
  exit 0
fi

remaining=$((TOTAL_SIZE - prefix_size))
chunk_size=$(((remaining + PARTS - 1) / PARTS))
segment_dir="${DESTINATION}.segments-${prefix_size}"
backup="${DESTINATION}.prefix-${prefix_size}.backup"
mkdir -p "$segment_dir"

pids=()
for index in $(seq 0 $((PARTS - 1))); do
  start=$((prefix_size + index * chunk_size))
  [[ "$start" -ge "$TOTAL_SIZE" ]] && break
  end=$((start + chunk_size - 1))
  [[ "$end" -ge "$TOTAL_SIZE" ]] && end=$((TOTAL_SIZE - 1))
  segment="$segment_dir/segment-$(printf '%02d' "$index")-${start}-${end}.bin"
  expected=$((end - start + 1))

  if [[ "$(stat -c %s "$segment" 2>/dev/null || printf 0)" == "$expected" ]]; then
    echo "Segment $index already complete."
    continue
  fi

  echo "Downloading segment $index: bytes $start-$end"
  curl --http1.1 -fL --retry 20 --retry-all-errors --retry-delay 3 \
    --range "$start-$end" "$URL" -o "$segment" \
    >"$segment.curl.log" 2>&1 &
  pids+=("$!")
done

failed=0
for pid in "${pids[@]}"; do
  wait "$pid" || failed=1
done
[[ "$failed" == 0 ]] || { echo "At least one range download failed." >&2; exit 1; }

for segment in "$segment_dir"/segment-*.bin; do
  range="${segment%.bin}"
  range="${range##*-}"
  # The end is the final dash-delimited field; start is the field before it.
  end="$range"
  without_end="${segment%-${end}.bin}"
  start="${without_end##*-}"
  expected=$((end - start + 1))
  actual="$(stat -c %s "$segment")"
  [[ "$actual" == "$expected" ]] || {
    echo "Bad segment size: $segment ($actual != $expected)" >&2
    exit 1
  }
done

cp --reflink=auto "$DESTINATION" "$backup"
for segment in "$segment_dir"/segment-*.bin; do
  dd if="$segment" of="$DESTINATION" bs=8M oflag=append conv=notrunc status=none
done

actual="$(stat -c %s "$DESTINATION")"
if [[ "$actual" != "$TOTAL_SIZE" ]]; then
  echo "Assembly size mismatch: $actual != $TOTAL_SIZE; prefix backup: $backup" >&2
  exit 1
fi

echo "Assembled and size-verified: $DESTINATION ($actual bytes)"
echo "Keeping prefix backup and segments until the GGUF load test succeeds."

