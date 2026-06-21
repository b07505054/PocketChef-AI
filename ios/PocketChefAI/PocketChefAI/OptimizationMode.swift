import Foundation
import CoreML
import CoreGraphics

enum OptimizationMode: String, CaseIterable, Identifiable {
    case baseline = "Baseline"
    case runtime = "Runtime"
    case compiler = "Compiler"
    case compression = "Compression"
    case combined = "Combined"

    var id: String { rawValue }

    var legacyModelCandidates: [String] {
        switch self {
        case .baseline:
            return ["yolo_food_s_seg_fp32"]
        case .runtime:
            return ["yolo_food_s_seg_fp32"]
        case .compiler:
            return ["yolo_food_s_seg_fp32"]
        case .compression:
            return [
                "yolo_food_s_seg_int8",
                "yolo_food_s_seg_pruned",
                "yolo_food_s_seg_fp16",
                "yolo_food_s_seg_fp32"
            ]
        case .combined:
            return [
                "yolo_food_s_seg_int8",
                "yolo_food_s_seg_pruned",
                "yolo_food_s_seg_fp16",
                "yolo_food_s_seg_fp32"
            ]
        }
    }

    var preferredComputeUnits: MLComputeUnits {
        switch self {
        case .baseline:
            return .cpuAndGPU
        case .runtime, .combined:
            return .all
        case .compiler, .compression:
            return .cpuAndGPU
        }
    }

    var segmenterProfileName: String {
        switch self {
        case .baseline: return "Baseline segmentation"
        case .runtime: return "Runtime-optimized segmentation"
        case .compiler: return "Compiler-optimized segmentation"
        case .compression: return "Compressed segmentation model path"
        case .combined: return "Combined optimized segmentation"
        }
    }

    var optimizationStack: String {
        switch self {
        case .baseline:
            return "default YOLO-Seg food segmentation | policy=baseline Core ML + default bbox-cropped mask decode"
        case .runtime:
            return "runtime acceleration: same YOLO-Seg model with Core ML computeUnits=.all"
        case .compiler:
            return "compiler acceleration: artifact-backed bbox-cropped mask decode + stricter threshold"
        case .compression:
            return "model compression: quantization + pruning candidate path, fp32 fallback"
        case .combined:
            return "runtime + compiler + compression all enabled, fp32 fallback"
        }
    }

    var yoloSegMaskThreshold: Double {
        switch self {
        case .baseline: return 0.52
        case .runtime: return 0.52
        case .compiler: return 0.55
        case .compression: return 0.56
        case .combined: return 0.55
        }
    }

    var segmenterMaskThreshold: Float {
        Float(yoloSegMaskThreshold)
    }

    var yoloSegMinActiveRatio: CGFloat {
        switch self {
        case .baseline, .runtime: return 0.04
        case .compiler, .compression, .combined: return 0.08
        }
    }

    var postprocessPolicyName: String {
        switch self {
        case .baseline:
            return "baseline bbox-crop mask decode"
        case .runtime:
            return "same postprocess as baseline; runtime policy changes compute scheduling"
        case .compiler:
            return "compiler-lowered scalar/SIMD mask decode"
        case .compression:
            return "quantization/pruning candidate + stricter mask decode"
        case .combined:
            return "compiler-lowered scalar/SIMD postprocess + runtime compute scheduling"
        }
    }

    var prefersSIMDMaskPostprocess: Bool {
        switch self {
        case .compiler, .combined:
            return true
        case .baseline, .runtime, .compression:
            return false
        }
    }

    var policySummary: String {
        switch self {
        case .baseline:
            return "Input=iPhone snapshot | decision=default Core ML path | metric=baseline p50/p95/FPS"
        case .runtime:
            return "Run policy: computeUnits=.all from runtime evidence | metric=p50/p95/FPS delta"
        case .compiler:
            return "Comp policy: scalar/SIMD mask decode lowering | artifact=mask_postprocess_lowering_report"
        case .compression:
            return "Zip policy: quantization/pruning candidates | metric=size/latency/mask stability"
        case .combined:
            return "All policy: runtime computeUnits=.all + compiler-lowered scalar/SIMD postprocess"
        }
    }

    var segmenterDilationRadius: Int {
        switch self {
        case .baseline, .runtime, .compiler: return 1
        case .compression: return 0
        case .combined: return 2
        }
    }

    var segmenterMaxObjects: Int {
        switch self {
        case .baseline, .runtime, .compiler, .compression, .combined: return 1
        }
    }

    var segmenterContourSamples: Int {
        switch self {
        case .baseline: return 72
        case .runtime: return 40
        case .compiler: return 40
        case .compression: return 28
        case .combined: return 48
        }
    }

    var shortName: String {
        switch self {
        case .baseline: return "Base"
        case .runtime: return "Run"
        case .compiler: return "Comp"
        case .compression: return "Zip"
        case .combined: return "All"
        }
    }
}

extension MLComputeUnits {
    var label: String {
        switch self {
        case .cpuOnly: return "CPU"
        case .cpuAndGPU: return "CPU+GPU"
        case .cpuAndNeuralEngine: return "CPU+ANE"
        case .all: return "CPU+GPU+ANE"
        @unknown default: return "Core ML"
        }
    }
}
