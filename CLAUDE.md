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

## Documentation Hierarchy

Truth must flow in the following order:

Code
↓
Artifacts
↓
README.md
↓
CLAUDE.md
↓
docs/

Lower levels must never contradict higher levels.

Documentation must describe reality rather than invent behavior.

If uncertainty exists, trust code and generated artifacts.

Never exaggerate capabilities.

Never claim production behavior unless code and artifacts support it.

## README Contract

README.md exists to answer:

1. What is it?
2. Why is it interesting?
3. How do I run it?
4. What results does it produce?

README should emphasize user-facing understanding.

Avoid implementation details unless necessary.

Avoid maintenance instructions.

## CLAUDE.md Contract

CLAUDE.md exists to answer:

1. How do I maintain it?
2. What commands are canonical?
3. Which components are implemented?
4. Which components are simulated?
5. Which validation commands must pass?
6. What files should not be changed casually?

CLAUDE.md is intended for maintainers and future AI agents.

## docs/ Contract

docs/ exists to answer:

1. Why is it designed this way?
2. What tradeoffs were made?
3. What is measured versus modeled?
4. What assumptions exist?
5. What limitations remain?
6. What future work is possible?

docs/ explains architecture and rationale rather than usage.

## Documentation Principles

Code > Artifacts > README > CLAUDE.md > docs/

Never reverse this order.

Never infer unsupported features.

Never create claims unsupported by code or artifacts.

Prefer conservative wording.

Call synthetic benchmarks synthetic.

Call simulated systems simulated.

Distinguish measured behavior from modeled behavior.

## Git Authorship Policy

The user is the sole maintainer and owner of this repository.

AI agents may modify files as requested.

AI agents must not add AI authorship metadata.

Never add:

* Co-Authored-By entries
* Co-authored-by trailers
* Claude authorship metadata
* AI signatures
* Generated-by-AI footers
* any metadata that makes an AI system appear as a repository contributor

Commit policy:

* By default, do not run git commit.
* If the user explicitly asks in the current conversation to commit, an AI agent may run git add and git commit.
* Commits must use the machine's global Git identity (`git config --global user.name` and `git config --global user.email`).
* Commits created by an AI agent must use the user's configured git author and committer identity.
* Never set author or committer identity to Claude, Anthropic, or any AI/bot identity.
* Commit messages must not mention AI authorship unless the user explicitly asks.
* Before committing, show git status and the staged diff summary when practical.

Push policy:

* By default, do not run git push.
* Only run git push if the user explicitly asks in the current conversation.
* Pushes must use the user's machine/account Git authentication, never a Claude/Anthropic/bot identity.
* Never force-push unless the user explicitly asks for a force push and the reason is explained.

History policy:

* Do not create branches, rewrite history, rebase, reset, or amend commits unless the user explicitly asks in the current conversation.
* Never rewrite public history without explicit user approval.

Ownership rule:

* The user remains the sole author/maintainer for portfolio presentation purposes.
* No AI system should appear as a repository contributor.
