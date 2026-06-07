#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMPILER_REPO = Path(os.environ.get(
    "POCKETCHEF_COMPILER_REPO",
    "/Users/allen/Documents/Codex/project/ml-graph-compiler-runtime",
))

TRACE_ARTIFACTS = {
    "lowered_graph": "cv_lowered_graph.json",
    "memory_plan": "cv_memory_plan.json",
    "execution_plan": "cv_execution_plan_v2.json",
    "static_schedule": "cv_static_schedule.json",
    "subgraph_partition": "cv_subgraph_partition.json",
    "cost_report": "cv_cost_report.json",
    "cost_based_planner": "cv_cost_based_planner.json",
    "runtime_replan": "cv_runtime_replan.json",
    "runtime_timeline": "cv_runtime_timeline.json",
}

PASS_PIPELINE = [
    {
        "name": "ShapeInferencePass",
        "decision": "infer tensor shapes for downstream lowering and memory planning",
        "metric_link": "enables byte/flop estimates and activation-size accounting",
    },
    {
        "name": "CanonicalizationPass",
        "decision": "normalize graph form before pattern matching",
        "metric_link": "makes fusion and lowering deterministic",
    },
    {
        "name": "DTypePropagationPass",
        "decision": "propagate float32 dtype through the CV graph",
        "metric_link": "feeds memory-size and bandwidth estimates",
    },
    {
        "name": "FusionCandidatePass",
        "decision": "rewrite Conv2D + BatchNorm + ReLU into FusedConvBatchNormReLU",
        "metric_link": "reduces launch count and intermediate tensor writes",
    },
    {
        "name": "MemoryPlanningPass",
        "decision": "reuse activation buffers with non-overlapping lifetimes",
        "metric_link": "reduces planned peak activation memory",
    },
    {
        "name": "BackendPlacementPass",
        "decision": "place high-intensity ops on Metal and simple shape ops on CPU",
        "metric_link": "trades backend launch/switch cost against compute and bandwidth",
    },
    {
        "name": "SchedulingPass",
        "decision": "build a static topological execution schedule",
        "metric_link": "produces execution order consumed by the lowered runtime plan",
    },
]


def sha256(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def run_pipeline(compiler_repo: Path, binary: Path):
    if not compiler_repo.exists():
        raise FileNotFoundError(f"compiler repo not found: {compiler_repo}")
    if not binary.exists():
        raise FileNotFoundError(
            f"compiler binary not found: {binary}. Build ml-graph-compiler-runtime first."
        )

    result = subprocess.run(
        [str(binary)],
        cwd=str(binary.parent),
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return result.stdout


def collect_artifacts(compiler_repo: Path, out_dir: Path):
    trace_dir = compiler_repo / "trace"
    out_dir.mkdir(parents=True, exist_ok=True)
    copied = {}
    for key, filename in TRACE_ARTIFACTS.items():
        src = trace_dir / filename
        dst = out_dir / filename
        if not src.exists():
            copied[key] = {
                "exists": False,
                "source_path": str(src),
                "artifact_path": str(dst),
            }
            continue
        shutil.copy2(src, dst)
        copied[key] = {
            "exists": True,
            "source_path": str(src),
            "artifact_path": str(dst),
            "sha256": sha256(dst),
            "bytes": dst.stat().st_size,
        }
    return copied


def summarize_metrics(out_dir: Path):
    memory_plan = load_json(out_dir / "cv_memory_plan.json", {})
    planner = load_json(out_dir / "cv_cost_based_planner.json", {})
    cost_report = load_json(out_dir / "cv_cost_report.json", [])
    lowered = load_json(out_dir / "cv_lowered_graph.json", [])

    naive = memory_plan.get("naive_float_elements")
    planned = memory_plan.get("planned_peak_float_elements")
    saved = memory_plan.get("saved_float_elements")
    candidates = planner_candidates(planner)
    chosen = next((candidate for candidate in candidates if candidate.get("chosen")), None)
    rejected = next((candidate for candidate in candidates if candidate.get("name") == "all_metal" and not candidate.get("chosen")), None)
    if rejected is None:
        rejected = next((candidate for candidate in candidates if not candidate.get("chosen")), None)
    fused_ops = [
        item for item in cost_report
        if item.get("fusion_note") or "Fused" in str(item.get("op_type", ""))
    ]

    return {
        "lowered_op_count": len(lowered),
        "fusion_count": len(fused_ops),
        "fusions": [
            {
                "op_name": item.get("op_name"),
                "op_type": item.get("op_type"),
                "note": item.get("fusion_note"),
            }
            for item in fused_ops
        ],
        "memory": {
            "naive_float_elements": naive,
            "planned_peak_float_elements": planned,
            "saved_float_elements": saved,
            "naive_mb_estimate": round(naive * 4 / 1_000_000, 3) if naive else None,
            "planned_peak_mb_estimate": round(planned * 4 / 1_000_000, 3) if planned else None,
            "saved_mb_estimate": round(saved * 4 / 1_000_000, 3) if saved else None,
            "reuse_events": memory_plan.get("reuse_events", []),
        },
        "planner": {
            "chosen_plan": chosen.get("name") if chosen else None,
            "chosen_estimated_latency_ms": chosen.get("total_latency_ms") if chosen else None,
            "comparison_plan": rejected.get("name") if rejected else None,
            "comparison_estimated_latency_ms": rejected.get("total_latency_ms") if rejected else None,
            "candidate_count": len(candidates),
        },
    }


def main():
    parser = argparse.ArgumentParser(
        description="Run ml-graph-compiler-runtime CV lowering/pass/optimization pipeline for PocketChef."
    )
    parser.add_argument("--compiler-repo", type=Path, default=DEFAULT_COMPILER_REPO)
    parser.add_argument("--binary", type=Path)
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=ROOT / "compiler_artifacts/generated",
    )
    args = parser.parse_args()

    compiler_repo = args.compiler_repo.resolve()
    binary = args.binary.resolve() if args.binary else compiler_repo / "build/run_cv_graph_demo"
    out_dir = args.out_dir.resolve()

    stdout = run_pipeline(compiler_repo, binary)
    stdout_path = out_dir / "compiler_pipeline_stdout.txt"
    out_dir.mkdir(parents=True, exist_ok=True)
    stdout_path.write_text(stdout, encoding="utf-8")

    copied = collect_artifacts(compiler_repo, out_dir)
    metrics = summarize_metrics(out_dir)

    manifest = {
        "artifact_type": "pocketchef_compiler_pipeline_manifest",
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "integration_level": "level_2_5_mac_side_compiler_pipeline",
        "truth_boundary": {
            "what_is_real": "PocketChef invokes ml-graph-compiler-runtime on the Mac and imports generated compiler trace artifacts.",
            "what_is_not_claimed": "The iPhone app does not live-compile the YOLO-Seg Core ML graph at runtime.",
        },
        "input_source": {
            "pocketchef_runtime_input": "iPhone snapshot + YOLO-Seg Core ML segmentation output",
            "compiler_pipeline_input": "CV graph abstraction in ml-graph-compiler-runtime/apps/run_cv_graph_demo.cpp",
            "model_family": "YOLO-Seg style CV graph: conv block + pooling/flatten/head + postprocess policy mapping",
        },
        "compiler_repo": {
            "name": "ml-graph-compiler-runtime",
            "path": str(compiler_repo),
            "binary": str(binary),
            "app_source": str(compiler_repo / "apps/run_cv_graph_demo.cpp"),
        },
        "lowering_and_optimization_passes": PASS_PIPELINE,
        "generated_artifacts": copied,
        "metric_impact": metrics,
        "app_mapping": {
            "mode": "Comp",
            "display_decision": "show compiler artifact decision summary",
            "execution_policy": "use compiler-lowered postprocess policy in PocketChef; headline claims come from this manifest and copied trace artifacts",
            "dashboard_row": "benchmark_reports/core_value_evidence.json rows[variant=Comp]",
        },
    }

    manifest_path = out_dir / "compiler_pipeline_manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    print(json.dumps({
        "wrote_manifest": str(manifest_path),
        "wrote_stdout": str(stdout_path),
        "artifact_count": sum(1 for item in copied.values() if item.get("exists")),
        "chosen_plan": metrics["planner"]["chosen_plan"],
        "saved_activation_mb_estimate": metrics["memory"]["saved_mb_estimate"],
    }, indent=2))


if __name__ == "__main__":
    main()
