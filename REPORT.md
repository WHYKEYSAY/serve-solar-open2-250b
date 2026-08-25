# Solar Open 2 250B local-serving report

Date: 2026-08-24 (America/Toronto)

## Objective

Determine whether Solar Open 2 250B-A15B is practically usable on an RTX 5090
32 GB + RTX 5080 16 GB workstation with approximately 90 GB WSL memory, using
the hybrid CPU/GPU methods established in the Orion large-MoE campaign.

## Rig at start

| Component | Observed |
|---|---|
| GPU 0 | RTX 5080, 16,303 MiB |
| GPU 1 | RTX 5090, 32,607 MiB |
| NVIDIA driver | 610.88 |
| CUDA compiler | 12.9.41 |
| WSL memory | 88 GiB |
| WSL swap | 16 GiB |
| Existing service | Qwen3.5-122B-A10B, port 8001 |

The existing Qwen service occupied approximately 15.0 GiB and 32.0 GiB on the
two GPUs. It was left running during source preparation and compilation.

## Architecture and engine finding

Solar Open 2 uses the new `solar_open2` architecture: 48 layers arranged as
one softmax-attention layer plus three KDA linear-attention layers per group,
with 250B total and about 15B active parameters. Mainline llama.cpp does not
recognize it. The tested community patch is 46,500 bytes and touches 11 files,
including the model graph, conversion mapping, vocabulary termination, and
chat/tool parser.

Pinned inputs:

| Input | Value |
|---|---|
| llama.cpp commit | `6ea215d17` |
| patch SHA-256 | `d2906be2c00913dd6700c3c403f9d3f99fd9f8d79c05d03e8027e1c748afa538` |
| CUDA architecture | `120a` (CMake rewrites requested `120`) |

`git apply --check` completed successfully before applying the patch.

## Quant decision

| Quant | Published size | Role on this rig |
|---|---:|---|
| IQ1_M | 56 GiB | Smoke test; easiest fit, severe quality caveat |
| Q2_K | 89 GiB | Follow-up quality test with substantial RAM offload |
| IQ4_XS | 127 GiB | Too close to/exceeds practical combined-memory ceiling |

## Experiment results

Results will be appended after each reproducible run. Raw machine-readable
records are produced under `results/` and excluded from Git until curated.

| Run | Placement | Context | Load | Decode | Prefill | Outcome |
|---|---|---:|---:|---:|---:|---|
| Build | patched llama.cpp, sm_120a | — | — | — | — | success; server + CLI |
| Wrong single-GPU map | `CUDA_VISIBLE_DEVICES=1`, `CUDA0` | 4K | stopped | — | — | selected physical 5080; invalid profile |
| Wrong dual ratio | 38 GPU layers, split `1,2` | 4K | 3.5s | — | — | CUDA1 requested 28,463.93 MiB; OOM |

Build identification:

```text
version: 161 (6ea215d17)
built with GNU 12.2.0 for Linux x86_64
```

CMake accepted `120` and selected `120a`. NCCL was not installed, so the build
reported that multi-GPU performance may be suboptimal; this is recorded as a
test variable rather than treated as a build failure. The local Node.js version
was too old to regenerate the optional web UI, after which the build system
successfully fetched the prebuilt UI asset. This did not affect the server,
CLI, CUDA backend, or Solar model graph.

### Device-order finding

On this host, patched llama.cpp reports `CUDA0 = RTX 5090 (32 GB)` and
`CUDA1 = RTX 5080 (16 GB)`, while `nvidia-smi` displays the 5080 as index 0 and
the 5090 as index 1. Setting `CUDA_VISIBLE_DEVICES=1` therefore produced the
opposite of the intended placement in the first profile. The first dual profile
also used the ratio `1,2`, causing a 28,463.93 MiB allocation on the 16 GB card.
Both profiles were corrected to use llama.cpp's own order: no visibility remap,
`--device CUDA0` for the 5090-only run, and `--tensor-split 2,1` for dual GPU.

### Download transport note

The first 44.7 GB shard's initial HTTP/2 transfer was cancelled by the remote
Xet bridge after approximately 8.3 GB (`curl: (92) ... CANCEL`). The partial
file remained valid for byte-range continuation. The reproducible downloader
was changed to HTTP/1.1 with `--retry-all-errors` and 20 retries, then resumed
instead of restarting. The second shard was fetched concurrently with
`huggingface_hub`/`hf_xet` to reduce wall time.

Because the server advertises and correctly returns `206 Partial Content`, the
remaining first-shard range was split into eight exact byte ranges. Every range
is length-checked before ordered assembly. The original contiguous prefix and
all segments are retained until llama.cpp successfully validates and loads the
assembled GGUF; this makes the acceleration recoverable rather than destructive.

## Interpretation

Pending runtime measurements. A successful load alone will not establish that
IQ1_M is useful: output coherence, multilingual behavior, coding, reasoning,
and tool calling must be checked before keeping the model.
