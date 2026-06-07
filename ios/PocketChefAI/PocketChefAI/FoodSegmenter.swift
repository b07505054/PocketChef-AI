import CoreML
import CoreVideo
import Foundation
import Vision

struct SegmentedObject {
    let boundingBox: CGRect
    let maskPolygon: [CGPoint]
    let areaRatio: CGFloat
    let confidence: Float
}

final class FoodSegmenter {
    private var request: VNCoreMLRequest?
    private var activeModelName = "missing_fastsam_model"
    private var loadMessage = "No FastSAM Core ML model loaded"
    private var runtimeMessage = "FastSAM has not run yet"
    private let modelInputSize: CGFloat = 640
    private let maskCoefficientCount = 32

    var backendName: String {
        request == nil ? loadMessage : "FastSAM Core ML segmentation | \(runtimeMessage)"
    }

    var modelName: String {
        request == nil ? activeModelName : activeModelName
    }

    func configure(mode: OptimizationMode) {
        var loadErrors: [String] = []
        request = nil

        for name in mode.fastSAMModelCandidates {
            guard let url = modelURL(named: name) else { continue }

            do {
                let configuration = MLModelConfiguration()
                configuration.computeUnits = mode.preferredComputeUnits
                let model = try MLModel(contentsOf: url, configuration: configuration)
                let visionModel = try VNCoreMLModel(for: model)
                let request = VNCoreMLRequest(model: visionModel)
                request.imageCropAndScaleOption = .scaleFill
                self.request = request
                activeModelName = name
                loadMessage = "Loaded \(name)"
                runtimeMessage = "FastSAM ready"
                return
            } catch {
                loadErrors.append("\(name): \(error.localizedDescription)")
            }
        }

        activeModelName = mode.fastSAMModelCandidates.joined(separator: ", ")
        loadMessage = loadErrors.isEmpty
            ? "FastSAM model not found"
            : "FastSAM load failed: \(loadErrors.joined(separator: " | "))"
        runtimeMessage = loadMessage
    }

    func segment(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mode: OptimizationMode,
        promptPoint: CGPoint?
    ) -> [SegmentedObject] {
        guard let promptPoint else {
            runtimeMessage = "Tap target object"
            return []
        }

        return segmentWithFastSAM(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            mode: mode,
            promptPoint: promptPoint
        )
    }

    private func segmentWithFastSAM(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mode: OptimizationMode,
        promptPoint: CGPoint
    ) -> [SegmentedObject] {
        guard let request else { return [] }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            guard let observations = request.results as? [VNCoreMLFeatureValueObservation] else { return [] }
            let objects = parseFastSAMResults(observations, mode: mode, promptPoint: promptPoint)
            runtimeMessage = objects.isEmpty ? "FastSAM returned no usable masks" : "FastSAM ready"
            return objects
        } catch {
            runtimeMessage = "FastSAM inference failed: \(error.localizedDescription)"
            return []
        }
    }

    private func parseFastSAMResults(
        _ observations: [VNCoreMLFeatureValueObservation],
        mode: OptimizationMode,
        promptPoint: CGPoint
    ) -> [SegmentedObject] {
        let arrays = observations.compactMap { $0.featureValue.multiArrayValue }
        guard
            let rawOutput = arrays.first(where: { $0.shape.count == 3 && $0.shape[1].intValue >= 37 }),
            let prototypes = arrays.first(where: { $0.shape.count == 4 && $0.shape[1].intValue == maskCoefficientCount })
        else {
            return []
        }

        let channelCount = rawOutput.shape[1].intValue
        let candidateCount = rawOutput.shape[2].intValue
        guard channelCount >= 5 + maskCoefficientCount else { return [] }

        var candidates: [FastSAMCandidate] = []
        let candidateThreshold = min(max(mode.segmenterMaskThreshold * 0.35, 0.05), 0.18)

        for index in 0..<candidateCount {
            let confidence = value(rawOutput, 0, 4, index)
            guard confidence >= candidateThreshold else { continue }

            let centerX = CGFloat(value(rawOutput, 0, 0, index)) / modelInputSize
            let centerY = CGFloat(value(rawOutput, 0, 1, index)) / modelInputSize
            let width = CGFloat(value(rawOutput, 0, 2, index)) / modelInputSize
            let height = CGFloat(value(rawOutput, 0, 3, index)) / modelInputSize

            let rawBox = CGRect(
                x: clamp01(centerX - width / 2),
                y: clamp01(centerY - height / 2),
                width: clamp01(width),
                height: clamp01(height)
            ).standardized

            let area = rawBox.width * rawBox.height
            guard
                rawBox.width >= 0.025,
                rawBox.height >= 0.025,
                area >= 0.004,
                area <= 0.45
            else { continue }

            var coefficients: [Float] = []
            for maskIndex in 0..<maskCoefficientCount {
                coefficients.append(value(rawOutput, 0, 5 + maskIndex, index))
            }

            candidates.append(FastSAMCandidate(
                confidence: confidence,
                rawBox: rawBox,
                displayBox: displayBox(fromRawBox: rawBox),
                coefficients: coefficients
            ))
        }

        let rankedObjects = candidates
            .sorted { promptRank($0, promptPoint: promptPoint) > promptRank($1, promptPoint: promptPoint) }
            .prefix(32)
            .compactMap { candidate -> (object: SegmentedObject, rank: CGFloat)? in
            let geometry = maskGeometry(
                coefficients: candidate.coefficients,
                prototypes: prototypes,
                rawBox: candidate.rawBox,
                threshold: mode.segmenterMaskThreshold,
                dilationRadius: mode.segmenterDilationRadius,
                contourSamples: mode.segmenterContourSamples
            )

            let polygon = geometry?.polygon ?? []
            let box = geometry?.boundingBox ?? candidate.displayBox
            let areaRatio = geometry?.areaRatio ?? candidate.displayBox.width * candidate.displayBox.height

            guard areaRatio >= 0.004 else { return nil }
            let object = SegmentedObject(
                boundingBox: box,
                maskPolygon: polygon,
                areaRatio: areaRatio,
                confidence: candidate.confidence
            )
            return (object, objectRank(object, promptPoint: promptPoint))
        }

        return rankedObjects
            .sorted { $0.rank > $1.rank }
            .prefix(mode.segmenterMaxObjects)
            .map(\.object)
    }

    @available(iOS 17.0, *)
    private func visionForegroundObjects(
        request: VNGenerateForegroundInstanceMaskRequest,
        handler: VNImageRequestHandler,
        mode: OptimizationMode
    ) -> [SegmentedObject] {
        guard let observation = request.results?.first else { return [] }

        var objects: [SegmentedObject] = []
        for instance in observation.allInstances {
            guard objects.count < mode.segmenterMaxObjects else { break }
            let instances = IndexSet(integer: instance)

            guard
                let mask = try? observation.generateScaledMaskForImage(
                    forInstances: instances,
                    from: handler
                ),
                let geometry = maskGeometry(
                    from: mask,
                    threshold: mode.segmenterMaskThreshold,
                    dilationRadius: mode.segmenterDilationRadius,
                    contourSamples: mode.segmenterContourSamples
                ),
                geometry.areaRatio >= 0.005
            else {
                continue
            }

            objects.append(SegmentedObject(
                boundingBox: geometry.boundingBox,
                maskPolygon: geometry.polygon,
                areaRatio: geometry.areaRatio,
                confidence: Float(min(geometry.areaRatio * 12, 1.0))
            ))
        }
        return objects.sorted { $0.areaRatio > $1.areaRatio }
    }

    private func segmentWithVisionForegroundMask(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        mode: OptimizationMode
    ) -> [SegmentedObject] {
        guard #available(iOS 17.0, *) else { return [] }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])

        do {
            try handler.perform([request])
            return visionForegroundObjects(request: request, handler: handler, mode: mode)
        } catch {
            return []
        }
    }

    private func maskGeometry(
        coefficients: [Float],
        prototypes: MLMultiArray,
        rawBox: CGRect,
        threshold: Float,
        dilationRadius: Int,
        contourSamples: Int
    ) -> (boundingBox: CGRect, polygon: [CGPoint], areaRatio: CGFloat)? {
        guard prototypes.shape.count == 4, coefficients.count == maskCoefficientCount else { return nil }

        let maskWidth = prototypes.shape[3].intValue
        let maskHeight = prototypes.shape[2].intValue
        guard maskWidth > 2, maskHeight > 2 else { return nil }

        let minX = max(Int(rawBox.minX * CGFloat(maskWidth)), 0)
        let maxX = min(Int(rawBox.maxX * CGFloat(maskWidth)), maskWidth - 1)
        let minY = max(Int(rawBox.minY * CGFloat(maskHeight)), 0)
        let maxY = min(Int(rawBox.maxY * CGFloat(maskHeight)), maskHeight - 1)
        guard maxX > minX, maxY > minY else { return nil }

        var activeRows = Array(repeating: (min: Int.max, max: Int.min), count: maskWidth)
        var boxMinX = maskWidth
        var boxMinY = maskHeight
        var boxMaxX = 0
        var boxMaxY = 0
        var activeArea = 0
        let radius = max(dilationRadius, 0)

        for y in minY...maxY {
            for x in minX...maxX where isPrototypeActive(
                coefficients: coefficients,
                prototypes: prototypes,
                x: x,
                y: y,
                threshold: threshold,
                dilationRadius: radius
            ) {
                activeRows[x].min = min(activeRows[x].min, y)
                activeRows[x].max = max(activeRows[x].max, y)
                boxMinX = min(boxMinX, x)
                boxMinY = min(boxMinY, y)
                boxMaxX = max(boxMaxX, x)
                boxMaxY = max(boxMaxY, y)
                activeArea += 1
            }
        }

        guard boxMaxX > boxMinX, boxMaxY > boxMinY, activeArea > 0 else { return nil }

        let boundingBox = CGRect(
            x: CGFloat(boxMinX) / CGFloat(maskWidth),
            y: 1 - CGFloat(boxMaxY) / CGFloat(maskHeight),
            width: CGFloat(boxMaxX - boxMinX) / CGFloat(maskWidth),
            height: CGFloat(boxMaxY - boxMinY) / CGFloat(maskHeight)
        )

        let step = max((boxMaxX - boxMinX) / max(contourSamples, 1), 1)
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []

        for x in Swift.stride(from: boxMinX, through: boxMaxX, by: step) {
            let row = activeRows[x]
            guard row.min <= row.max else { continue }

            top.append(CGPoint(
                x: CGFloat(x) / CGFloat(maskWidth),
                y: 1 - CGFloat(row.min) / CGFloat(maskHeight)
            ))
            bottom.append(CGPoint(
                x: CGFloat(x) / CGFloat(maskWidth),
                y: 1 - CGFloat(row.max) / CGFloat(maskHeight)
            ))
        }

        let polygon = top + bottom.reversed()
        return (
            boundingBox,
            polygon.count >= 6 ? polygon : [],
            CGFloat(activeArea) / CGFloat(maskWidth * maskHeight)
        )
    }

    private func maskGeometry(
        from mask: CVPixelBuffer,
        threshold: Float,
        dilationRadius: Int,
        contourSamples: Int
    ) -> (boundingBox: CGRect, polygon: [CGPoint], areaRatio: CGFloat)? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }

        let width = CVPixelBufferGetWidth(mask)
        let height = CVPixelBufferGetHeight(mask)
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        guard width > 2, height > 2 else { return nil }

        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var area = 0

        for y in 0..<height {
            for x in 0..<width where isVisionMaskActive(
                base: base,
                rowBytes: rowBytes,
                width: width,
                height: height,
                x: x,
                y: y,
                threshold: threshold,
                dilationRadius: dilationRadius
            ) {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
                area += 1
            }
        }

        guard maxX > minX, maxY > minY, area > 0 else { return nil }

        let boundingBox = CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: 1 - CGFloat(maxY) / CGFloat(height),
            width: CGFloat(maxX - minX) / CGFloat(width),
            height: CGFloat(maxY - minY) / CGFloat(height)
        )

        let step = max((maxX - minX) / max(contourSamples, 1), 1)
        var top: [CGPoint] = []
        var bottom: [CGPoint] = []

        for x in Swift.stride(from: minX, through: maxX, by: step) {
            var topY: Int?
            var bottomY: Int?

            for y in minY...maxY {
                if isVisionMaskActive(
                    base: base,
                    rowBytes: rowBytes,
                    width: width,
                    height: height,
                    x: x,
                    y: y,
                    threshold: threshold,
                    dilationRadius: dilationRadius
                ) {
                    if topY == nil { topY = y }
                    bottomY = y
                }
            }

            guard let topY, let bottomY else { continue }
            top.append(CGPoint(x: CGFloat(x) / CGFloat(width), y: 1 - CGFloat(topY) / CGFloat(height)))
            bottom.append(CGPoint(x: CGFloat(x) / CGFloat(width), y: 1 - CGFloat(bottomY) / CGFloat(height)))
        }

        let polygon = top + bottom.reversed()
        return (
            boundingBox,
            polygon.count >= 6 ? polygon : [],
            CGFloat(area) / CGFloat(width * height)
        )
    }

    private func isPrototypeActive(
        coefficients: [Float],
        prototypes: MLMultiArray,
        x: Int,
        y: Int,
        threshold: Float,
        dilationRadius: Int
    ) -> Bool {
        let minX = max(x - dilationRadius, 0)
        let maxX = min(x + dilationRadius, prototypes.shape[3].intValue - 1)
        let minY = max(y - dilationRadius, 0)
        let maxY = min(y + dilationRadius, prototypes.shape[2].intValue - 1)

        for sampleY in minY...maxY {
            for sampleX in minX...maxX where fastSAMMaskValue(
                coefficients: coefficients,
                prototypes: prototypes,
                x: sampleX,
                y: sampleY
            ) >= threshold {
                return true
            }
        }
        return false
    }

    private func fastSAMMaskValue(
        coefficients: [Float],
        prototypes: MLMultiArray,
        x: Int,
        y: Int
    ) -> Float {
        var sum: Float = 0
        for index in 0..<maskCoefficientCount {
            sum += coefficients[index] * value(prototypes, 0, index, y, x)
        }
        return 1 / (1 + exp(-sum))
    }

    private func isVisionMaskActive(
        base: UnsafeMutableRawPointer,
        rowBytes: Int,
        width: Int,
        height: Int,
        x: Int,
        y: Int,
        threshold: Float,
        dilationRadius: Int
    ) -> Bool {
        let radius = max(dilationRadius, 0)
        let minX = max(x - radius, 0)
        let maxX = min(x + radius, width - 1)
        let minY = max(y - radius, 0)
        let maxY = min(y + radius, height - 1)

        for sampleY in minY...maxY {
            let row = base.advanced(by: sampleY * rowBytes).assumingMemoryBound(to: Float32.self)
            for sampleX in minX...maxX where row[sampleX] >= threshold {
                return true
            }
        }

        return false
    }

    private func applyNMS(to candidates: [FastSAMCandidate], limit: Int) -> [FastSAMCandidate] {
        var kept: [FastSAMCandidate] = []

        for candidate in candidates {
            guard kept.count < limit else { break }
            let overlaps = kept.contains { existing in
                iou(existing.displayBox, candidate.displayBox) > 0.55
            }
            if !overlaps {
                kept.append(candidate)
            }
        }

        return kept
    }

    private func candidateRank(_ candidate: FastSAMCandidate) -> CGFloat {
        let area = candidate.rawBox.width * candidate.rawBox.height
        let center = CGPoint(x: candidate.rawBox.midX, y: candidate.rawBox.midY)
        let centerDistance = hypot(center.x - 0.5, center.y - 0.54)
        let edgePenalty = minEdgeDistance(candidate.rawBox) < 0.015 ? 0.25 : 0
        return CGFloat(candidate.confidence) + min(area * 3.2, 0.32) - min(centerDistance * 0.18, 0.16) - edgePenalty
    }

    private func promptRank(_ candidate: FastSAMCandidate, promptPoint: CGPoint) -> CGFloat {
        let box = candidate.displayBox
        let center = CGPoint(x: box.midX, y: box.midY)
        let distance = hypot(center.x - promptPoint.x, center.y - promptPoint.y)
        let containsPrompt = box.insetBy(dx: -0.035, dy: -0.035).contains(promptPoint)
        let area = candidate.rawBox.width * candidate.rawBox.height
        let targetAreaScore = 1 - min(abs(area - 0.08) / 0.18, 1)
        return CGFloat(candidate.confidence)
            + (containsPrompt ? 1.25 : 0)
            + targetAreaScore * 0.22
            - min(distance * 1.6, 1.1)
    }

    private func objectRank(_ object: SegmentedObject, promptPoint: CGPoint) -> CGFloat {
        let box = object.boundingBox
        let center = CGPoint(x: box.midX, y: box.midY)
        let distance = hypot(center.x - promptPoint.x, center.y - promptPoint.y)
        let containsPrompt = box.insetBy(dx: -0.04, dy: -0.04).contains(promptPoint)
        let aspect = max(box.width, box.height) / max(min(box.width, box.height), 0.001)
        let compactShapeScore = max(0, 1 - min((aspect - 1) / 2.4, 1))
        let areaScore = min(object.areaRatio * 18, 1)

        return CGFloat(object.confidence)
            + (containsPrompt ? 1.4 : 0)
            + areaScore * 0.9
            + compactShapeScore * 0.8
            - min(distance * 1.8, 1.2)
    }

    private func minEdgeDistance(_ rect: CGRect) -> CGFloat {
        min(rect.minX, rect.minY, 1 - rect.maxX, 1 - rect.maxY)
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

        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: keys
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard extensions.contains(url.pathExtension) else { continue }
            if url.deletingPathExtension().lastPathComponent == name {
                return url
            }
        }

        return nil
    }

    private func value(_ array: MLMultiArray, _ indices: Int...) -> Float {
        array[indices.map { NSNumber(value: $0) }].floatValue
    }

    private func displayBox(fromRawBox rawBox: CGRect) -> CGRect {
        CGRect(
            x: rawBox.minX,
            y: clamp01(1 - rawBox.maxY),
            width: rawBox.width,
            height: rawBox.height
        )
    }

    private func iou(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}

private struct FastSAMCandidate {
    let confidence: Float
    let rawBox: CGRect
    let displayBox: CGRect
    let coefficients: [Float]
}
