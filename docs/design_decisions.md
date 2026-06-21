# Design Decisions

## Camera-First Native iOS Experience

The app opens directly into a camera surface rather than a landing page or form. This keeps the main value loop short: capture food, tap target, see segmentation, then inspect recipe/nutrition and metrics.

Tradeoff: app logic is concentrated in `CameraViewModel`, which makes the user flow easy to follow but increases class size and testing difficulty.

## Snapshot Inference Instead of Continuous Inference

The current flow stores the latest preview buffer, captures a frozen frame, stops the camera session, and runs detection on the captured image after a target tap.

Benefits:

- Lower memory and thermal pressure than continuous per-frame segmentation.
- Stable target selection and overlay geometry.
- Easier benchmark event boundaries.

Tradeoff:

- FPS metrics are based on recorded detection events, not a continuous live video inference loop.
- The user must capture and tap instead of seeing continuously updated segmentation.

## Vision/Core ML as the App Inference Runtime

The implemented app path uses `VNCoreMLRequest` and Core ML model files discovered in the bundle.

Benefits:

- Native iOS deployment path.
- Simple compute unit selection through `MLModelConfiguration`.
- Works with compiled `.mlmodelc`, `.mlpackage`, and `.mlmodel` resources.

Tradeoff:

- App behavior depends heavily on model output tensor shape and Vision wrapping.
- Lower-level backend scheduling and compiler passes are not directly controlled inside the iOS app.

## Optimization Modes as Policies

`OptimizationMode` centralizes model candidate ordering, compute units, thresholds, postprocess preference, and UI summaries.

Benefits:

- Makes Baseline/Runtime/Compiler/Compression/Combined comparisons visible.
- Keeps mode-specific policy in one place.

Tradeoff:

- Some mode names imply deeper system changes than the live app currently performs. Documentation and UI summaries must keep distinguishing live behavior from artifact-backed evidence.

## YOLO-Seg as the Primary Implemented Path

`FoodDetector.detect(...)` currently calls `detectWithYOLOSeg(...)` directly. `FoodSegmenter` and `FoodClassifier` are present but not part of the main path.

Benefits:

- Single primary model flow.
- Detection labels, boxes, and masks come from one segmentation model family.

Tradeoff:

- Unused model wrappers add maintenance surface and may confuse handoff readers.

## CPU Scalar/SIMD Mask Postprocess in App

Mask decode is implemented in Swift with scalar and SIMD candidate paths. Compiler modes can prefer the SIMD path when legality checks pass.

Benefits:

- There is a real app-side optimization point independent of Core ML internals.
- Diagnostics expose selected backend, fallback reason, decode latency, and layout.

Tradeoff:

- The SIMD implementation is still CPU-side. Metal SPMD evidence exists as a Mac benchmark, but live iPhone Metal dispatch is not implemented.

## Deterministic Planner Before LLM

The recipe/nutrition snapshot is generated locally through `PocketChefPlanner` before any LLM call.

Benefits:

- App remains useful without network or Ollama.
- Deterministic output supports easier demos and tests.
- LLM prompts can use compact structured context.

Tradeoff:

- Nutrition is based on static label profiles, not portion size, weight, or external nutrition databases.

## Ollama for Local/LAN LLM Serving

The app uses Ollama `/api/chat` streaming for the implemented LLM path.

Benefits:

- Simple local development path.
- Real streaming TTFT and total latency can be measured in app.
- Fallback model behavior is straightforward.

Tradeoff:

- Simulator can use `127.0.0.1`, but real iPhone requires a Mac LAN IP.
- Multi-request scheduler artifacts are not executed by the app.

## Evidence Artifacts as First-Class Outputs

The repository keeps JSON evidence under `benchmark_reports`, `compiler_artifacts`, `compression_artifacts`, `runtime_artifacts`, and `llm_artifacts`.

Benefits:

- Claims can point to input source, decision, and metric impact.
- The dashboard can aggregate artifacts without rebuilding the iOS app.

Tradeoff:

- Mixed evidence types require discipline. Real measurements, estimates, simulations, placeholders, and pending schemas sit beside each other.

## Explicit Truth Boundaries

README and generated reports repeatedly distinguish implemented behavior from simulations and imported evidence.

Important boundaries:

- Real: iOS YOLO-Seg/Core ML inference, scalar/SIMD mask postprocess, local memory sampling, deterministic recipe planner, Ollama streaming metrics.
- Real on Mac but not live iPhone: Metal mask SPMD benchmark.
- Imported or artifact-backed: compiler lowering/memory planning, external runtime rows, LLM serving scheduler/framework evidence.
- Placeholder or pending: compression speed/accuracy impact, app-specific runtime benchmark exports, app-specific iPhone memory report.

## Assumptions

- Python scripts are intended to run with Python 3.11 unless a specific dependency requires otherwise.
- External repo paths in scripts default to local absolute paths under `/Users/allen/Documents/Codex/project`.
- Generated metrics are valid only for the artifact and environment that produced them.
- Placeholder compression artifacts should not be treated as real quantized/pruned models.
- Future claims should preserve the repo's three-question rule: input source, decision, and metric impact.
