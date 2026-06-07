#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_COMPILER_ARTIFACTS = Path(os.environ.get(
    "POCKETCHEF_LLM_COMPILER_ARTIFACTS",
    "/Users/allen/Documents/Codex/project/ml-graph-compiler-runtime/artifacts/apple_demo",
))
DEFAULT_RUNTIME_ARTIFACTS = Path(os.environ.get(
    "POCKETCHEF_LLM_RUNTIME_ARTIFACTS",
    "/Users/allen/Documents/Codex/project/heterogeneous-inference-runtime/results/llm_runtime_artifacts",
))

COMPILER_FILES = {
    "artifact_provenance": "artifact_provenance.json",
    "llm_graph_ir": "llm_graph_ir.json",
    "serving_execution_plan": "serving_execution_plan.json",
    "serving_framework_contract": "serving_framework_contract.json",
    "kv_cache_plan": "kv_cache_plan.json",
    "scheduling_plan": "scheduling_plan.json",
    "memory_plan": "memory_plan.json",
    "memory_timeline": "memory_timeline.json",
    "validation_manifest": "validation_manifest.json",
}

RUNTIME_FILES = {
    "manifest": "manifest.json",
    "prefill_decode_benchmark": "prefill_decode_benchmark.json",
    "kv_cache_trace": "kv_cache_trace.json",
    "scheduler_decision_report": "scheduler_decision_report.json",
    "scheduler_trace": "scheduler_trace.json",
    "serving_framework_report": "serving_framework_report.json",
    "runtime_profile": "runtime_profile.json",
    "serving_trace": "serving_trace.json",
    "backend_trace": "backend_trace.json",
    "plan_benchmark_results": "plan_benchmark_results.json",
    "cold_start_report": "cold_start_report.json",
    "real_llama_profile": "real_llama_profile.json",
    "vllm_trace_adapter_report": "vllm_trace_adapter_report.json",
    "sglang_trace_adapter_report": "sglang_trace_adapter_report.json",
    "technology_gate_audit": "technology_gate_audit.json",
}


def load_json(path: Path, fallback):
    if not path.exists():
        return fallback
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def copy_artifacts(source_dir: Path, out_dir: Path, files: dict[str, str], namespace: str):
    copied = {}
    namespace_dir = out_dir / namespace
    namespace_dir.mkdir(parents=True, exist_ok=True)
    for key, filename in files.items():
        src = source_dir / filename
        dst = namespace_dir / filename
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


def selected_policy(report):
    if not isinstance(report, dict):
        return {}
    selected = report.get("selected_policy")
    for policy in report.get("policies", []):
        if policy.get("policy") == selected:
            return policy
    return {}


def baseline_policy(report):
    for policy in report.get("policies", []):
        if policy.get("policy") == "fcfs_fixed_batch":
            return policy
    return {}


def pct_improvement(before, after):
    if before in (None, 0) or after is None:
        return None
    return round((before - after) / before * 100, 2)


def build_evidence(out_dir: Path, copied_compiler, copied_runtime):
    compiler_dir = out_dir / "compiler"
    runtime_dir = out_dir / "runtime"

    kv_plan = load_json(compiler_dir / "kv_cache_plan.json", {})
    serving_plan = load_json(compiler_dir / "serving_execution_plan.json", {})
    contract = load_json(compiler_dir / "serving_framework_contract.json", {})
    prefill_decode = load_json(runtime_dir / "prefill_decode_benchmark.json", {})
    scheduler_report = load_json(runtime_dir / "scheduler_decision_report.json", {})
    serving_report = load_json(runtime_dir / "serving_framework_report.json", {})
    runtime_profile = load_json(runtime_dir / "runtime_profile.json", {})
    validation = load_json(compiler_dir / "validation_manifest.json", {})

    baseline = baseline_policy(scheduler_report)
    optimized = selected_policy(scheduler_report)
    serving_metrics = serving_report.get("metrics", {})

    evidence = {
        "artifact_type": "pocketchef_llm_serving_evidence",
        "schema_version": 1,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "replaces_repo": {
            "name": "mini-llm-serving-runtime-demo",
            "reason": "PocketChef now imports compiler/runtime LLM serving artifacts directly from the primary systems repos.",
        },
        "truth_boundary": {
            "real": [
                "PocketChef iOS app asks a real local Ollama model and measures TTFT/total/tokens-per-second.",
                "PocketChef imports LLM serving compiler/runtime artifacts from ml-graph-compiler-runtime and heterogeneous-inference-runtime.",
            ],
            "not_claimed": [
                "PocketChef does not run vLLM, SGLang, Triton, or TensorRT directly.",
                "PocketChef does not yet run a live multi-request LLM scheduler inside the iPhone app.",
            ],
        },
        "input_source": {
            "app_input": "selected YOLO-Seg ingredient context + nutrition estimate + user typed question",
            "compiler_input": "tiny-gpt LLM serving graph/contract from ml-graph-compiler-runtime apple_demo artifacts",
            "runtime_input": "synthetic LLM-shaped prefill/decode workload from heterogeneous-inference-runtime",
        },
        "decision_chain": [
            {
                "stage": "prompt_context",
                "decision": "Base uses full context; Comp/All lower prompt into compact structured visual facts.",
                "artifact": "ios/PocketChefAI/PocketChefAI/OllamaClient.swift",
                "metric": "prompt tokens, TTFT, total latency",
            },
            {
                "stage": "serving_execution_plan",
                "decision": serving_plan.get("runtime_contract", {}).get("scheduler_plan", "prefill/decode split with KV contract"),
                "artifact": "llm_artifacts/serving/compiler/serving_execution_plan.json",
                "metric": serving_plan.get("runtime_contract", {}).get("metrics_targets", []),
            },
            {
                "stage": "kv_cache_policy",
                "decision": {
                    "kv_cache": kv_plan.get("allocation_strategy"),
                    "block_size_tokens": kv_plan.get("block_size_tokens"),
                    "prefix_cache_enabled": kv_plan.get("prefix_cache_enabled"),
                    "eviction_policy": kv_plan.get("eviction_policy"),
                    "admission_policy": kv_plan.get("admission_policy"),
                },
                "artifact": "llm_artifacts/serving/compiler/kv_cache_plan.json",
                "metric": kv_plan.get("prefix_cache_policy", {}).get("runtime_metrics", []),
            },
            {
                "stage": "runtime_scheduler",
                "decision": scheduler_report.get("selected_policy"),
                "artifact": "llm_artifacts/serving/runtime/scheduler_decision_report.json",
                "metric": scheduler_report.get("improvement", {}),
            },
            {
                "stage": "serving_framework_positioning",
                "decision": serving_report.get("selected_framework_style"),
                "artifact": "llm_artifacts/serving/runtime/serving_framework_report.json",
                "metric": serving_report.get("metrics", {}),
            },
        ],
        "metric_summary": {
            "ollama_live_app_metrics": "Measured in app after each Ask LLM request; see llm_artifacts/pocketchef_llm_benchmark_report.json schema and copied single-run JSON from the app.",
            "prefill_latency_ms": prefill_decode.get("prefill_latency_ms"),
            "avg_decode_latency_ms": prefill_decode.get("avg_decode_latency_ms"),
            "p95_decode_latency_ms": prefill_decode.get("p95_decode_latency_ms"),
            "tokens_per_second": prefill_decode.get("tokens_per_second") or serving_metrics.get("throughput_tokens_per_s"),
            "scheduler_before": {
                "policy": baseline.get("policy"),
                "p95_latency_ms": baseline.get("p95_latency_ms"),
                "tokens_per_second": baseline.get("tokens_per_second"),
                "avg_decode_batch_size": baseline.get("avg_decode_batch_size"),
                "peak_kv_cache_mb": baseline.get("peak_kv_cache_mb"),
            },
            "scheduler_after": {
                "policy": optimized.get("policy"),
                "p95_latency_ms": optimized.get("p95_latency_ms"),
                "tokens_per_second": optimized.get("tokens_per_second"),
                "avg_decode_batch_size": optimized.get("avg_decode_batch_size"),
                "peak_kv_cache_mb": optimized.get("peak_kv_cache_mb"),
            },
            "scheduler_improvement": {
                "p95_latency_reduction_percent": pct_improvement(baseline.get("p95_latency_ms"), optimized.get("p95_latency_ms")),
                "tokens_per_second_delta": scheduler_report.get("improvement", {}).get("tokens_per_second_delta"),
                "decode_batch_efficiency_delta": scheduler_report.get("improvement", {}).get("decode_batch_efficiency_delta"),
            },
            "serving_framework_metrics": serving_metrics,
            "runtime_profile": runtime_profile,
        },
        "validation": {
            "source": "ml-graph-compiler-runtime/apple_demo validation manifest plus runtime artifacts",
            "manifest": validation,
            "acceptance": [
                "App LLM answer must show TTFT, total latency, and tokens/sec.",
                "Serving evidence must include prefill/decode, scheduler policy, KV cache policy, and metric impact.",
                "README must distinguish real Ollama app serving from imported/simulated multi-request serving artifacts.",
            ],
        },
        "source_artifacts": {
            "compiler": copied_compiler,
            "runtime": copied_runtime,
        },
        "framework_targets": contract.get("framework_targets", {}),
    }

    out = out_dir / "llm_serving_evidence.json"
    out.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    return evidence, out


def main():
    parser = argparse.ArgumentParser(
        description="Import LLM serving compiler/runtime evidence into PocketChef."
    )
    parser.add_argument("--compiler-artifacts", type=Path, default=DEFAULT_COMPILER_ARTIFACTS)
    parser.add_argument("--runtime-artifacts", type=Path, default=DEFAULT_RUNTIME_ARTIFACTS)
    parser.add_argument("--out-dir", type=Path, default=ROOT / "llm_artifacts/serving")
    args = parser.parse_args()

    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    copied_compiler = copy_artifacts(args.compiler_artifacts.resolve(), out_dir, COMPILER_FILES, "compiler")
    copied_runtime = copy_artifacts(args.runtime_artifacts.resolve(), out_dir, RUNTIME_FILES, "runtime")
    evidence, evidence_path = build_evidence(out_dir, copied_compiler, copied_runtime)

    print(json.dumps({
        "wrote": str(evidence_path),
        "compiler_artifacts": sum(1 for item in copied_compiler.values() if item.get("exists")),
        "runtime_artifacts": sum(1 for item in copied_runtime.values() if item.get("exists")),
        "selected_scheduler": evidence["metric_summary"]["scheduler_after"]["policy"],
        "tokens_per_second": evidence["metric_summary"]["tokens_per_second"],
    }, indent=2))


if __name__ == "__main__":
    main()
