# Technical Debt

## Weak Spots

### Large View Models and Views

`CameraViewModel.swift`, `FoodDetector.swift`, `FoodSegmenter.swift`, `ResultSheet.swift`, and `MaskPostprocessRuntime.swift` are large files with multiple responsibilities. This makes behavior harder to test and raises the risk of accidental regressions.

Risk:

- Camera lifecycle, memory events, inference dispatch, metrics, and recipe state are tightly coupled.
- Future changes may need careful extraction to avoid breaking the main demo flow.

### Mixed Implemented and Evidence-Only Paths

The repo intentionally combines app code with evidence artifacts. Some mode names describe real policy changes while other claims are imported, estimated, pending, or simulated.

Risk:

- Future contributors may accidentally present artifact-backed or placeholder rows as measured app behavior.
- The Compression and Combined modes are especially easy to overstate until measured iPhone exports exist.

### Unused or Partially Integrated Components

`FoodSegmenter` and `FoodClassifier` are implemented wrappers, but the primary detection path uses `FoodDetector.detectWithYOLOSeg(...)`.

Risk:

- Readers may assume FastSAM or classification is active in the main flow.
- These components can drift from app behavior without test coverage.

### Hard-Coded Label and Nutrition Tables

Food labels and nutrition profiles are hard-coded in Swift.

Risk:

- Label naming inconsistencies can silently drop ingredients.
- Nutrition values are coarse estimates and do not account for quantity.
- Updating model classes requires manual updates in several places.

### Shape-Specific Model Parsing

YOLO-Seg parsing depends on expected tensor ranks, channel counts, prototype channel count, and COCO label offsets.

Risk:

- Exporting a different YOLO model variant can break parsing without compile-time warnings.
- Failures may surface as empty detections rather than explicit errors.

### Placeholder Compression Artifacts

`compress_model.py` currently copies source artifacts for INT8/pruned variants and labels them as placeholders.

Risk:

- File sizes match FP32 and there is no real speed, memory, or accuracy improvement to claim.
- Future docs or dashboards could misinterpret candidate ordering as validated compression.

### Pending Runtime and Memory Exports

Several reports contain schemas or `None` values for real app-specific metrics.

Risk:

- `runtime_artifacts/runtime_benchmark_report.json` and `runtime_artifacts/iphone_memory_report.json` can be mistaken for measured results.
- Real device benchmark procedures are not automated end to end.

### External Absolute Paths

Scripts default to absolute local paths for `ml-graph-compiler-runtime` and `heterogeneous-inference-runtime`.

Risk:

- Fresh clones on another machine will fail unless environment variables are set.
- Claude Code should inspect script defaults before running evidence generation.

## Missing Tests

No dedicated test suite was found in the repository during handoff inspection.

High-value test targets:

- `CapturedFrameGeometry` coordinate conversions.
- `MetricsTracker` percentile and FPS calculations.
- `PocketChefPlanner` label grouping, profile lookup, and output generation.
- `OllamaClient` prompt construction and fallback logic with mocked responses.
- `MaskPostprocessRuntime` legality checks, fallback reasons, and scalar/SIMD equivalence on small tensors.
- YOLO-Seg parser behavior for supported and unsupported tensor shapes.
- Python report generators with fixture artifacts.

## Duplicated or Repeated Logic

- Model lookup logic appears in multiple Swift model wrappers.
- Food label/name normalization appears across detector, classifier, and planner logic.
- Evidence truth-boundary language appears in README, scripts, and artifacts.
- Metrics/report schema construction is repeated across Python scripts.

Risk:

- Inconsistent updates when adding models, labels, modes, or report fields.

## Unclear Naming

- `legacyVisionModel` is the active YOLO-Seg model path; "legacy" may imply deprecated behavior.
- `Runtime`, `Compiler`, `Compression`, and `Combined` modes are partly live policies and partly evidence labels.
- `FoodSegmenter` suggests an active segmentation module, but YOLO-Seg inside `FoodDetector` is the active path.

Risk:

- New contributors may optimize the wrong path or document inactive behavior as active.

## Future Risks

- App memory could grow if mask caches, captured images, or pixel buffers are not cleared consistently.
- Core ML model bundle changes can break runtime loading or parsing.
- Local Ollama networking can be brittle on real devices because host/IP differs between simulator and iPhone.
- Generated evidence artifacts can become stale relative to app code.
- Large JSON/model artifacts may make the repository heavy and slow to clone.
- Swift concurrency uses manual queues and `@unchecked Sendable`; future changes should be careful with thread ownership.

## Assumptions

- Existing dirty worktree changes are user-owned and were not modified while creating this documentation.
- Documentation should preserve current behavior rather than redesigning source code.
- Any future refactor should be guarded by tests before splitting large files.
