#!/usr/bin/env python3
import argparse
import json
import statistics
import time
from pathlib import Path


def require_coremltools():
    try:
        import coremltools as ct
        import numpy as np
    except ImportError as exc:
        raise SystemExit(
            "Missing dependency. Install with:\n"
            "python3 -m pip install coremltools numpy"
        ) from exc
    return ct, np


def percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    values = sorted(values)
    index = round((pct / 100.0) * (len(values) - 1))
    return values[index]


def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark a Core ML model on the local Mac runtime.")
    parser.add_argument("--model", required=True)
    parser.add_argument("--runs", type=int, default=50)
    parser.add_argument("--warmup", type=int, default=10)
    parser.add_argument("--output", default="runtime_artifacts/runtime_benchmark_report.json")
    args = parser.parse_args()

    ct, np = require_coremltools()
    model_path = Path(args.model)
    if not model_path.exists():
        raise SystemExit(f"Model not found: {model_path}")

    model = ct.models.MLModel(str(model_path))
    spec = model.get_spec()
    input_desc = spec.description.input[0]
    input_name = input_desc.name

    shape = [1, 3, 640, 640]
    if input_desc.type.HasField("multiArrayType") and input_desc.type.multiArrayType.shape:
        shape = list(input_desc.type.multiArrayType.shape)

    sample = np.random.rand(*shape).astype(np.float32)
    payload = {input_name: sample}

    for _ in range(args.warmup):
        model.predict(payload)

    latencies = []
    for _ in range(args.runs):
        start = time.perf_counter()
        model.predict(payload)
        latencies.append((time.perf_counter() - start) * 1000)

    report = {
        "artifact_type": "runtime_benchmark_report",
        "evidence_type": "local_coremltools_runtime",
        "model": str(model_path),
        "runs": args.runs,
        "warmup": args.warmup,
        "latency_ms_avg": round(statistics.mean(latencies), 4),
        "latency_ms_p50": round(percentile(latencies, 50), 4),
        "latency_ms_p95": round(percentile(latencies, 95), 4),
        "latency_ms_p99": round(percentile(latencies, 99), 4),
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()

