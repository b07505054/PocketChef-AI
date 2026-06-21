import CoreGraphics
import CoreML
import Foundation

enum MaskPostprocessBackend: String {
    case scalarCPU = "scalar_cpu"
    case simdCPU = "simd_cpu"
}

enum MaskPostprocessFallbackReason: String {
    case none = "none"
    case invalidPrototypeShape = "invalid_prototype_shape"
    case coefficientCountNot32 = "coefficient_count_not_32"
    case unsupportedStrideLayout = "unsupported_stride_layout"
    case cropTooSmall = "crop_too_small"
    case simdDisabledByPolicy = "simd_disabled_by_policy"
    case emptyMaskFallback = "empty_mask_fallback"
    case minActiveRatioFallback = "min_active_ratio_fallback"
    case cropFailed = "crop_failed"
}

struct MaskPostprocessDiagnostics {
    let selectedBackend: MaskPostprocessBackend
    let fallbackReason: MaskPostprocessFallbackReason
    let decodeLatencyMs: Double
    let simdEligible: Bool
    let prototypeLayout: String
    let correctnessMode: String
}

struct MaskPostprocessResult {
    let boundingBox: CGRect
    let mask: DetectionMask
    let areaRatio: CGFloat
    let maskFullBytes: Int
    let diagnostics: MaskPostprocessDiagnostics
}

final class MaskPostprocessRuntime {
    private let coefficientCount = 32

    func decode(
        coefficients: [Float],
        prototypes: MLMultiArray,
        fallbackBox: CGRect,
        mode: OptimizationMode
    ) -> MaskPostprocessResult? {
        let start = CFAbsoluteTimeGetCurrent()
        let legality = legalityCheck(
            coefficients: coefficients,
            prototypes: prototypes,
            fallbackBox: fallbackBox,
            mode: mode
        )
        let backend = legality.simdEligible ? MaskPostprocessBackend.simdCPU : .scalarCPU

        guard let shape = legality.shape else {
            return nil
        }

        let decoded = rasterize(
            coefficients: coefficients,
            prototypes: prototypes,
            shape: shape,
            fallbackBox: fallbackBox,
            mode: mode,
            backend: backend
        )

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
        guard var decoded else { return nil }
        let diagnostics = MaskPostprocessDiagnostics(
            selectedBackend: backend,
            fallbackReason: decoded.fallbackReason ?? legality.fallbackReason,
            decodeLatencyMs: elapsed,
            simdEligible: legality.simdEligible,
            prototypeLayout: legality.prototypeLayout,
            correctnessMode: backend == .scalarCPU ? "scalar_reference" : "simd_candidate"
        )
        decoded.resultDiagnostics = diagnostics
        return decoded.result
    }

    private func legalityCheck(
        coefficients: [Float],
        prototypes: MLMultiArray,
        fallbackBox: CGRect,
        mode: OptimizationMode
    ) -> MaskPostprocessLegality {
        guard coefficients.count == coefficientCount else {
            return MaskPostprocessLegality(
                shape: nil,
                simdEligible: false,
                fallbackReason: .coefficientCountNot32,
                prototypeLayout: "unknown"
            )
        }
        guard prototypes.shape.count == 4 else {
            return MaskPostprocessLegality(
                shape: nil,
                simdEligible: false,
                fallbackReason: .invalidPrototypeShape,
                prototypeLayout: "unknown"
            )
        }
        let channels = prototypes.shape[1].intValue
        let height = prototypes.shape[2].intValue
        let width = prototypes.shape[3].intValue
        guard channels == coefficientCount, width > 2, height > 2 else {
            return MaskPostprocessLegality(
                shape: nil,
                simdEligible: false,
                fallbackReason: .invalidPrototypeShape,
                prototypeLayout: "NCHW"
            )
        }

        let crop = cropBounds(for: fallbackBox, width: width, height: height)
        guard crop.maxX > crop.minX, crop.maxY > crop.minY else {
            return MaskPostprocessLegality(
                shape: MaskPostprocessShape(width: width, height: height, crop: crop),
                simdEligible: false,
                fallbackReason: .cropTooSmall,
                prototypeLayout: "NCHW"
            )
        }

        let strides = prototypes.strides.map(\.intValue)
        let supportedLayout = strides.count == 4 && strides[3] == 1
        guard supportedLayout else {
            return MaskPostprocessLegality(
                shape: MaskPostprocessShape(width: width, height: height, crop: crop),
                simdEligible: false,
                fallbackReason: .unsupportedStrideLayout,
                prototypeLayout: "unsupported"
            )
        }

        let simdEligible = mode.prefersSIMDMaskPostprocess
        return MaskPostprocessLegality(
            shape: MaskPostprocessShape(width: width, height: height, crop: crop),
            simdEligible: simdEligible,
            fallbackReason: simdEligible ? .none : .simdDisabledByPolicy,
            prototypeLayout: "NCHW"
        )
    }

    private func rasterize(
        coefficients: [Float],
        prototypes: MLMultiArray,
        shape: MaskPostprocessShape,
        fallbackBox: CGRect,
        mode: OptimizationMode,
        backend: MaskPostprocessBackend
    ) -> MaskPostprocessInternalResult? {
        var fullMask = [UInt8](repeating: 0, count: shape.width * shape.height)
        var activeCount = 0

        for y in shape.crop.minY...shape.crop.maxY {
            for x in shape.crop.minX...shape.crop.maxX {
                let alpha: UInt8
                switch backend {
                case .scalarCPU:
                    alpha = scalarMaskAlpha(
                        coefficients: coefficients,
                        prototypes: prototypes,
                        x: x,
                        y: y,
                        threshold: mode.yoloSegMaskThreshold
                    )
                case .simdCPU:
                    alpha = simdMaskAlpha(
                        coefficients: coefficients,
                        prototypes: prototypes,
                        x: x,
                        y: y,
                        threshold: mode.yoloSegMaskThreshold
                    )
                }
                guard alpha > 0 else { continue }
                fullMask[y * shape.width + x] = alpha
                activeCount += 1
            }
        }

        let refined = refinedMask(fullMask, width: shape.width, height: shape.height)
        fullMask = refined.mask
        activeCount = refined.activeCount

        if activeCount == 0 {
            return fallbackMask(
                for: fallbackBox,
                maskWidth: shape.width,
                maskHeight: shape.height,
                reason: .emptyMaskFallback
            )
        }

        let boxPixelArea = max((shape.crop.maxX - shape.crop.minX + 1) * (shape.crop.maxY - shape.crop.minY + 1), 1)
        if CGFloat(activeCount) / CGFloat(boxPixelArea) < mode.yoloSegMinActiveRatio {
            return fallbackMask(
                for: fallbackBox,
                maskWidth: shape.width,
                maskHeight: shape.height,
                reason: .minActiveRatioFallback
            )
        }

        guard let cropped = croppedMask(
            fullMask,
            maskWidth: shape.width,
            maskHeight: shape.height,
            cropBox: fallbackBox
        ) else {
            return nil
        }

        return MaskPostprocessInternalResult(
            boundingBox: cropped.boundingBox,
            mask: cropped.mask,
            areaRatio: cropped.areaRatio,
            maskFullBytes: fullMask.count,
            fallbackReason: .none
        )
    }

    private func scalarMaskAlpha(
        coefficients: [Float],
        prototypes: MLMultiArray,
        x: Int,
        y: Int,
        threshold: Double
    ) -> UInt8 {
        var sum: Float = 0
        for index in 0..<coefficientCount {
            sum += coefficients[index] * value(prototypes, 0, index, y, x)
        }
        return alpha(from: sum, threshold: threshold)
    }

    private func simdMaskAlpha(
        coefficients: [Float],
        prototypes: MLMultiArray,
        x: Int,
        y: Int,
        threshold: Double
    ) -> UInt8 {
        var sum = SIMD8<Float>.zero
        for base in stride(from: 0, to: coefficientCount, by: 8) {
            let coeff = SIMD8<Float>(
                coefficients[base],
                coefficients[base + 1],
                coefficients[base + 2],
                coefficients[base + 3],
                coefficients[base + 4],
                coefficients[base + 5],
                coefficients[base + 6],
                coefficients[base + 7]
            )
            let proto = SIMD8<Float>(
                value(prototypes, 0, base, y, x),
                value(prototypes, 0, base + 1, y, x),
                value(prototypes, 0, base + 2, y, x),
                value(prototypes, 0, base + 3, y, x),
                value(prototypes, 0, base + 4, y, x),
                value(prototypes, 0, base + 5, y, x),
                value(prototypes, 0, base + 6, y, x),
                value(prototypes, 0, base + 7, y, x)
            )
            sum += coeff * proto
        }
        let reduced = sum[0] + sum[1] + sum[2] + sum[3] + sum[4] + sum[5] + sum[6] + sum[7]
        return alpha(from: reduced, threshold: threshold)
    }

    private func alpha(from sum: Float, threshold: Double) -> UInt8 {
        let probability = 1.0 / (1.0 + exp(-Double(sum)))
        guard probability >= threshold else { return 0 }
        let shaped = min(max((probability - threshold) / (1 - threshold), 0), 1)
        return UInt8(70 + shaped * 125)
    }

    private func refinedMask(_ mask: [UInt8], width: Int, height: Int) -> (mask: [UInt8], activeCount: Int) {
        guard width > 2, height > 2, mask.count == width * height else {
            return (mask, mask.reduce(0) { $0 + ($1 > 0 ? 1 : 0) })
        }

        var output = mask
        var activeCount = 0

        for y in 0..<height {
            for x in 0..<width {
                let index = y * width + x
                guard mask[index] > 0 else {
                    output[index] = 0
                    continue
                }

                var neighbors = 0
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        let ny = y + dy
                        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
                        if mask[ny * width + nx] > 0 {
                            neighbors += 1
                        }
                    }
                }

                if neighbors >= 3 {
                    output[index] = mask[index]
                    activeCount += 1
                } else {
                    output[index] = 0
                }
            }
        }

        return (output, activeCount)
    }

    private func croppedMask(
        _ fullMask: [UInt8],
        maskWidth: Int,
        maskHeight: Int,
        cropBox: CGRect
    ) -> (boundingBox: CGRect, mask: DetectionMask, areaRatio: CGFloat)? {
        let crop = cropBounds(for: cropBox, width: maskWidth, height: maskHeight)
        guard crop.maxX > crop.minX, crop.maxY > crop.minY else { return nil }

        let cropWidth = crop.maxX - crop.minX + 1
        let cropHeight = crop.maxY - crop.minY + 1
        var alpha = [UInt8](repeating: 0, count: cropWidth * cropHeight)
        var activeCount = 0

        for y in crop.minY...crop.maxY {
            for x in crop.minX...crop.maxX {
                let sourceAlpha = fullMask[y * maskWidth + x]
                guard sourceAlpha > 0 else { continue }
                let cropIndex = (y - crop.minY) * cropWidth + (x - crop.minX)
                alpha[cropIndex] = sourceAlpha
                activeCount += 1
            }
        }

        guard activeCount > 0 else { return nil }
        let displayBox = CGRect(
            x: CGFloat(crop.minX) / CGFloat(maskWidth),
            y: 1 - CGFloat(crop.maxY + 1) / CGFloat(maskHeight),
            width: CGFloat(cropWidth) / CGFloat(maskWidth),
            height: CGFloat(cropHeight) / CGFloat(maskHeight)
        )

        return (
            displayBox,
            DetectionMask(width: cropWidth, height: cropHeight, alpha: alpha),
            CGFloat(activeCount) / CGFloat(maskWidth * maskHeight)
        )
    }

    private func fallbackMask(
        for rawBox: CGRect,
        maskWidth: Int,
        maskHeight: Int,
        reason: MaskPostprocessFallbackReason
    ) -> MaskPostprocessInternalResult? {
        let crop = cropBounds(for: rawBox, width: maskWidth, height: maskHeight)
        guard crop.maxX > crop.minX, crop.maxY > crop.minY else { return nil }

        let width = crop.maxX - crop.minX + 1
        let height = crop.maxY - crop.minY + 1
        var alpha = [UInt8](repeating: 0, count: width * height)
        let centerX = CGFloat(width - 1) / 2
        let centerY = CGFloat(height - 1) / 2
        let radiusX = max(centerX, 1)
        let radiusY = max(centerY, 1)

        for y in 0..<height {
            for x in 0..<width {
                let dx = (CGFloat(x) - centerX) / radiusX
                let dy = (CGFloat(y) - centerY) / radiusY
                let distance = sqrt(dx * dx + dy * dy)
                guard distance <= 1 else { continue }
                alpha[y * width + x] = UInt8(72 + max(0, 1 - distance) * 72)
            }
        }

        let displayBox = CGRect(
            x: CGFloat(crop.minX) / CGFloat(maskWidth),
            y: 1 - CGFloat(crop.maxY + 1) / CGFloat(maskHeight),
            width: CGFloat(width) / CGFloat(maskWidth),
            height: CGFloat(height) / CGFloat(maskHeight)
        )

        return MaskPostprocessInternalResult(
            boundingBox: displayBox,
            mask: DetectionMask(width: width, height: height, alpha: alpha),
            areaRatio: displayBox.width * displayBox.height,
            maskFullBytes: maskWidth * maskHeight,
            fallbackReason: reason
        )
    }

    private func cropBounds(for box: CGRect, width: Int, height: Int) -> MaskPostprocessCrop {
        MaskPostprocessCrop(
            minX: max(Int(floor(box.minX * CGFloat(width))), 0),
            maxX: min(Int(ceil(box.maxX * CGFloat(width))) - 1, width - 1),
            minY: max(Int(floor(box.minY * CGFloat(height))), 0),
            maxY: min(Int(ceil(box.maxY * CGFloat(height))) - 1, height - 1)
        )
    }

    private func value(_ array: MLMultiArray, _ indices: Int...) -> Float {
        array[indices.map { NSNumber(value: $0) }].floatValue
    }
}

private struct MaskPostprocessCrop {
    let minX: Int
    let maxX: Int
    let minY: Int
    let maxY: Int
}

private struct MaskPostprocessShape {
    let width: Int
    let height: Int
    let crop: MaskPostprocessCrop
}

private struct MaskPostprocessLegality {
    let shape: MaskPostprocessShape?
    let simdEligible: Bool
    let fallbackReason: MaskPostprocessFallbackReason
    let prototypeLayout: String
}

private struct MaskPostprocessInternalResult {
    let boundingBox: CGRect
    let mask: DetectionMask
    let areaRatio: CGFloat
    let maskFullBytes: Int
    let fallbackReason: MaskPostprocessFallbackReason?
    var resultDiagnostics: MaskPostprocessDiagnostics?

    var result: MaskPostprocessResult? {
        guard let resultDiagnostics else { return nil }
        return MaskPostprocessResult(
            boundingBox: boundingBox,
            mask: mask,
            areaRatio: areaRatio,
            maskFullBytes: maskFullBytes,
            diagnostics: resultDiagnostics
        )
    }
}
