# Models

Generated Core ML model packages live here.

Expected names:

```text
food_classifier_fp32.mlpackage
food_classifier_fp32.mlmodelc
fastsam_s_fp32.mlpackage
fastsam_s_fp32.mlmodelc
fastsam_x_fp32.mlpackage
fastsam_x_fp32.mlmodelc
yolo_food_s_seg_fp32.mlpackage
yolo_food_s_seg_fp32.mlmodelc
yolo_food_s_fp32.mlpackage
yolo_food_s_fp32.mlmodelc
yolo_food_fp32.mlpackage
yolo_food_fp32.mlmodelc
yolo_food_fp16.mlpackage
yolo_food_int8.mlpackage
yolo_food_pruned.mlpackage
yolo_food_distilled.mlpackage
```

Current app path:

- Primary: segmentation-only FastSAM Core ML.
- Fast path: `fastsam_s_fp32` for Base/Run and as fallback for Zip/All.
- Quality path: `fastsam_x_fp32` for Comp when available.
- Classifier: `food_classifier_fp32` is bundled but intentionally disabled while mask quality is being tuned.
- Runtime mode: Core ML compute scheduling on FastSAM-S.
- Compiler mode: FastSAM-X quality path plus fused mask postprocess, dilation fill, and contour extraction tuning.
- Compression mode: searches quantized/pruned/distilled FastSAM-S artifacts first, then falls back to `fastsam_s_fp32`.
- Fallback artifacts: YOLO segmentation/detection models remain bundled for later comparison, but the current debug path focuses on segmentation only.
- Vision foreground masks are fallback only if FastSAM fails to load.

Add compiled or packaged models to the iOS target in Xcode before real-device profiling.
