# CLAUDE.md

## Project Context

PocketChef-AI is a native iOS SwiftUI food segmentation and edge AI systems demo. The implemented app path captures a camera frame, lets the user tap a food target, runs Vision/Core ML YOLO-Seg, decodes and overlays a mask, reports latency/FPS/memory, generates a deterministic recipe/nutrition snapshot, and optionally asks a local Ollama model.

This repo also contains compiler/runtime/compression/LLM evidence artifacts. Treat those artifacts carefully: many are simulated, estimated, imported, placeholder, or pending real iPhone export.

## Required Truth Boundaries

- Clearly distinguish implemented app behavior from simulations and imported evidence.
- Do not claim live iPhone graph compilation; current compiler integration is Mac-side artifact import.
- Do not claim live iPhone Metal mask dispatch; current Metal evidence is a Mac benchmark.
- Do not claim real compression gains from current INT8/pruned artifacts; they are placeholder copies unless replaced.
- Do not claim app-specific runtime/memory benchmark numbers from schema files or `None` fields.
- If metrics are estimated, label them estimated.
- If metrics come from generated artifacts, name the artifact.
- Do not invent benchmark numbers.

## Engineering Preferences

- Python 3.11.
- Prefer dataclasses.
- Avoid unnecessary classes.
- Keep functions under 100 lines when practical.
- Use type hints.
- Prefer simple modular design.
- Avoid over-engineering.
- Composition over inheritance.
- No giant classes.
- Write tests for non-trivial logic.
- Run tests after changes.
- Explain changes after implementation.

## Working Rules

- Do not modify source code unless explicitly asked.
- Do not refactor code unless explicitly asked.
- Do not change tests unless the task requires it.
- Preserve existing generated artifacts unless the task is specifically to regenerate evidence.
- Treat dirty worktree changes as user-owned.
- Before making benchmark or architecture claims, inspect the relevant source and artifact.

## Important Files

- `ios/PocketChefAI/PocketChefAI/CameraViewModel.swift`
  - Camera session, capture state, detection dispatch, metrics, memory events, recipe state.
- `ios/PocketChefAI/PocketChefAI/FoodDetector.swift`
  - Main implemented YOLO-Seg Vision/Core ML detection path.
- `ios/PocketChefAI/PocketChefAI/MaskPostprocessRuntime.swift`
  - Live scalar/SIMD CPU mask decoding.
- `ios/PocketChefAI/PocketChefAI/OptimizationMode.swift`
  - Mode policies and summaries.
- `ios/PocketChefAI/PocketChefAI/PocketChefPlanner.swift`
  - Deterministic recipe/nutrition estimates.
- `ios/PocketChefAI/PocketChefAI/OllamaClient.swift`
  - Implemented local/LAN Ollama streaming LLM path.
- `dashboard/server.py`
  - Local evidence dashboard API.
- `scripts/`
  - Model export, benchmark, compiler import, report generation, and evidence scripts.
- `docs/`
  - Handoff documentation.

## Handoff Docs

Read these first:

- `docs/architecture.md`
- `docs/data_flow.md`
- `docs/design_decisions.md`
- `docs/technical_debt.md`
- `docs/future_work.md`

## Testing Guidance

No dedicated test suite was found during documentation handoff. When adding behavior, prioritize tests for:

- Geometry conversion.
- Metrics percentile calculations.
- Recipe planner label/profile logic.
- Mask postprocess legality and fallback paths.
- Ollama prompt construction and response parsing with mocks.
- Python report generators with fixture artifacts.

## Benchmark Guidance

A valid benchmark claim should include:

- Input source.
- Compiler/runtime/app decision.
- Metric impact.
- Device or host.
- Model artifact name/hash when practical.
- Command or app export path.
- Whether the number is measured or estimated.

When in doubt, write "pending measurement" instead of filling in a number.

## Validation

Current validation is a Python syntax check only:

- `scripts/check.sh` runs `.venv/bin/python -m py_compile` over `dashboard/server.py` and `scripts/*.py`. It requires a project-local `.venv` and has no system Python fallback; if `.venv/bin/python` is missing it errors out instead of falling back.
- `.github/workflows/python-validate.yml` runs on push and pull request using Python 3.11: it creates `.venv`, installs `requirements.txt` if one exists in the repo (skipping cleanly if not), then runs `scripts/check.sh`. No packages are installed automatically outside CI, and `requirements.txt` does not exist yet.

There is no automated test suite yet (Swift or Python). See `docs/test_plan.md` for the future test plan; it is documentation only and not implemented.
