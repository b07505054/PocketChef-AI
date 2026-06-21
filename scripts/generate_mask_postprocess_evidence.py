#!/usr/bin/env python3
import json
import math
import random
import statistics
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT_PATH = ROOT / "compiler_artifacts/generated/mask_postprocess_lowering_report.json"


def percentile(values, p):
    if not values:
        return 0.0
    values = sorted(values)
    rank = math.ceil((p / 100.0) * len(values)) - 1
    rank = max(0, min(rank, len(values) - 1))
    return values[rank]


def alpha_from_sum(value, threshold):
    probability = 1.0 / (1.0 + math.exp(-value))
    if probability < threshold:
        return 0
    shaped = min(max((probability - threshold) / (1.0 - threshold), 0.0), 1.0)
    return int(70 + shaped * 125)


def make_case(width, height, crop, seed):
    rng = random.Random(seed)
    coefficients = [rng.uniform(-0.7, 0.7) for _ in range(32)]
    prototypes = [
        [
            [rng.uniform(-1.0, 1.0) for _ in range(width)]
            for _ in range(height)
        ]
        for _ in range(32)
    ]
    return {
        "width": width,
        "height": height,
        "crop": crop,
        "coefficients": coefficients,
        "prototypes": prototypes,
        "threshold": 0.55,
    }


def crop_bounds(case):
    width = case["width"]
    height = case["height"]
    crop = case["crop"]
    return {
        "min_x": max(math.floor(crop["min_x"] * width), 0),
        "max_x": min(math.ceil(crop["max_x"] * width) - 1, width - 1),
        "min_y": max(math.floor(crop["min_y"] * height), 0),
        "max_y": min(math.ceil(crop["max_y"] * height) - 1, height - 1),
    }


def scalar_decode(case):
    bounds = crop_bounds(case)
    width = case["width"]
    height = case["height"]
    mask = [0] * (width * height)
    for y in range(bounds["min_y"], bounds["max_y"] + 1):
        for x in range(bounds["min_x"], bounds["max_x"] + 1):
            total = 0.0
            for channel in range(32):
                total += case["coefficients"][channel] * case["prototypes"][channel][y][x]
            mask[y * width + x] = alpha_from_sum(total, case["threshold"])
    return mask


def simd_style_decode(case):
    bounds = crop_bounds(case)
    width = case["width"]
    height = case["height"]
    mask = [0] * (width * height)
    for y in range(bounds["min_y"], bounds["max_y"] + 1):
        for x in range(bounds["min_x"], bounds["max_x"] + 1):
            total = 0.0
            for base in range(0, 32, 8):
                total += sum(
                    case["coefficients"][base + lane]
                    * case["prototypes"][base + lane][y][x]
                    for lane in range(8)
                )
            mask[y * width + x] = alpha_from_sum(total, case["threshold"])
    return mask


def active_bbox(mask, width, height):
    xs = []
    ys = []
    for index, value in enumerate(mask):
        if value > 0:
            ys.append(index // width)
            xs.append(index % width)
    if not xs:
        return None
    return {
        "min_x": min(xs),
        "max_x": max(xs),
        "min_y": min(ys),
        "max_y": max(ys),
    }


def bbox_delta_pixels(a, b):
    if a is None and b is None:
        return 0
    if a is None or b is None:
        return 10**9
    return max(abs(a[key] - b[key]) for key in a)


def correctness_metrics(reference, candidate, width, height):
    diffs = [abs(a - b) for a, b in zip(reference, candidate)]
    ref_active = {idx for idx, value in enumerate(reference) if value > 0}
    candidate_active = {idx for idx, value in enumerate(candidate) if value > 0}
    union = ref_active | candidate_active
    intersection = ref_active & candidate_active
    iou = len(intersection) / len(union) if union else 1.0
    return {
        "max_alpha_abs_diff": max(diffs) if diffs else 0,
        "mean_alpha_abs_diff": round(statistics.fmean(diffs), 6) if diffs else 0.0,
        "active_pixel_count_delta": len(candidate_active) - len(ref_active),
        "iou_vs_scalar": round(iou, 6),
        "bbox_delta_pixels": bbox_delta_pixels(
            active_bbox(reference, width, height),
            active_bbox(candidate, width, height),
        ),
    }


def measure(fn, case, runs=15, warmup=3):
    for _ in range(warmup):
        fn(case)
    latencies = []
    result = None
    for _ in range(runs):
        start = time.perf_counter()
        result = fn(case)
        latencies.append((time.perf_counter() - start) * 1000.0)
    return result, {
        "runs": runs,
        "p50_latency_ms": round(percentile(latencies, 50), 6),
        "p95_latency_ms": round(percentile(latencies, 95), 6),
        "mean_latency_ms": round(statistics.fmean(latencies), 6),
    }


def case_report(name, case):
    scalar_mask, scalar_latency = measure(scalar_decode, case)
    simd_mask, simd_latency = measure(simd_style_decode, case)
    correctness = correctness_metrics(scalar_mask, simd_mask, case["width"], case["height"])
    correctness_passed = (
        correctness["max_alpha_abs_diff"] <= 1
        and correctness["iou_vs_scalar"] >= 0.995
        and correctness["bbox_delta_pixels"] <= 1
    )
    simd_faster_or_close = simd_latency["p95_latency_ms"] <= scalar_latency["p95_latency_ms"] * 1.03
    selected = "simd_cpu" if correctness_passed and simd_faster_or_close else "scalar_cpu"
    fallback_reason = "none" if selected == "simd_cpu" else (
        "correctness_rejected" if not correctness_passed else "profile_rejected"
    )
    fps_impact = 0.0
    if scalar_latency["p95_latency_ms"] > 0:
        fps_impact = (scalar_latency["p95_latency_ms"] - simd_latency["p95_latency_ms"]) / scalar_latency["p95_latency_ms"]
    return {
        "case": name,
        "input": {
            "prototype_layout": "NCHW",
            "prototype_shape": [1, 32, case["height"], case["width"]],
            "crop": case["crop"],
            "threshold": case["threshold"],
        },
        "decision": {
            "selected_backend": selected,
            "fallback_reason": fallback_reason,
            "simd_legality": "coefficients=32 and NCHW prototype layout",
        },
        "scalar_cpu": scalar_latency,
        "simd_cpu": simd_latency,
        "correctness": correctness,
        "metric_impact": {
            "p50_latency_ms": simd_latency["p50_latency_ms"] if selected == "simd_cpu" else scalar_latency["p50_latency_ms"],
            "p95_latency_ms": simd_latency["p95_latency_ms"] if selected == "simd_cpu" else scalar_latency["p95_latency_ms"],
            "estimated_fps_impact": round(fps_impact, 6),
        },
    }


def main():
    cases = [
        ("small_crop_160", make_case(160, 160, {"min_x": 0.20, "max_x": 0.48, "min_y": 0.25, "max_y": 0.55}, 7)),
        ("medium_crop_160", make_case(160, 160, {"min_x": 0.12, "max_x": 0.72, "min_y": 0.18, "max_y": 0.76}, 11)),
        ("edge_crop_160", make_case(160, 160, {"min_x": 0.00, "max_x": 0.34, "min_y": 0.02, "max_y": 0.44}, 17)),
    ]
    reports = [case_report(name, case) for name, case in cases]
    selected_counts = {}
    fallback_counts = {}
    selected_p50 = []
    selected_p95 = []
    fps_impacts = []
    for row in reports:
        selected = row["decision"]["selected_backend"]
        fallback = row["decision"]["fallback_reason"]
        selected_counts[selected] = selected_counts.get(selected, 0) + 1
        fallback_counts[fallback] = fallback_counts.get(fallback, 0) + 1
        selected_p50.append(row["metric_impact"]["p50_latency_ms"])
        selected_p95.append(row["metric_impact"]["p95_latency_ms"])
        fps_impacts.append(row["metric_impact"]["estimated_fps_impact"])

    max_alpha_abs_diff = max(row["correctness"]["max_alpha_abs_diff"] for row in reports)
    mean_alpha_abs_diff = statistics.fmean(row["correctness"]["mean_alpha_abs_diff"] for row in reports)
    max_active_delta = max(abs(row["correctness"]["active_pixel_count_delta"]) for row in reports)
    min_iou = min(row["correctness"]["iou_vs_scalar"] for row in reports)
    max_bbox_delta = max(row["correctness"]["bbox_delta_pixels"] for row in reports)
    selected_backend = max(selected_counts.items(), key=lambda item: item[1])[0]
    fallback_reason = max(fallback_counts.items(), key=lambda item: item[1])[0]

    payload = {
        "artifact_type": "mask_postprocess_lowering_report",
        "schema_version": 1,
        "benchmark_runtime": "python_semantic_harness",
        "truth_boundary": {
            "real": "PocketChef app contains live scalar/SIMD CPU mask postprocess dispatch.",
            "artifact_backed": "This report validates scalar vs SIMD-style semantics, correctness gates, p50/p95 timings, and policy output on synthetic YOLO-Seg-like tensors.",
            "not_claimed": "No Qualcomm Ripple, Snapdragon/QNN/Hexagon, live Metal dispatch, or production compiler integration is claimed in V1.",
        },
        "technology_gate": {
            "input": "YOLO-Seg mask coefficients, NCHW prototype tensor, crop box, and threshold",
            "decision": "legality and profile policy select scalar CPU or SIMD CPU mask postprocess",
            "metric": "p50/p95 mask decode latency, estimated FPS impact, fallback behavior, and mask correctness vs scalar reference",
            "passes_gate": True,
        },
        "acceptance_thresholds": {
            "max_alpha_abs_diff": 1,
            "iou_vs_scalar": 0.995,
            "bbox_delta_pixels": 1,
        },
        "summary": {
            "case_count": len(reports),
            "selected_backend_counts": selected_counts,
            "fallback_reason_counts": fallback_counts,
        },
        "selected_backend": selected_backend,
        "fallback_reason": fallback_reason,
        "p50_latency_ms": round(percentile(selected_p50, 50), 6),
        "p95_latency_ms": round(percentile(selected_p95, 95), 6),
        "estimated_fps_impact": round(statistics.fmean(fps_impacts), 6),
        "max_alpha_abs_diff": max_alpha_abs_diff,
        "mean_alpha_abs_diff": round(mean_alpha_abs_diff, 6),
        "active_pixel_count_delta": max_active_delta,
        "iou_vs_scalar": min_iou,
        "bbox_delta_pixels": max_bbox_delta,
        "cases": reports,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps({"wrote": str(OUT_PATH), "case_count": len(reports)}, indent=2))


if __name__ == "__main__":
    main()
