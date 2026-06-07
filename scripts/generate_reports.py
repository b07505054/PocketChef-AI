#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    core_value = load_json(ROOT / "benchmark_reports/core_value_evidence.json", {})
    runtime = load_json(ROOT / "runtime_artifacts/runtime_benchmark_report.json", {})
    compression = load_json(ROOT / "compression_artifacts/model_compression_report.json", {})
    compiler = {
        "graph_ir": load_json(ROOT / "compiler_artifacts/cv_graph_ir.json", {}),
        "fusion": load_json(ROOT / "compiler_artifacts/cv_fusion_report.json", {}),
        "memory": load_json(ROOT / "compiler_artifacts/cv_memory_plan.json", {}),
        "execution_plan": load_json(ROOT / "compiler_artifacts/cv_execution_plan.json", {}),
        "cost": load_json(ROOT / "compiler_artifacts/cv_cost_report.json", {}),
    }

    report = {
        "artifact_type": "combined_benchmark_report",
        "evidence_type": "mixed_real_and_simulation",
        "core_value_evidence": core_value,
        "runtime": runtime,
        "compression": compression,
        "compiler": compiler,
        "summary": {
            "baseline_latency_ms": None,
            "runtime_optimized_latency_ms": None,
            "compiler_optimized_latency_ms": None,
            "compression_optimized_latency_ms": None,
            "combined_optimized_latency_ms": None,
            "model_size_reduction_percent": None,
            "fps_improvement": None,
            "memory_reduction_mb": compiler["memory"].get("estimated_savings_mb"),
        },
    }

    output = ROOT / "benchmark_reports/combined_benchmark_report.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"wrote": str(output)}, indent=2))


if __name__ == "__main__":
    main()
