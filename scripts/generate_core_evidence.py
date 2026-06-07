#!/usr/bin/env python3
import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
COMPILER_REPO = Path(os.environ.get(
    "POCKETCHEF_COMPILER_REPO",
    "/Users/allen/Documents/Codex/project/ml-graph-compiler-runtime",
))
RUNTIME_REPO = Path(os.environ.get(
    "POCKETCHEF_RUNTIME_REPO",
    "/Users/allen/Documents/Codex/project/heterogeneous-inference-runtime",
))


def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def planner_candidates(planner):
    if isinstance(planner, list):
        return planner
    if isinstance(planner, dict):
        return planner.get("candidates", [])
    return []


def sha256(path: Path):
    if not path.exists():
        return None
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source(path: Path, repo: Path, repo_name: str):
    return {
        "source_repo": repo_name,
        "source_path": str(path),
        "exists": path.exists(),
        "sha256": sha256(path),
    }


def runtime_metric(runtime_comparison, video_metrics):
    runtimes = runtime_comparison.get("runtimes", [])
    cpu = next((item for item in runtimes if item.get("runtime") == "ONNX Runtime"), {})
    video = video_metrics.get("metrics", {})
    backend = video_metrics.get("backend", {})
    return {
        "before": {
            "name": "external_cv_cpu_baseline",
            "latency_ms": cpu.get("latency_ms"),
            "runtime": cpu.get("runtime"),
            "backend": cpu.get("backend"),
        },
        "after": {
            "name": "external_cv_coreml_video_pipeline",
            "latency_ms": video.get("avg_latency_ms"),
            "fps": video.get("fps"),
            "runtime": backend.get("name"),
            "backend": backend.get("active_provider"),
        },
    }


def compiler_metric(memory_plan, cost_planner):
    naive_elements = memory_plan.get("naive_float_elements")
    planned_elements = memory_plan.get("planned_peak_float_elements")
    saved_elements = memory_plan.get("saved_float_elements")
    chosen = None
    rejected = None
    for candidate in planner_candidates(cost_planner):
        if candidate.get("chosen"):
            chosen = candidate
        elif candidate.get("name") == "all_metal":
            rejected = candidate

    return {
        "before": {
            "name": "naive_activation_plan",
            "peak_activation_mb_estimate": round(naive_elements * 4 / 1_000_000, 3) if naive_elements else None,
            "reference_plan": rejected.get("name") if rejected else None,
            "estimated_latency_ms": rejected.get("total_latency_ms") if rejected else None,
        },
        "after": {
            "name": "compiler_selected_plan",
            "peak_activation_mb_estimate": round(planned_elements * 4 / 1_000_000, 3) if planned_elements else None,
            "saved_activation_mb_estimate": round(saved_elements * 4 / 1_000_000, 3) if saved_elements else None,
            "reference_plan": chosen.get("name") if chosen else None,
            "estimated_latency_ms": chosen.get("total_latency_ms") if chosen else None,
        },
    }


def compiler_pipeline_metric(manifest):
    metric = manifest.get("metric_impact", {})
    memory = metric.get("memory", {})
    planner = metric.get("planner", {})
    return {
        "before": {
            "name": "pre_memory_planning_and_unselected_all_metal_plan",
            "peak_activation_mb_estimate": memory.get("naive_mb_estimate"),
            "reference_plan": planner.get("comparison_plan"),
            "estimated_latency_ms": planner.get("comparison_estimated_latency_ms"),
        },
        "after": {
            "name": "lowered_compiler_selected_plan",
            "peak_activation_mb_estimate": memory.get("planned_peak_mb_estimate"),
            "saved_activation_mb_estimate": memory.get("saved_mb_estimate"),
            "reference_plan": planner.get("chosen_plan"),
            "estimated_latency_ms": planner.get("chosen_estimated_latency_ms"),
            "lowered_op_count": metric.get("lowered_op_count"),
            "fusion_count": metric.get("fusion_count"),
        },
    }


def compression_metric(compression_report):
    variants = compression_report.get("variants", [])
    baseline = next((item for item in variants if item.get("compression") == "none"), {})
    quantized = next((item for item in variants if item.get("compression") == "quantization"), {})
    pruned = next((item for item in variants if item.get("compression") == "pruning"), {})
    return {
        "before": {
            "name": baseline.get("model"),
            "model_size_mb": baseline.get("size_mb"),
            "compression": baseline.get("compression"),
        },
        "after": {
            "quantization": {
                "name": quantized.get("model"),
                "model_size_mb": quantized.get("size_mb"),
                "status": quantized.get("status"),
            },
            "pruning": {
                "name": pruned.get("model"),
                "model_size_mb": pruned.get("size_mb"),
                "status": pruned.get("status"),
            },
        },
    }


def percent_delta(before, after):
    if before in (None, 0) or after is None:
        return None
    return round((before - after) / before * 100, 2)


def main():
    compiler_trace = COMPILER_REPO / "trace"
    runtime_results = RUNTIME_REPO / "results"

    compiler_paths = {
        "pipeline_manifest": ROOT / "compiler_artifacts/generated/compiler_pipeline_manifest.json",
        "lowered_graph": compiler_trace / "cv_lowered_graph.json",
        "memory_plan": compiler_trace / "cv_memory_plan.json",
        "execution_plan": compiler_trace / "cv_execution_plan_v2.json",
        "cost_report": compiler_trace / "cv_cost_report.json",
        "cost_planner": compiler_trace / "cv_cost_based_planner.json",
        "static_schedule": compiler_trace / "cv_static_schedule.json",
        "partition": compiler_trace / "cv_subgraph_partition.json",
    }
    runtime_paths = {
        "runtime_comparison": runtime_results / "runtime_comparison.json",
        "video_pipeline": runtime_results / "video_pipeline_metrics.json",
        "backend_validation": runtime_results / "backend_validation_summary.json",
        "operator_profile": runtime_results / "onnx_operator_profile_summary.json",
    }

    memory_plan = load_json(compiler_paths["memory_plan"], {})
    cost_planner = load_json(compiler_paths["cost_planner"], {})
    pipeline_manifest = load_json(compiler_paths["pipeline_manifest"], {})
    runtime_comparison = load_json(runtime_paths["runtime_comparison"], {})
    video_metrics = load_json(runtime_paths["video_pipeline"], {})
    compression_report = load_json(ROOT / "compression_artifacts/model_compression_report.json", {})

    runtime = runtime_metric(runtime_comparison, video_metrics)
    compiler = compiler_pipeline_metric(pipeline_manifest) if pipeline_manifest else compiler_metric(memory_plan, cost_planner)
    compression = compression_metric(compression_report)

    runtime_before = runtime["before"].get("latency_ms")
    runtime_after = runtime["after"].get("latency_ms")
    compiler_before = compiler["before"].get("estimated_latency_ms")
    compiler_after = compiler["after"].get("estimated_latency_ms")

    report = {
        "artifact_type": "pocketchef_core_value_evidence",
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "rule": [
            "Input source must be explicit.",
            "Compiler/runtime decision must be explicit.",
            "Execution or serving metric impact must be explicit.",
        ],
        "scope": {
            "primary_repos": [
                "ml-graph-compiler-runtime",
                "heterogeneous-inference-runtime",
            ],
            "excluded_from_main_plan": [
                "inference-validation-platform",
                "mini-llm-serving-runtime-demo",
            ],
            "exclusion_reason": "Not part of the current PocketChef execution path unless validating or extending an existing measured metric.",
        },
        "source_artifacts": {
            "compiler": {
                key: source(path, COMPILER_REPO, "ml-graph-compiler-runtime")
                for key, path in compiler_paths.items()
            },
            "runtime": {
                key: source(path, RUNTIME_REPO, "heterogeneous-inference-runtime")
                for key, path in runtime_paths.items()
            },
        },
        "rows": [
            {
                "variant": "Base",
                "input_source": "PocketChef iPhone camera snapshot + YOLO-Seg FP32 Core ML model output",
                "decision_type": "baseline_runtime_path",
                "decision_artifact": "PocketChef-AI iOS app mode=Baseline",
                "compiler_or_runtime_decision": "Use default Vision/Core ML execution path with no cross-repo optimization claim.",
                "metric_before": None,
                "metric_after": {
                    "status": "pending_real_iphone_export",
                    "metrics": ["p50_latency_ms", "p95_latency_ms", "fps", "mask_latency_ms"],
                },
                "metric_impact": "Baseline row defines the reference; no improvement claim.",
                "source_repo": "PocketChef-AI",
                "evidence_type": "app_measurement_pending",
            },
            {
                "variant": "Run",
                "input_source": "External CV runtime benchmark input from heterogeneous-inference-runtime; same-class CV inference workload, not yet PocketChef YOLO-Seg iPhone export.",
                "decision_type": "runtime_backend_policy",
                "decision_artifact": str(runtime_paths["video_pipeline"]),
                "compiler_or_runtime_decision": "Select CoreMLExecutionProvider video pipeline over CPU-only external CV baseline.",
                "metric_before": runtime["before"],
                "metric_after": runtime["after"],
                "metric_impact": {
                    "latency_reduction_percent": percent_delta(runtime_before, runtime_after),
                    "note": "External CV runtime evidence; replace with PocketChef YOLO-Seg iPhone benchmark when exported.",
                },
                "source_repo": "heterogeneous-inference-runtime",
                "evidence_type": "external_cv_runtime_evidence",
            },
            {
                "variant": "Comp",
                "input_source": pipeline_manifest.get("input_source", {}).get("compiler_pipeline_input", "CV graph abstraction from ml-graph-compiler-runtime trace: fused conv block, pool/flatten, linear, memory lifetimes."),
                "decision_type": "compiler_lowering_pass_optimization_pipeline",
                "decision_artifact": str(compiler_paths["pipeline_manifest"] if pipeline_manifest else compiler_paths["cost_planner"]),
                "compiler_or_runtime_decision": "Run ShapeInference, Canonicalization, DTypePropagation, FusionCandidate, MemoryPlanning, BackendPlacement, and Scheduling; lower graph into execution artifacts.",
                "metric_before": compiler["before"],
                "metric_after": compiler["after"],
                "metric_impact": {
                    "estimated_latency_reduction_percent": percent_delta(compiler_before, compiler_after),
                    "estimated_memory_reduction_mb": compiler["after"].get("saved_activation_mb_estimate"),
                    "lowering_and_optimization_passes": [item.get("name") for item in pipeline_manifest.get("lowering_and_optimization_passes", [])] if pipeline_manifest else [],
                    "note": "Compiler-estimated metric impact from a PocketChef-triggered ml-graph-compiler-runtime pipeline run.",
                },
                "source_repo": "ml-graph-compiler-runtime",
                "evidence_type": "compiler_pipeline_artifact_estimate" if pipeline_manifest else "compiler_artifact_estimate",
            },
            {
                "variant": "Zip",
                "input_source": "YOLO-Seg Core ML compiled model family from PocketChef-AI/models.",
                "decision_type": "model_compression_policy",
                "decision_artifact": "PocketChef-AI/compression_artifacts/model_compression_report.json",
                "compiler_or_runtime_decision": "Zip mode selects quantization and pruning candidates before FP32 fallback; speedup/accuracy claims remain gated until real compression is generated.",
                "metric_before": compression["before"],
                "metric_after": compression["after"],
                "metric_impact": {
                    "status": compression_report.get("evidence_type"),
                    "note": compression_report.get("note"),
                },
                "source_repo": "PocketChef-AI",
                "evidence_type": "policy_backed_model_compression",
            },
            {
                "variant": "All",
                "input_source": "Best measured PocketChef model + compiler decision artifact + runtime policy artifact.",
                "decision_type": "combined_path",
                "decision_artifact": "benchmark_reports/core_value_evidence.json",
                "compiler_or_runtime_decision": "Combine only decisions that already answer input, decision, and metric impact.",
                "metric_before": None,
                "metric_after": {
                    "status": "pending_end_to_end_measurement",
                    "required_inputs": ["Base real iPhone metrics", "Run PocketChef runtime metrics", "Comp measured or clearly simulated compiler metric", "Zip measured compression metric"],
                },
                "metric_impact": "No headline combined number until end-to-end PocketChef measurement exists.",
                "source_repo": "PocketChef-AI",
                "evidence_type": "rollup_pending",
            },
        ],
    }

    out = ROOT / "benchmark_reports/core_value_evidence.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps({"wrote": str(out)}, indent=2))


if __name__ == "__main__":
    main()
