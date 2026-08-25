#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROD_SERVICE="${PROD_SERVICE:-keying-122b.service}"
PROD_PORT="${PROD_PORT:-8001}"
PROD_ALIAS="${PROD_ALIAS:-keying-deep}"
SOLAR_PORT="${SOLAR_PORT:-8025}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RESULT_DIR="$REPO_DIR/results/$RUN_ID"
SERVER_PID=""

mkdir -p "$RESULT_DIR"

log() {
  printf '%s  %s\n' "$(date -u +%FT%TZ)" "$*" | tee -a "$RESULT_DIR/experiment.log"
}

stop_solar() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    log "Stopping Solar server pid=$SERVER_PID"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  SERVER_PID=""
}

restore_production() {
  stop_solar
  log "Restoring $PROD_SERVICE"
  systemctl --user reset-failed "$PROD_SERVICE" 2>/dev/null || true
  systemctl --user start "$PROD_SERVICE"
  for _ in $(seq 1 60); do
    if curl -fsS --max-time 5 "http://127.0.0.1:$PROD_PORT/v1/models" | grep -q "$PROD_ALIAS"; then
      log "Production model healthy on :$PROD_PORT"
      return
    fi
    sleep 10
  done
  log "WARNING: production model did not become healthy within 600 seconds"
}

trap restore_production EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

log "Capturing pre-test state"
nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu \
  --format=csv,noheader | tee "$RESULT_DIR/gpu-before.csv"
free -h | tee "$RESULT_DIR/memory-before.txt"
/opt/llama-solar/build-solar/bin/llama-server --version 2>&1 \
  | tee "$RESULT_DIR/server-version.txt"

log "Stopping $PROD_SERVICE once for the Solar test sequence"
systemctl --user stop "$PROD_SERVICE"
for _ in $(seq 1 30); do
  used="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits \
    | awk '{ total += $1 } END { print total + 0 }')"
  log "GPU drain check: ${used} MiB"
  [[ "$used" -lt 4000 ]] && break
  sleep 5
done

for profile in "${@:-single-5090}"; do
  profile_log="$RESULT_DIR/server-$profile.log"
  log "Starting Solar profile=$profile"
  SOLAR_PORT="$SOLAR_PORT" "$REPO_DIR/scripts/serve-iq1.sh" "$profile" \
    >"$profile_log" 2>&1 &
  SERVER_PID=$!

  healthy=0
  for attempt in $(seq 1 150); do
    if curl -fsS --max-time 5 "http://127.0.0.1:$SOLAR_PORT/v1/models" \
      | grep -q 'solar-open2-250b-iq1'; then
      healthy=1
      break
    fi
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      log "Solar server exited during load; see $profile_log"
      break
    fi
    if (( attempt % 6 == 0 )); then
      gpu_used="$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits \
        | paste -sd, -)"
      ram_available="$(free -h | awk '/Mem:/{print $7}')"
      log "Loading ${attempt}0s: GPU MiB=$gpu_used, RAM available=$ram_available"
    fi
    sleep 10
  done

  if [[ "$healthy" == 1 ]]; then
    log "Solar profile=$profile healthy; running benchmark"
    python3 "$REPO_DIR/scripts/bench_decode.py" \
      --port "$SOLAR_PORT" --label "solar-open2-iq1-$profile" \
      --out "$RESULT_DIR/benchmarks.jsonl" \
      | tee "$RESULT_DIR/bench-$profile.txt"
    python3 "$REPO_DIR/scripts/chat_smoke.py" \
      --port "$SOLAR_PORT" --label "solar-open2-iq1-$profile" \
      --out "$RESULT_DIR/chat-$profile.json" \
      | tee "$RESULT_DIR/chat-$profile.txt"
  else
    log "Solar profile=$profile FAILED to become healthy"
  fi

  nvidia-smi --query-gpu=index,name,memory.used,utilization.gpu \
    --format=csv,noheader | tee "$RESULT_DIR/gpu-$profile.csv"
  free -h | tee "$RESULT_DIR/memory-$profile.txt"
  stop_solar
  sleep 5
done

log "Solar test sequence complete"
