#!/usr/bin/env bash
set -euo pipefail

SOLAR_SRC_DIR="${SOLAR_SRC_DIR:-/opt/llama-solar}"
SOLAR_BUILD_DIR="${SOLAR_BUILD_DIR:-$SOLAR_SRC_DIR/build-solar}"
LLAMA_COMMIT="6ea215d17"
PATCH_URL="https://huggingface.co/prometheusAIR/Solar-Open2-250B-GGUF/resolve/main/solar_open2-llama.cpp.patch"
PATCH_SHA256="d2906be2c00913dd6700c3c403f9d3f99fd9f8d79c05d03e8027e1c748afa538"

if ! git -C "$SOLAR_SRC_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  git clone https://github.com/ggml-org/llama.cpp.git "$SOLAR_SRC_DIR"
fi

git -C "$SOLAR_SRC_DIR" fetch origin master
git -C "$SOLAR_SRC_DIR" checkout --detach "$LLAMA_COMMIT"

PATCH_FILE="$SOLAR_SRC_DIR/solar_open2-llama.cpp.patch"
curl -fL "$PATCH_URL" -o "$PATCH_FILE"
printf '%s  %s\n' "$PATCH_SHA256" "$PATCH_FILE" | sha256sum --check

if [[ -f "$SOLAR_SRC_DIR/src/models/solar-open2.cpp" ]] && \
   grep -q 'LLM_ARCH_SOLAR_OPEN2' "$SOLAR_SRC_DIR/src/llama-arch.h"; then
  echo "Solar patch is already present; keeping the working tree."
elif ! git -C "$SOLAR_SRC_DIR" diff --quiet || \
     [[ -n "$(git -C "$SOLAR_SRC_DIR" ls-files --others --exclude-standard)" ]]; then
  echo "Refusing to overwrite unrelated changes in $SOLAR_SRC_DIR" >&2
  exit 1
else
  git -C "$SOLAR_SRC_DIR" apply --check "$PATCH_FILE"
  git -C "$SOLAR_SRC_DIR" apply "$PATCH_FILE"
fi

cmake -S "$SOLAR_SRC_DIR" -B "$SOLAR_BUILD_DIR" \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=120 \
  -DCMAKE_BUILD_TYPE=Release
cmake --build "$SOLAR_BUILD_DIR" --target llama-server llama-cli -j "$(nproc)"

"$SOLAR_BUILD_DIR/bin/llama-server" --version
