#!/usr/bin/env python3
"""Exercise the patched chat template, multilingual output, code, and tools."""

import argparse
import json
import time
import urllib.request
from pathlib import Path


CASES = {
    "chinese": {
        "messages": [
            {"role": "system", "content": "你是简洁、准确的技术助手。"},
            {"role": "user", "content": "只用三句话解释为什么MoE模型做CPU卸载时，RAM中的权重字节数会影响逐token速度。"},
        ],
    },
    "code": {
        "messages": [
            {"role": "system", "content": "Return correct, minimal code and tests."},
            {"role": "user", "content": "Write a Python merge_intervals function and exactly three assert tests."},
        ],
    },
    "tool": {
        "messages": [
            {"role": "user", "content": "What is the current weather in Toronto? Use the weather tool."},
        ],
        "tools": [{
            "type": "function",
            "function": {
                "name": "get_weather",
                "description": "Get current weather for a city",
                "parameters": {
                    "type": "object",
                    "properties": {"city": {"type": "string"}},
                    "required": ["city"],
                },
            },
        }],
        "tool_choice": "auto",
    },
}


def request_case(port: int, payload: dict) -> tuple[dict, float]:
    body = {
        "model": "solar-open2-250b-iq1",
        "temperature": 0,
        "max_tokens": 192,
        **payload,
    }
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
    )
    started = time.monotonic()
    with urllib.request.urlopen(request, timeout=900) as response:
        result = json.load(response)
    return result, time.monotonic() - started


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8025)
    parser.add_argument("--label", default="solar-open2-iq1")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    report = {"label": args.label, "cases": {}}
    for name, payload in CASES.items():
        response, elapsed = request_case(args.port, payload)
        choice = response["choices"][0]
        message = choice["message"]
        report["cases"][name] = {
            "elapsed_s": round(elapsed, 3),
            "finish_reason": choice.get("finish_reason"),
            "content": message.get("content"),
            "tool_calls": message.get("tool_calls"),
            "usage": response.get("usage"),
        }
        print(json.dumps({name: report["cases"][name]}, ensure_ascii=False, indent=2))

    output = Path(args.out)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

