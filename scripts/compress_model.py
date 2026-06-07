#!/usr/bin/env python3
import argparse
import json
import shutil
from pathlib import Path


def file_or_dir_size_mb(path: Path) -> float:
    if not path.exists():
        return 0.0
    if path.is_file():
        return path.stat().st_size / (1024 * 1024)
    total = sum(p.stat().st_size for p in path.rglob("*") if p.is_file())
    return total / (1024 * 1024)


def main() -> None:
    parser = argparse.ArgumentParser(description="Create Core ML compression variants and report sizes.")
    parser.add_argument("--input", required=True, help="Input .mlpackage/.mlmodel path.")
    parser.add_argument("--output-dir", default="models")
    parser.add_argument("--report", default="compression_artifacts/model_compression_report.json")
    args = parser.parse_args()

    input_path = Path(args.input)
    output_dir = Path(args.output_dir)
    report_path = Path(args.report)
    output_dir.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    if not input_path.exists():
        raise SystemExit(f"Input model not found: {input_path}")

    source_stem = input_path.stem.removesuffix("_fp32")
    variants = [
        {
            "compression": "none",
            "stem": f"{source_stem}_fp32",
            "decision": "baseline uncompressed model",
            "status": "source_or_copied",
        },
        {
            "compression": "quantization",
            "stem": f"{source_stem}_int8",
            "decision": "INT8 quantization candidate",
            "status": "placeholder_copy_pending_real_quantization",
        },
        {
            "compression": "pruning",
            "stem": f"{source_stem}_pruned",
            "decision": "structured pruning candidate",
            "status": "placeholder_copy_pending_real_pruning",
        },
    ]

    rows = []
    for variant in variants:
        compression = variant["compression"]
        output = output_dir / f"{variant['stem']}{input_path.suffix}"
        if input_path.resolve() == output.resolve():
            pass
        elif input_path.is_dir():
            if output.exists():
                shutil.rmtree(output)
            shutil.copytree(input_path, output)
        else:
            shutil.copy2(input_path, output)

        rows.append(
            {
                "model": output.name,
                "compression": compression,
                "input_source": str(input_path),
                "decision_type": "model_compression_policy",
                "compression_decision": variant["decision"],
                "size_mb": round(file_or_dir_size_mb(output), 4),
                "metric_before": None,
                "metric_after": {
                    "model_size_mb": round(file_or_dir_size_mb(output), 4),
                    "latency_ms": None,
                    "mask_stability": None,
                },
                "proxy_accuracy": None,
                "status": variant["status"],
            }
        )

    report = {
        "artifact_type": "model_compression_report",
        "evidence_type": "policy_backed_placeholder",
        "source_model": str(input_path),
        "scope": "quantization_and_pruning_only",
        "note": "INT8 and pruned artifacts are copied placeholders until real quantization/pruning is generated; do not report speedup or accuracy improvement from them yet.",
        "variants": rows,
    }
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
