# serve-solar-open2-250b

Reproducible experiments for serving **Upstage Solar Open 2 250B-A15B** on a
consumer 48 GB VRAM rig (RTX 5090 32 GB + RTX 5080 16 GB, 90 GB system RAM).

## Current status

- Solar Open 2 is not supported by upstream `llama.cpp` as of 2026-08-24.
- The community port from `prometheusAIR/Solar-Open2-250B-GGUF` applies cleanly
  to upstream commit `6ea215d17`.
- The patched CUDA `sm_120a` server and CLI build successfully on this rig.
- Model weights and generated logs are intentionally excluded from Git.

See [REPORT.md](REPORT.md) for measured results and failures. Runtime testing
begins after the two IQ1_M shards finish downloading.

## Reproduce

```bash
./scripts/build-patched-llama.sh
./scripts/download-iq1.sh

# Conservative first boot: RTX 5090 only, experts from 24 layers in RAM.
SOLAR_MODEL_DIR=/mnt/d/models/solar-open2-250b/IQ1_M \
  ./scripts/serve-iq1.sh single-5090

# In another shell:
python3 scripts/bench_decode.py --port 8025 --label solar-open2-iq1-single-5090
```

The first test uses IQ1_M only to validate architecture, CUDA kernels, chat
format, and tool parsing. It is **not** assumed to preserve production quality:
the quantizer reports substantially worse perplexity than Q6_K. Q2_K is the
next quality test if the smoke test succeeds.

## Important constraints

- The patch is third-party and is pinned by commit and SHA-256.
- `--no-mmap` is required when experts are CPU-offloaded.
- Do not use `-ub 2048`; the port documents a CUDA illegal-memory-access bug.
- `iq1_s`, `iq2_s`, and `iq3_s` kernels are unsafe on Blackwell in the tested
  upstream build. This repository uses the published `IQ1_M` artifact.
- The asymmetric 5090 + 5080 path is tested separately. The port author warns
  against combining `-ncmoe` with a smaller second GPU because late,
  expert-heavy layers can overflow it.

## Sources

- Base model: <https://huggingface.co/upstage/Solar-Open2-250B>
- GGUF, patch, and quant measurements:
  <https://huggingface.co/prometheusAIR/Solar-Open2-250B-GGUF>
- Upstream support request:
  <https://github.com/ggml-org/llama.cpp/issues/26115>
