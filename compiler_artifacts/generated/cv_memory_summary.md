# CV Compiler Memory Summary

Evidence type: artifact-backed estimate from `ml-graph-compiler-runtime`.

| Metric | Value |
|---|---:|
| Naive activation memory | 19.529 MB |
| Planned peak activation memory | 14.798 MB |
| Saved activation memory | 4.731 MB |
| Saved activation percent | 24.22% |

Compiler decision:

```text
MemoryPlanningPass reuses activation buffers for tensors with non-overlapping lifetimes.
```

Dashboard contract:

```text
Input: YOLO-Seg CV graph abstraction
Decision: tensor lifetime analysis + activation buffer reuse
Metric: estimated activation peak memory reduction
```

Truth boundary:

```text
Real: PocketChef imports generated compiler artifacts.
Not claimed: iPhone live-compiles the YOLO-Seg Core ML graph.
```
