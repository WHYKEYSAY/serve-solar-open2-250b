#!/usr/bin/env python3
"""Measure native llama.cpp prompt/decode timing and capture GPU/RAM state."""

import argparse
import json
import subprocess
import time
import urllib.request
from pathlib import Path

PROMPTS = {
    "code": "Implement a complete, well-commented Python LRU cache with O(1) get and put, then explain its invariants.",
    "reasoning": "A warehouse has three robots with different rates. Explain a robust scheduling algorithm and analyze its complexity.",
    "multilingual": "请用中文解释混合专家模型的路由、负载均衡和CPU卸载之间的关系，并给出实际部署建议。",
}


def completion(port: int, prompt: str, n_predict: int) -> dict:
    body = json.dumps({
        "prompt": prompt,
        "n_predict": n_predict,
        "temperature": 0,
        "cache_prompt": False,
    }).encode()
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/completion",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=900) as response:
        return json.load(response)


def command_output(command: list[str]) -> str:
    try:
        return subprocess.check_output(command, text=True).strip()
    except Exception as error:
        return f"ERROR: {error}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8025)
    parser.add_argument("--label", default="solar-open2-iq1")
    parser.add_argument("--tokens", type=int, default=256)
    parser.add_argument("--out", default="results/benchmarks.jsonl")
    args = parser.parse_args()

    record = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "label": args.label,
        "port": args.port,
        "gpu_before": command_output([
            "nvidia-smi", "--query-gpu=index,name,memory.used,utilization.gpu",
            "--format=csv,noheader",
        ]),
        "memory_before": command_output(["free", "-h"]),
        "workloads": {},
    }

    for name, prompt in PROMPTS.items():
        response = completion(args.port, prompt, args.tokens)
        timings = response.get("timings", {})
        record["workloads"][name] = {
            "prompt_tok_s": timings.get("prompt_per_second"),
            "decode_tok_s": timings.get("predicted_per_second"),
            "predicted_n": timings.get("predicted_n"),
            "sample": response.get("content", "")[:500],
        }
        print(name, record["workloads"][name])

    record["gpu_after"] = command_output([
        "nvidia-smi", "--query-gpu=index,name,memory.used,utilization.gpu",
        "--format=csv,noheader",
    ])
    record["memory_after"] = command_output(["free", "-h"])

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()

