#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def require(package_name: str, import_name: str | None = None):
    try:
        return __import__(import_name or package_name)
    except ImportError as exc:
        raise SystemExit(
            f"Missing dependency: {package_name}. Install with:\n"
            "python3 -m pip install ultralytics coremltools onnx onnxruntime numpy pillow"
        ) from exc


def main() -> None:
    parser = argparse.ArgumentParser(description="Export a YOLO detector to ONNX and Core ML.")
    parser.add_argument("--model", default="yolov8n.pt", help="Ultralytics model path or model name.")
    parser.add_argument("--output-dir", default="models")
    parser.add_argument("--image-size", type=int, default=640)
    parser.add_argument("--half", action="store_true", help="Export FP16 Core ML variant when supported.")
    parser.add_argument("--artifact-prefix", default="yolo_food", help="Output artifact prefix.")
    args = parser.parse_args()

    ultralytics = require("ultralytics")
    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    model = ultralytics.YOLO(args.model)

    onnx_path = model.export(
        format="onnx",
        imgsz=args.image_size,
        dynamic=False,
        simplify=True,
    )
    onnx_path = Path(onnx_path)
    target_onnx = output_dir / f"{args.artifact_prefix}_fp32.onnx"
    if onnx_path.resolve() != target_onnx.resolve():
        target_onnx.write_bytes(onnx_path.read_bytes())

    coreml_path = model.export(
        format="coreml",
        imgsz=args.image_size,
        half=args.half,
        nms=True,
    )
    coreml_path = Path(coreml_path)
    suffix = ".mlpackage" if coreml_path.suffix == ".mlpackage" else coreml_path.suffix
    target_coreml = output_dir / f"{args.artifact_prefix}_{'fp16' if args.half else 'fp32'}{suffix}"
    if coreml_path.resolve() != target_coreml.resolve():
        if coreml_path.is_dir():
            import shutil

            if target_coreml.exists():
                shutil.rmtree(target_coreml)
            shutil.copytree(coreml_path, target_coreml)
        else:
            target_coreml.write_bytes(coreml_path.read_bytes())

    report = {
        "artifact_type": "model_export_report",
        "source_model": args.model,
        "image_size": args.image_size,
        "outputs": {
            "onnx": str(target_onnx),
            "coreml": str(target_coreml),
        },
    }
    report_path = output_dir / "model_export_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
