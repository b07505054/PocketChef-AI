# Future Work

## Near-Term Handoff Tasks

- Add tests around non-trivial pure logic before refactoring:
  - Geometry conversion.
  - Metrics percentiles.
  - Recipe planning.
  - Mask postprocess legality and fallback behavior.
  - Python report generation with fixture JSON.
- Capture real iPhone benchmark exports for each app mode:
  - Baseline p50/p95/FPS.
  - Runtime p50/p95/FPS.
  - Compression p50/p95/FPS and stability.
  - Combined p50/p95/FPS.
  - Peak physical footprint and event deltas.
- Replace `runtime_artifacts/iphone_memory_report.json` schema with a measured device export before making runtime memory claims.
- Replace compression placeholder copies with actual quantized/pruned Core ML artifacts or remove compression improvement claims.
- Add a concise benchmark runbook that says exactly which device, model bundle, mode, frame, and artifact file produced each number.

## App Improvements

- Split `CameraViewModel` into smaller components after tests exist:
  - Camera session service.
  - Capture state.
  - Detection coordinator.
  - Memory event recorder.
  - Recipe state coordinator.
- Make model discovery/reporting more explicit in the UI when candidates are missing or falling back.
- Add clearer app-side export controls for:
  - Detection metrics JSON.
  - Memory report JSON.
  - LLM benchmark JSON.
- Improve error messaging for model shape mismatches and empty segmentation output.
- Consider a continuous preview inference mode only after snapshot mode is well benchmarked.

## Model and Inference Work

- Validate current YOLO-Seg parser against every bundled model variant.
- Add fixture-based parser tests for representative model outputs.
- Decide whether `FoodSegmenter` and `FoodClassifier` should be active product features, removed, or documented as experimental.
- If FastSAM remains, define how it composes with YOLO-Seg or replaces it.
- Build a real quantization/pruning pipeline and report:
  - Model size.
  - Loaded memory.
  - Latency.
  - Detection/mask stability.
  - Accuracy or proxy correctness.

## Compiler and Runtime Evidence

- Keep the current truth boundary: app-side behavior is separate from imported compiler/runtime evidence.
- Replace external same-class runtime rows with PocketChef-specific iPhone YOLO-Seg rows.
- Add provenance fields to every generated report:
  - Git commit.
  - Device or host.
  - OS version.
  - Model artifact hash.
  - Command line.
  - Timestamp.
- Consider validating generated artifacts in CI with schema checks.
- If live iPhone compiler integration is desired, define a smaller first milestone such as selecting postprocess policy from a manifest rather than live graph compilation.

## Metal Mask Postprocess

- Decide whether Mac Metal benchmark evidence should become an iPhone runtime feature.
- If yes:
  - Port the kernel into the app target.
  - Add device compatibility checks.
  - Benchmark scalar CPU, SIMD CPU, and Metal on the same real iPhone frames.
  - Preserve scalar output as correctness reference.
  - Report fallback reasons and mismatches.

## LLM Serving

- Keep implemented LLM claims limited to Ollama local/LAN streaming metrics until more runtime code is actually integrated.
- Add mocked tests for prompt lowering, fallback model behavior, and metrics parsing.
- Add export/import flow for real in-app LLM benchmark JSON.
- If multi-request serving remains a portfolio goal, replace synthetic/imported traces with a reproducible live framework run before claiming framework performance.

## Documentation and Maintenance

- Keep `docs/architecture.md`, `docs/data_flow.md`, and README truth boundaries synchronized.
- Add a short "claim checklist" to future PRs:
  - Is the component implemented, simulated, imported, placeholder, or pending?
  - Is the metric measured or estimated?
  - What artifact backs the claim?
  - Can someone reproduce it?
- Avoid adding new giant files. Prefer small functions and simple modules.
- Make generated artifacts easy to regenerate, but do not require regeneration for unrelated app changes.

## Assumptions

- The next maintainer will use Claude Code for implementation work and should be given conservative guardrails.
- Python automation should target Python 3.11.
- The highest-impact next step is real device evidence, not more simulated benchmark rows.
