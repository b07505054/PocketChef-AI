# Data Flow

## Camera and Capture Input

Primary user input is an iPhone camera frame plus an optional tap point.

1. `ContentView` starts `CameraViewModel.start()`.
2. `CameraViewModel` configures an `AVCaptureSession` with the back camera and a `AVCaptureVideoDataOutput`.
3. `captureOutput(_:didOutput:from:)` stores the latest `CVPixelBuffer`.
4. When the user taps capture, `capturePhoto()` copies the pixel buffer, creates a display `UIImage`, stores `CapturedFrameGeometry`, stops the live session, and waits for a target tap.
5. The target tap is converted to normalized image coordinates and passed to `setTargetPrompt(_:)`.

Important structures:

- `CapturedFrameGeometry`
  - Captured image size.
  - Pixel buffer size.
  - Vision orientation.
  - View/image coordinate conversion helpers.
- `CVPixelBuffer`
  - The frozen inference input.
- `CGPoint`
  - Normalized prompt point in image coordinates.

## Detection and Mask Processing

The implemented detection path is `CameraViewModel.detectCapturedFrame(at:)` into `FoodDetector.detect(...)`.

Processing flow:

1. Record memory event `before_inference`.
2. Dispatch detection on `inferenceQueue`.
3. Run `VNCoreMLRequest` against the loaded YOLO-Seg Core ML model.
4. Parse Vision results:
   - `VNRecognizedObjectObservation` for object observations, or
   - `VNCoreMLFeatureValueObservation` for YOLO detector/segmentation tensors.
5. For segmentation-shaped output:
   - Find raw candidate tensor and mask prototype tensor.
   - Select best class per candidate.
   - Filter by confidence and supported food labels.
   - Convert YOLO box coordinates into normalized display boxes.
   - Extract 32 mask coefficients.
   - Apply NMS.
   - Decode masks through `MaskPostprocessRuntime`.
6. Select prompt-aligned target:
   - If no prompt exists, keep highest-confidence detections up to mode limit.
   - If a prompt exists, require mask or expanded-box hit.
   - Rank by confidence, prompt containment, box area, and distance from center.
7. Return `DetectionFrame`.
8. Update UI state, overlay, metrics, recipe plan, and memory events on the main queue.

Important structures:

- `Detection`
  - Label, confidence, normalized bounding box, optional mask polygon, optional `DetectionMask`, and mask area ratio.
- `DetectionMask`
  - Cropped alpha mask, dimensions, active pixel count, centroid, and hit testing.
- `DetectionFrame`
  - Detections, latency, mode, backend string, model summary, timestamp, and memory metadata.
- `MaskPostprocessDiagnostics`
  - Selected backend, fallback reason, decode latency, SIMD eligibility, prototype layout, and correctness mode.

## Optimization Mode Data

`OptimizationMode` controls live app behavior and UI wording:

- `Baseline`
  - Uses `yolo_food_s_seg_fp32`.
  - Core ML compute units: CPU+GPU.
  - Baseline mask threshold and scalar postprocess policy.
- `Runtime`
  - Uses the same YOLO-Seg FP32 model.
  - Core ML compute units: all, meaning CPU+GPU+ANE where available.
  - Runtime evidence in reports is external until PocketChef-specific iPhone exports exist.
- `Compiler`
  - Uses YOLO-Seg FP32.
  - Enables SIMD-preferred mask postprocess policy.
  - Compiler speed/memory claims are artifact-backed estimates, not live iPhone compilation.
- `Compression`
  - Searches INT8/pruned/FP16 candidates before FP32 fallback.
  - Current INT8/pruned artifacts are placeholders unless regenerated with real compression.
- `Combined`
  - Combines runtime compute unit policy with compiler-style postprocess and compressed candidate ordering.
  - End-to-end combined benchmark numbers are pending.

## Recipe and Nutrition Output

`PocketChefPlanner.makePlan(...)` converts detections into a deterministic `RecipePlan`.

Flow:

1. Group detections by lowercased label.
2. Keep labels found in the hard-coded nutrition profile table.
3. Use max confidence per label.
4. Keep up to five ingredients.
5. Sum static calories/macros/fiber.
6. Generate title, subtitle, scene summary, visual answer, missing items, shopping suggestions, steps, nutrition note, benchmark note, and LLM runtime note.

Important structures:

- `IngredientSummary`
  - Name, confidence, calories, protein, carbs, fat, fiber.
- `RecipePlan`
  - User-facing recipe/nutrition snapshot and supporting notes.

Assumption: nutrition values are estimates from static per-label profiles, not measured portions or medical/dietary advice.

## Local LLM Flow

`ResultSheet` lets the user ask a question about the current recipe snapshot.

Flow:

1. User enters Ollama host, model, mode, and question.
2. `OllamaClient.ask(...)` validates the question.
3. Client posts to `host + "/api/chat"` with streaming enabled.
4. Request includes:
   - System prompt.
   - Detected ingredients and nutrition estimate.
   - Either full context or lowered structured context depending on `LLMOptimizationMode`.
   - Mode-specific temperature, token budget, and optional `keep_alive`.
5. Streaming response lines are decoded as Ollama chat chunks.
6. The first content token timestamp becomes TTFT.
7. Final chunk metadata provides prompt token count, completion token count, and eval duration when available.
8. `LLMMetrics` and answer text update the result sheet.

Implemented metrics:

- TTFT, measured live.
- Total latency, measured live.
- Prompt tokens, from Ollama final chunk when provided.
- Completion tokens, from Ollama final chunk when provided.
- Tokens/sec, calculated from completion tokens and eval duration when provided.

Imported/simulated serving evidence:

- `llm_artifacts/serving/*` describes compiler/runtime scheduler, KV cache, framework adapter, and multi-request serving evidence.
- The iOS app does not execute these serving frameworks directly.

## Reports and Dashboard Flow

Script/report inputs:

- Local model files under `models/`.
- iOS app modes and schema expectations.
- External compiler artifacts from `ml-graph-compiler-runtime`.
- External runtime artifacts from `heterogeneous-inference-runtime`.
- Generated local evidence artifacts.

Script/report outputs:

- `benchmark_reports/core_value_evidence.json`
- `benchmark_reports/combined_benchmark_report.json`
- `benchmark_reports/memory_evidence_summary.json`
- `compiler_artifacts/generated/*`
- `compression_artifacts/*`
- `runtime_artifacts/*`
- `llm_artifacts/*`

Dashboard flow:

1. `dashboard/server.py` serves `/api/snapshot`.
2. It reads JSON reports from compiler, runtime, compression, LLM, and benchmark directories.
3. `dashboard/static/index.html` renders the local evidence snapshot.

## Metrics and Truth Boundaries

Implemented app metrics:

- Latest detection latency.
- p50/p95 detection latency over recent samples.
- FPS over recent recorded detections.
- Physical footprint and RSS memory samples.
- Mask decode latency metadata.
- Local Ollama TTFT, total latency, and tokens/sec.

Estimated or artifact-backed metrics:

- Compiler activation memory estimates in generated compiler artifacts.
- Compiler estimated latency from cost planner artifacts.
- External runtime latency/FPS deltas in `core_value_evidence.json`.
- Metal mask benchmark measurements on local Mac GPU.
- LLM multi-request scheduler throughput, p95 latency, KV cache, and framework adapter metrics.

Pending metrics:

- Real PocketChef YOLO-Seg iPhone baseline/runtime/compression p50, p95, FPS, and peak memory exports.
- Loaded-memory impact of compression candidates.
- End-to-end combined mode improvement.
