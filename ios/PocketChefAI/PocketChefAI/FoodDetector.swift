import CoreML
import CoreVideo
import Foundation
import Vision

final class FoodDetector {
    private var legacyRequest: VNCoreMLRequest?
    private(set) var backendName = "No Core ML model loaded"
    private(set) var modelName = "missing_yolo_food_model"
    private(set) var bundleInventory = "Bundle models: scanning..."
    private let confidenceThreshold: Float = 0.45
    private let modelInputSize: Double = 640.0
    private let foodClassNames: Set<String> = [
        "banana", "apple", "sandwich", "orange", "broccoli", "carrot",
        "hot dog", "pizza", "donut", "cake", "bowl"
    ]
    private let cocoLabels = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck",
        "boat", "traffic light", "fire hydrant", "stop sign", "parking meter", "bench",
        "bird", "cat", "dog", "horse", "sheep", "cow", "elephant", "bear", "zebra",
        "giraffe", "backpack", "umbrella", "handbag", "tie", "suitcase", "frisbee",
        "skis", "snowboard", "sports ball", "kite", "baseball bat", "baseball glove",
        "skateboard", "surfboard", "tennis racket", "bottle", "wine glass", "cup",
        "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
        "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch",
        "potted plant", "bed", "dining table", "toilet", "tv", "laptop", "mouse",
        "remote", "keyboard", "cell phone", "microwave", "oven", "toaster", "sink",
        "refrigerator", "book", "clock", "vase", "scissors", "teddy bear", "hair drier",
        "toothbrush"
    ]

    init(mode: OptimizationMode) {
        configure(mode: mode)
    }

    func configure(mode: OptimizationMode) {
        legacyRequest = nil
        bundleInventory = makeBundleInventory()
        legacyRequest = loadLegacyRequest(mode: mode)
    }

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mode: OptimizationMode,
        promptPoint: CGPoint?
    ) -> DetectionFrame {
        let start = CFAbsoluteTimeGetCurrent()

        return detectWithYOLOSeg(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            mode: mode,
            promptPoint: promptPoint,
            start: start
        )
    }

    private func detectWithYOLOSeg(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mode: OptimizationMode,
        promptPoint: CGPoint?,
        start: CFAbsoluteTime
    ) -> DetectionFrame {
        var detections: [Detection] = []

        if let legacyRequest {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

            do {
                try handler.perform([legacyRequest])
                detections = selectTargetDetection(
                    from: parseVisionResults(legacyRequest.results, mode: mode),
                    promptPoint: promptPoint,
                    limit: mode.segmenterMaxObjects
                )
            } catch {
                backendName = "YOLO-Seg inference failed"
                modelName = error.localizedDescription
            }
        }

        let latency = (CFAbsoluteTimeGetCurrent() - start) * 1000
        return DetectionFrame(
            detections: detections,
            latencyMs: latency,
            mode: mode,
            backend: backendName,
            modelName: yoloSegModelName(for: mode, promptPoint: promptPoint),
            timestamp: Date()
        )
    }

    private func yoloSegModelName(for mode: OptimizationMode, promptPoint: CGPoint?) -> String {
        [
            "segmenter=\(modelName)",
            "classifier=off",
            promptDescription(promptPoint),
            "optimization=\(mode.optimizationStack)",
            "postprocess=\(mode.postprocessPolicyName)",
            String(format: "mask_threshold=%.2f", mode.yoloSegMaskThreshold)
        ].joined(separator: " | ")
    }

    private func promptDescription(_ point: CGPoint?) -> String {
        guard let point else { return "prompt=none" }
        return String(format: "prompt=(%.3f, %.3f)", point.x, point.y)
    }

    private func loadLegacyRequest(mode: OptimizationMode) -> VNCoreMLRequest? {
        var loadErrors: [String] = []

        for name in mode.legacyModelCandidates {
            if let url = modelURL(named: name) {
                do {
                    let config = MLModelConfiguration()
                    config.computeUnits = mode.preferredComputeUnits
                    let model = try MLModel(contentsOf: url, configuration: config)
                    let visionModel = try VNCoreMLModel(for: model)
                    let request = VNCoreMLRequest(model: visionModel)
                    request.imageCropAndScaleOption = .scaleFill
                    backendName = "YOLO-Seg Vision/Core ML (\(mode.preferredComputeUnits.label))"
                    modelName = name
                    return request
                } catch {
                    loadErrors.append("\(name): \(error.localizedDescription)")
                    continue
                }
            }
        }

        backendName = loadErrors.isEmpty
            ? "No Core ML model loaded"
            : "Core ML load failed"
        modelName = loadErrors.isEmpty
            ? "\(mode.legacyModelCandidates.joined(separator: ", ")) not found"
            : loadErrors.joined(separator: " | ")
        return nil
    }

    private func selectTargetDetection(
        from detections: [Detection],
        promptPoint: CGPoint?,
        limit: Int
    ) -> [Detection] {
        guard !detections.isEmpty else { return [] }

        guard let promptPoint else {
            return Array(detections.sorted { $0.confidence > $1.confidence }.prefix(limit))
        }

        let hits = detections.filter { targetHit($0, promptPoint: promptPoint) }
        guard !hits.isEmpty else { return [] }

        return hits
            .sorted { targetRank($0, promptPoint: promptPoint) > targetRank($1, promptPoint: promptPoint) }
            .prefix(limit)
            .map { promptAlignedDetection($0, promptPoint: promptPoint) }
    }

    private func targetHit(_ detection: Detection, promptPoint: CGPoint) -> Bool {
        if detection.mask?.contains(promptPoint, in: detection.boundingBox) == true {
            return true
        }
        return detection.boundingBox.insetBy(dx: -0.025, dy: -0.025).contains(promptPoint)
    }

    private func targetRank(_ detection: Detection, promptPoint: CGPoint) -> CGFloat {
        let box = detection.boundingBox
        let maskContainsPrompt = detection.mask?.contains(promptPoint, in: box) == true
        let boxContainsPrompt = box.insetBy(dx: -0.025, dy: -0.025).contains(promptPoint)
        let center = CGPoint(x: box.midX, y: box.midY)
        let distance = hypot(center.x - promptPoint.x, center.y - promptPoint.y)
        let area = box.width * box.height

        return CGFloat(detection.confidence)
            + (maskContainsPrompt ? 3.0 : 0)
            + (boxContainsPrompt ? 1.2 : 0)
            + min(area * 1.2, 0.35)
            - min(distance * 1.4, 1.0)
    }

    private func promptAlignedDetection(_ detection: Detection, promptPoint: CGPoint) -> Detection {
        guard
            let mask = detection.mask,
            let centroid = mask.normalizedCentroid,
            detection.boundingBox.insetBy(dx: -0.035, dy: -0.035).contains(promptPoint)
        else {
            return detection
        }

        let box = detection.boundingBox
        let centroidInImage = CGPoint(
            x: box.minX + centroid.x * box.width,
            y: box.maxY - centroid.y * box.height
        )
        let rawDX = promptPoint.x - centroidInImage.x
        let rawDY = promptPoint.y - centroidInImage.y
        let maxDX = max(box.width * 0.22, 0.015)
        let maxDY = max(box.height * 0.22, 0.015)
        let dx = min(max(rawDX * 0.75, -maxDX), maxDX)
        let dy = min(max(rawDY * 0.75, -maxDY), maxDY)

        guard abs(dx) > 0.004 || abs(dy) > 0.004 else {
            return detection
        }

        let shiftedBox = CGRect(
            x: min(max(box.minX + dx, 0), max(1 - box.width, 0)),
            y: min(max(box.minY + dy, 0), max(1 - box.height, 0)),
            width: box.width,
            height: box.height
        )

        return Detection(
            label: detection.label,
            confidence: detection.confidence,
            boundingBox: shiftedBox,
            maskPolygon: detection.maskPolygon,
            mask: mask,
            maskAreaRatio: detection.maskAreaRatio
        )
    }

    private func modelURL(named name: String) -> URL? {
        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        for ext in extensions {
            if let rootURL = Bundle.main.url(forResource: name, withExtension: ext) {
                return rootURL
            }
            if let nestedURL = Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "models"
            ) {
                return nestedURL
            }
        }
        return nil
    }

    private func makeBundleInventory() -> String {
        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        let subdirectories: [String?] = [nil, "models"]
        var names = Set<String>()

        for subdirectory in subdirectories {
            for ext in extensions {
                let urls = Bundle.main.urls(
                    forResourcesWithExtension: ext,
                    subdirectory: subdirectory
                ) ?? []

                urls.forEach { url in
                    let prefix = subdirectory.map { "\($0)/" } ?? ""
                    names.insert("\(prefix)\(url.lastPathComponent)")
                }
            }
        }

        if let resourceURL = Bundle.main.resourceURL,
           let enumerator = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where extensions.contains(url.pathExtension) {
                names.insert(url.lastPathComponent)
            }
        }

        if names.isEmpty {
            return "Bundle models: none"
        }

        return "Bundle models: \(names.sorted().prefix(8).joined(separator: ", "))"
    }

    private func parseVisionResults(_ results: [Any]?, mode: OptimizationMode) -> [Detection] {
        if let observations = results as? [VNRecognizedObjectObservation] {
            return observations.prefix(12).compactMap { observation in
                guard let best = observation.labels.first else { return nil }
                guard foodClassNames.contains(best.identifier) else { return nil }
                return Detection(
                    label: best.identifier,
                    confidence: best.confidence,
                    boundingBox: observation.boundingBox
                )
            }
        }

        guard let featureObservations = results as? [VNCoreMLFeatureValueObservation] else {
            return []
        }

        if let segDetections = parseSegmentationResults(featureObservations, mode: mode) {
            return segDetections
        }

        let coordinates = featureObservations
            .first { $0.featureName == "coordinates" }?
            .featureValue
            .multiArrayValue
        let confidence = featureObservations
            .first { $0.featureName == "confidence" }?
            .featureValue
            .multiArrayValue

        guard let coordinates, let confidence else { return [] }
        return parseYOLODetections(coordinates: coordinates, confidence: confidence)
    }

    private func parseYOLODetections(
        coordinates: MLMultiArray,
        confidence: MLMultiArray
    ) -> [Detection] {
        guard confidence.shape.count == 2, coordinates.shape.count == 2 else {
            return []
        }

        let detectionCount = confidence.shape[0].intValue
        let classCount = confidence.shape[1].intValue
        var detections: [Detection] = []

        for index in 0..<detectionCount {
            var bestClass = -1
            var bestScore: Float = 0

            for classIndex in 0..<classCount {
                let score = confidence[[index as NSNumber, classIndex as NSNumber]].floatValue
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            guard bestScore >= confidenceThreshold else { continue }
            guard bestClass >= 0, bestClass < cocoLabels.count else { continue }

            let label = cocoLabels[bestClass]
            guard foodClassNames.contains(label) else { continue }

            let centerX = coordinates[[index as NSNumber, 0]].doubleValue
            let centerY = coordinates[[index as NSNumber, 1]].doubleValue
            let width = coordinates[[index as NSNumber, 2]].doubleValue
            let height = coordinates[[index as NSNumber, 3]].doubleValue

            let rect = CGRect(
                x: clamp01(centerX - width / 2),
                y: clamp01(centerY - height / 2),
                width: clamp01(width),
                height: clamp01(height)
            )
            detections.append(Detection(
                label: label,
                confidence: bestScore,
                boundingBox: rect
            ))
        }

        return Array(detections.sorted { $0.confidence > $1.confidence }.prefix(12))
    }

    private func parseSegmentationResults(
        _ observations: [VNCoreMLFeatureValueObservation],
        mode: OptimizationMode
    ) -> [Detection]? {
        let arrays = observations.compactMap { $0.featureValue.multiArrayValue }
        guard
            let rawOutput = arrays.first(where: { $0.shape.count == 3 && $0.shape[1].intValue >= 116 }),
            let prototypes = arrays.first(where: { $0.shape.count == 4 && $0.shape[1].intValue == 32 })
        else {
            return nil
        }

        let channelCount = rawOutput.shape[1].intValue
        let candidateCount = rawOutput.shape[2].intValue
        guard channelCount >= 116 else { return [] }

        var candidates: [SegCandidate] = []

        for index in 0..<candidateCount {
            var bestClass = -1
            var bestScore: Float = 0

            for classIndex in 0..<cocoLabels.count {
                let score = value(rawOutput, 0, 4 + classIndex, index)
                if score > bestScore {
                    bestScore = score
                    bestClass = classIndex
                }
            }

            guard bestScore >= confidenceThreshold else { continue }
            guard bestClass >= 0, bestClass < cocoLabels.count else { continue }

            let label = cocoLabels[bestClass]
            guard foodClassNames.contains(label) else { continue }

            let centerX = Double(value(rawOutput, 0, 0, index)) / modelInputSize
            let centerY = Double(value(rawOutput, 0, 1, index)) / modelInputSize
            let width = Double(value(rawOutput, 0, 2, index)) / modelInputSize
            let height = Double(value(rawOutput, 0, 3, index)) / modelInputSize
            let rawBox = CGRect(
                x: clamp01(centerX - width / 2),
                y: clamp01(centerY - height / 2),
                width: clamp01(width),
                height: clamp01(height)
            )
            let displayBox = CGRect(
                x: rawBox.minX,
                y: clamp01(1.0 - Double(rawBox.maxY)),
                width: rawBox.width,
                height: rawBox.height
            )

            var coefficients: [Float] = []
            for maskIndex in 0..<32 {
                coefficients.append(value(rawOutput, 0, 84 + maskIndex, index))
            }

            candidates.append(SegCandidate(
                label: label,
                confidence: bestScore,
                boundingBox: displayBox,
                maskBox: rawBox,
                maskCoefficients: coefficients
            ))
        }

        let kept = applyNMS(to: candidates.sorted { $0.confidence > $1.confidence }, limit: 8)
        return kept.compactMap { candidate in
            let raster = maskRaster(
                coefficients: candidate.maskCoefficients,
                prototypes: prototypes,
                fallbackBox: candidate.maskBox,
                mode: mode
            )

            guard let raster else {
                return Detection(
                    label: candidate.label,
                    confidence: candidate.confidence,
                    boundingBox: candidate.boundingBox
                )
            }

            return Detection(
                label: candidate.label,
                confidence: candidate.confidence,
                boundingBox: raster.boundingBox,
                mask: raster.mask,
                maskAreaRatio: raster.areaRatio
            )
        }
    }

    private func maskRaster(
        coefficients: [Float],
        prototypes: MLMultiArray,
        fallbackBox: CGRect,
        mode: OptimizationMode
    ) -> (boundingBox: CGRect, mask: DetectionMask, areaRatio: CGFloat)? {
        guard prototypes.shape.count == 4, coefficients.count == 32 else { return nil }

        let maskWidth = prototypes.shape[3].intValue
        let maskHeight = prototypes.shape[2].intValue
        guard maskWidth > 2, maskHeight > 2 else { return nil }

        let cropMinX = max(Int(floor(fallbackBox.minX * CGFloat(maskWidth))), 0)
        let cropMaxX = min(Int(ceil(fallbackBox.maxX * CGFloat(maskWidth))) - 1, maskWidth - 1)
        let cropMinY = max(Int(floor(fallbackBox.minY * CGFloat(maskHeight))), 0)
        let cropMaxY = min(Int(ceil(fallbackBox.maxY * CGFloat(maskHeight))) - 1, maskHeight - 1)
        guard cropMaxX > cropMinX, cropMaxY > cropMinY else { return nil }

        var fullMask = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        var activeCount = 0

        for y in cropMinY...cropMaxY {
            for x in cropMinX...cropMaxX {
                let alpha = maskAlpha(
                    coefficients: coefficients,
                    prototypes: prototypes,
                    x: x,
                    y: y,
                    threshold: mode.yoloSegMaskThreshold
                )
                guard alpha > 0 else { continue }
                fullMask[y * maskWidth + x] = alpha
                activeCount += 1
            }
        }
        let refined = refinedMask(fullMask, width: maskWidth, height: maskHeight)
        fullMask = refined.mask
        activeCount = refined.activeCount

        if activeCount == 0 {
            return fallbackMask(for: fallbackBox, maskWidth: maskWidth, maskHeight: maskHeight)
        }

        let boxPixelArea = max((cropMaxX - cropMinX + 1) * (cropMaxY - cropMinY + 1), 1)
        if CGFloat(activeCount) / CGFloat(boxPixelArea) < mode.yoloSegMinActiveRatio {
            return fallbackMask(for: fallbackBox, maskWidth: maskWidth, maskHeight: maskHeight)
        }

        return croppedMask(
            fullMask,
            maskWidth: maskWidth,
            maskHeight: maskHeight,
            cropBox: fallbackBox
        )
    }

    private func maskAlpha(
        coefficients: [Float],
        prototypes: MLMultiArray,
        x: Int,
        y: Int,
        threshold: Double
    ) -> UInt8 {
        var sum: Float = 0
        for index in 0..<32 {
            sum += coefficients[index] * value(prototypes, 0, index, y, x)
        }
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
        let minX = max(Int(floor(cropBox.minX * CGFloat(maskWidth))), 0)
        let maxX = min(Int(ceil(cropBox.maxX * CGFloat(maskWidth))) - 1, maskWidth - 1)
        let minY = max(Int(floor(cropBox.minY * CGFloat(maskHeight))), 0)
        let maxY = min(Int(ceil(cropBox.maxY * CGFloat(maskHeight))) - 1, maskHeight - 1)
        guard maxX > minX, maxY > minY else { return nil }

        let cropWidth = maxX - minX + 1
        let cropHeight = maxY - minY + 1
        var alpha = [UInt8](repeating: 0, count: cropWidth * cropHeight)
        var activeCount = 0

        for y in minY...maxY {
            for x in minX...maxX {
                let sourceAlpha = fullMask[y * maskWidth + x]
                guard sourceAlpha > 0 else { continue }
                let cropIndex = (y - minY) * cropWidth + (x - minX)
                alpha[cropIndex] = sourceAlpha
                activeCount += 1
            }
        }

        guard activeCount > 0 else { return nil }
        let displayBox = CGRect(
            x: CGFloat(minX) / CGFloat(maskWidth),
            y: 1 - CGFloat(maxY + 1) / CGFloat(maskHeight),
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
        maskHeight: Int
    ) -> (boundingBox: CGRect, mask: DetectionMask, areaRatio: CGFloat)? {
        let minX = max(Int(rawBox.minX * CGFloat(maskWidth)), 0)
        let maxX = min(Int(rawBox.maxX * CGFloat(maskWidth)), maskWidth - 1)
        let minY = max(Int(rawBox.minY * CGFloat(maskHeight)), 0)
        let maxY = min(Int(rawBox.maxY * CGFloat(maskHeight)), maskHeight - 1)
        guard maxX > minX, maxY > minY else { return nil }

        let width = maxX - minX + 1
        let height = maxY - minY + 1
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
            x: CGFloat(minX) / CGFloat(maskWidth),
            y: 1 - CGFloat(maxY + 1) / CGFloat(maskHeight),
            width: CGFloat(width) / CGFloat(maskWidth),
            height: CGFloat(height) / CGFloat(maskHeight)
        )

        return (
            displayBox,
            DetectionMask(width: width, height: height, alpha: alpha),
            displayBox.width * displayBox.height
        )
    }

    private func value(_ array: MLMultiArray, _ indices: Int...) -> Float {
        array[indices.map { NSNumber(value: $0) }].floatValue
    }

    private func applyNMS(to candidates: [SegCandidate], limit: Int) -> [SegCandidate] {
        var kept: [SegCandidate] = []

        for candidate in candidates {
            guard kept.count < limit else { break }
            let overlaps = kept.contains { existing in
                existing.label == candidate.label && iou(existing.boundingBox, candidate.boundingBox) > 0.45
            }
            if !overlaps {
                kept.append(candidate)
            }
        }

        return kept
    }

    private func iou(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func clamp01(_ value: Double) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }
}

private struct SegCandidate {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let maskBox: CGRect
    let maskCoefficients: [Float]
}

private extension MLComputeUnits {
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
