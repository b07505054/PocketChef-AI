# Architecture

## Purpose

PocketChef-AI is a native iOS food segmentation and edge AI systems demo. The user-facing app captures a camera frame, lets the user tap a food target, runs YOLO-Seg through Vision/Core ML, overlays the selected mask, reports runtime metrics, and turns the detected label into a recipe/nutrition snapshot. The repository also carries compiler, runtime, compression, memory, and LLM serving evidence artifacts used to explain optimization modes.

This repository is not only an app. It is also a portfolio shell for showing how mobile inference, compiler planning, runtime scheduling, model compression, memory instrumentation, and local LLM serving could connect. Some of those connections are implemented in the iOS app; others are imported evidence or simulations.

## Main Modules

### iOS App

- `ios/PocketChefAI/PocketChefAI/PocketChefAIApp.swift`
  - SwiftUI app entry point.
- `ContentView.swift`
  - Main camera-first UI.
  - Shows camera/captured image, detection overlay, metrics panel, capture/retake control, and result sheet.
- `CameraPreview.swift`
  - `UIViewRepresentable` wrapper for `AVCaptureVideoPreviewLayer`.
- `CameraViewModel.swift`
  - Owns camera session lifecycle, capture state, selected target point, detection dispatch, metrics, recipe state, memory events, and mode changes.
  - Coordinates `FoodDetector`, `MetricsTracker`, `MemoryProfiler`, and `PocketChefPlanner`.
- `DetectionOverlay.swift`
  - Draws prompt point, bounding boxes, mask polygons, and cached mask images.
- `MetricsPanel.swift`
  - Presents active mode, backend/model summary, FPS, latency percentiles, geometry, and memory summary.
- `ResultSheet.swift`
  - Shows recipe/nutrition output, benchmark details, memory export text, local LLM controls, and LLM response metrics.

### Vision/Core ML Inference

- `FoodDetector.swift`
  - Primary implemented detector path.
  - Loads YOLO-Seg Core ML candidates based on `OptimizationMode`.
  - Runs `VNCoreMLRequest` on captured frames.
  - Parses recognized object, detector, or segmentation-shaped outputs.
  - Filters to supported food labels.
  - Applies NMS, prompt hit testing, target ranking, and mask decode.
- `MaskPostprocessRuntime.swift`
  - Live CPU mask postprocess implementation.
  - Performs legality checks on YOLO-Seg mask coefficients and NCHW prototype tensors.
  - Chooses scalar CPU or SIMD CPU candidate based on mode policy.
  - Records diagnostics such as backend, fallback reason, latency, and layout.
- `Detection.swift`
  - Data structures for captured geometry, masks, detections, and detection frames.
- `OptimizationMode.swift`
  - Defines Baseline, Runtime, Compiler, Compression, and Combined modes.
  - Encodes model candidate order, Core ML compute units, thresholds, prompt/mask settings, and policy summaries.
- `FoodSegmenter.swift`
  - Secondary FastSAM-style segmentation implementation.
  - It is present and substantial, but the current `FoodDetector.detect` path calls YOLO-Seg directly.
- `FoodClassifier.swift`
  - Core ML classifier wrapper.
  - Present but not wired into the current `FoodDetector.detect` path.

### Recipe and Local LLM

- `PocketChefPlanner.swift`
  - Deterministic local recipe/nutrition planner.
  - Maps detected labels to hard-coded nutrition profiles and simple meal suggestions.
  - Nutrition values are estimates from static profiles, not measured food portions.
- `OllamaClient.swift`
  - Calls a local or LAN Ollama `/api/chat` endpoint.
  - Streams response text.
  - Measures TTFT, total latency, token counts, and tokens/sec when Ollama returns final counts.
  - Supports prompt-lowering and keep-alive policies through `LLMOptimizationMode`.

### Metrics and Memory

- `MetricsTracker.swift`
  - Tracks latest latency, FPS, p50, p95, and frame count over recent samples.
- `MemoryProfiler.swift`
  - Uses Mach task info to sample physical footprint and RSS.
  - Emits in-app memory events and a copyable JSON report.

### Scripts and Dashboard

- `scripts/export_yolo_to_coreml.py`
  - Exports Ultralytics YOLO models to ONNX and Core ML.
- `scripts/benchmark_coreml.py`
  - Benchmarks a Core ML model locally through `coremltools`.
- `scripts/compress_model.py`
  - Creates compression candidate artifacts and report rows.
  - Current INT8/pruned outputs are placeholder copies unless replaced by real compression.
- `scripts/run_compiler_pipeline.py`
  - Runs an external `ml-graph-compiler-runtime` binary on macOS and imports trace artifacts.
  - Does not make the iPhone app live-compile models.
- `scripts/generate_core_evidence.py`
  - Builds the main benchmark/evidence table from local app artifacts and external compiler/runtime artifacts.
- `scripts/generate_mask_postprocess_evidence.py`
  - Generates artifact-backed scalar/SIMD mask postprocess evidence on synthetic YOLO-Seg-like tensors.
- `scripts/generate_metal_mask_spmd_benchmark.py`
  - Runs a local Mac Metal benchmark for a mask postprocess candidate.
  - Does not route the iPhone app through Metal.
- `scripts/import_llm_serving_artifacts.py`
  - Imports LLM compiler/runtime serving artifacts from external systems repos.
- `scripts/generate_reports.py`
  - Combines evidence reports.
- `dashboard/server.py` and `dashboard/static/index.html`
  - Local read-only evidence dashboard served at `127.0.0.1:8766`.

## Implemented Behavior

- SwiftUI camera UI and capture/retake flow.
- Camera permission handling and `AVCaptureSession` preview.
- Captured frame freezing through `CVPixelBuffer` copy and display `UIImage`.
- Tap-to-select normalized prompt point.
- Vision/Core ML inference for YOLO-Seg candidate models found in the app bundle.
- YOLO-style output parsing, label filtering, NMS, mask coefficient extraction, and prompt-aligned target selection.
- Live scalar/SIMD CPU mask postprocess dispatch in the app.
- Overlay rendering for bounding boxes, polygons, and mask images.
- Runtime metrics inside the app: latest latency, p50, p95, FPS.
- In-process memory event recording: physical footprint, RSS, peak, deltas, and metadata.
- Deterministic recipe/nutrition snapshot generation from detected labels.
- Local Ollama streaming call path with live TTFT/total latency/tokens/sec measurement.
- Local dashboard that reads JSON artifacts and reports.

## Simulated, Artifact-Backed, or Pending Behavior

- Compiler graph IR, fusion, memory planning, and execution plan artifacts are compiler simulations or imported external compiler traces.
- `compiler_artifacts/generated/compiler_pipeline_manifest.json` states the real integration is a Mac-side compiler pipeline import; the iPhone app does not live-compile the YOLO-Seg graph.
- Runtime optimization evidence for the `Run` row comes from an external same-class CV workload until replaced by a PocketChef YOLO-Seg iPhone export.
- `runtime_artifacts/runtime_benchmark_report.json` contains placeholder `None` metrics for the app-specific runtime variants.
- `runtime_artifacts/iphone_memory_report.json` is a schema/pending export file, not a measured iPhone run.
- Compression INT8/pruned artifacts are currently policy-backed placeholder copies in `compression_artifacts/model_compression_report.json`.
- The Metal mask SPMD report runs a real local Mac Metal benchmark, but live iPhone Metal dispatch is not implemented.
- LLM serving artifacts include imported/synthetic multi-request scheduler and framework adapter evidence. The iOS app only calls local Ollama directly; it does not run vLLM, SGLang, Triton, TensorRT, or a live multi-request scheduler.

## Assumptions

- The main supported app path is YOLO-Seg through `FoodDetector`, not `FoodSegmenter` or `FoodClassifier`.
- The app bundle is expected to include compiled Core ML models under names referenced by `OptimizationMode`.
- Nutrition output is intentionally approximate and label-based.
- Metrics displayed by the app are session-local and depend on device, model bundle, camera frame, and current mode.
- Any metric labeled estimated, placeholder, artifact-backed, or pending should not be converted into a benchmark claim without a fresh measured artifact.
