# Test Plan (Future Work, Not Implemented)

This document lists candidate tests for future work. Nothing in this file is implemented yet. Adding any of these requires separate approval, including adding `pytest` as a dependency and wiring an Xcode test target.

Current validation is limited to a Python syntax check (`scripts/check.sh`, CI in `.github/workflows/python-validate.yml`). See the "Validation" section of `CLAUDE.md`.

## Swift XCTest (future)

- `MetricsTracker`
  - Latency/FPS aggregation correctness.
  - Percentile calculation correctness (e.g. p50/p95) on known input sequences.
  - Memory event recording and rollup.
- `PocketChefPlanner`
  - Label-to-profile mapping logic.
  - Deterministic recipe/nutrition output given fixed inputs.
- `MaskPostprocessRuntime`
  - Mask decode legality checks (valid shapes/ranges).
  - Fallback path behavior when decode input is malformed or unsupported.

No Xcode project, scheme, or target changes are proposed here; this is a list of future test targets only.

## Python pytest (future)

- `scripts/generate_reports.py`
  - Report generation against fixture artifacts.
- `scripts/run_compiler_pipeline.py`
  - Compiler artifact import behavior against fixture inputs.
- Benchmark/evidence schema validation
  - Validate generated benchmark/evidence JSON against expected schema using fixture artifacts.

`pytest` is not currently a dependency of this repo and should not be added without separate approval.
