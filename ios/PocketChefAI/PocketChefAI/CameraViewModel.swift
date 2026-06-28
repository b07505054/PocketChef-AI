import AVFoundation
import CoreVideo
import Foundation
import UIKit

final class CameraViewModel: NSObject, ObservableObject {
    @Published var detections: [Detection] = []
    @Published var optimizationMode: OptimizationMode = .baseline {
        didSet {
            recordMemoryEvent("before_model_load", metadata: modeSwitchMetadata())
            metrics.reset()
            detections = []
            benchmarkResults = []
            DetectionMaskImageCache.clear()
            selectedMaskSummary = "Target: none"
            currentRecipe = RecipePlan.empty
            detector.configure(mode: optimizationMode)
            activeBackend = detector.backendName
            activeModel = detector.modelName
            activePolicySummary = optimizationMode.policySummary
            bundleInventory = detector.bundleInventory
            recordMemoryEvent("after_model_load", metadata: modeSwitchMetadata())
            if capturedPixelBuffer != nil, let targetPrompt {
                detectCapturedFrame(at: targetPrompt)
            }
        }
    }
    @Published var benchmarkResults: [BenchmarkResult] = []
    @Published var isBenchmarking = false
    @Published var activeBackend = "No Core ML model loaded"
    @Published var activeModel = "missing_yolo_food_model"
    @Published var bundleInventory = "Bundle models: scanning..."
    @Published var activePolicySummary = OptimizationMode.baseline.policySummary
    @Published var selectedMaskSummary = "Target: none"
    @Published var currentRecipe = RecipePlan.empty
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var targetPrompt: CGPoint?
    @Published var capturedImage: UIImage?
    @Published var capturedGeometry: CapturedFrameGeometry?
    @Published var geometryDebugSummary = "Geometry: live preview"
    @Published var memoryDebugSummary = "Mem: pending"
    @Published var memoryDetailSummary = "Last jump: pending"
    @Published var isPhotoCaptured = false

    let session = AVCaptureSession()
    let metrics = MetricsTracker()

    private let detector = FoodDetector(mode: .baseline)
    private let memoryProfiler = MemoryProfiler()
    private let planner = PocketChefPlanner()
    private let sessionQueue = DispatchQueue(label: "pocketchef.camera.session")
    private let outputQueue = DispatchQueue(label: "pocketchef.camera.frames")
    private let inferenceQueue = DispatchQueue(label: "pocketchef.detector.snapshot")
    private let imageContext = CIContext()
    private let maxCapturedDisplayDimension: CGFloat = 1280
    private var latestPixelBuffer: CVPixelBuffer?
    private var capturedPixelBuffer: CVPixelBuffer?
    private var isProcessingFrame = false

    override init() {
        super.init()
        activeBackend = detector.backendName
        activeModel = detector.modelName
        activePolicySummary = optimizationMode.policySummary
        bundleInventory = detector.bundleInventory
        recordMemoryEvent("app_start")
    }

    func start() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch authorizationStatus {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = granted ? .authorized : .denied
                    if granted {
                        self?.configureAndStart()
                    }
                }
            }
        default:
            break
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func setTargetPrompt(_ point: CGPoint) {
        guard isPhotoCaptured else { return }
        targetPrompt = point
        metrics.reset()
        detectCapturedFrame(at: point)
    }

    func capturePhoto() {
        outputQueue.async { [weak self] in
            guard let self, let latestPixelBuffer else { return }
            self.recordMemoryEvent("before_capture", metadata: self.pixelBufferMetadata(latestPixelBuffer))
            guard let frozenBuffer = autoreleasepool(invoking: {
                self.copyPixelBuffer(latestPixelBuffer)
            }) else { return }
            self.recordMemoryEvent("after_copy_pixel_buffer", metadata: self.pixelBufferMetadata(frozenBuffer))
            guard let frozenImage = autoreleasepool(invoking: {
                self.image(from: frozenBuffer)
            }) else { return }
            self.recordMemoryEvent(
                "after_make_uiimage",
                metadata: self.imageMetadata(frozenImage).merging(self.pixelBufferMetadata(frozenBuffer)) { current, _ in current }
            )
            let geometry = CapturedFrameGeometry(
                imageSize: frozenImage.size,
                pixelBufferSize: CGSize(
                    width: CVPixelBufferGetWidth(frozenBuffer),
                    height: CVPixelBufferGetHeight(frozenBuffer)
                ),
                visionOrientation: .up
            )
            self.latestPixelBuffer = nil

            DispatchQueue.main.async {
                DetectionMaskImageCache.clear()
                self.capturedPixelBuffer = frozenBuffer
                self.capturedImage = frozenImage
                self.capturedGeometry = geometry
                self.geometryDebugSummary = geometry.debugSummary
                self.isPhotoCaptured = true
                self.targetPrompt = nil
                self.detections = []
                self.selectedMaskSummary = "Target: none"
                self.currentRecipe = RecipePlan.empty
                self.metrics.reset()
                self.activeBackend = "Photo captured | tap target object"
                self.activeModel = self.detector.modelName
                self.activePolicySummary = self.optimizationMode.policySummary
                self.stop()
                self.recordMemoryEvent("after_stop_session", metadata: self.captureStateMetadata())
            }
        }
    }

    func retakePhoto() {
        recordMemoryEvent("before_retake_clear", metadata: captureStateMetadata())
        capturedPixelBuffer = nil
        capturedImage = nil
        capturedGeometry = nil
        geometryDebugSummary = "Geometry: live preview"
        isPhotoCaptured = false
        targetPrompt = nil
        detections = []
        DetectionMaskImageCache.clear()
        selectedMaskSummary = "Target: none"
        currentRecipe = RecipePlan.empty
        metrics.reset()
        activeBackend = detector.backendName
        activeModel = detector.modelName
        activePolicySummary = optimizationMode.policySummary
        recordMemoryEvent("after_retake_clear", metadata: captureStateMetadata())
        configureAndStart()
    }

    func recordLLMMemoryEvent(_ event: String, metadata: [String: String] = [:]) {
        recordMemoryEvent(event, metadata: metadata)
    }

    func runBenchmark(configs: [BenchmarkConfig], warmup: Int = 1, runs: Int = 5) async {
        guard !configs.isEmpty,
              let pixelBuffer = capturedPixelBuffer,
              let promptPoint = targetPrompt else { return }

        let originalMode = optimizationMode
        let orientation = capturedGeometry?.visionOrientation ?? .up

        await MainActor.run {
            isBenchmarking = true
            benchmarkResults = []
        }

        for config in configs {
            let result: BenchmarkResult = await withCheckedContinuation { continuation in
                inferenceQueue.async {
                    let loadMs = self.detector.configureForBenchmark(computeUnits: config.computeUnits)
                    for _ in 0..<warmup {
                        _ = self.detector.detect(
                            pixelBuffer: pixelBuffer,
                            orientation: orientation,
                            mode: originalMode,
                            promptPoint: promptPoint
                        )
                    }
                    var samples: [BenchmarkSample] = []
                    for _ in 0..<runs {
                        let frame = self.detector.detect(
                            pixelBuffer: pixelBuffer,
                            orientation: orientation,
                            mode: originalMode,
                            promptPoint: promptPoint
                        )
                        let maskMs = Double(frame.memoryMetadata["mask_decode_latency_ms"] ?? "0") ?? 0
                        samples.append(BenchmarkSample(totalMs: frame.latencyMs, maskDecodeMs: maskMs))
                    }
                    let r = BenchmarkResult.make(
                        config: config,
                        modelLoadMs: loadMs,
                        warmupRuns: warmup,
                        measuredRuns: runs,
                        samples: samples,
                        thermalState: self.thermalStateString(),
                        lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                    )
                    continuation.resume(returning: r)
                }
            }
            await MainActor.run {
                benchmarkResults.append(result)
            }
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            inferenceQueue.async {
                self.detector.configure(mode: originalMode)
                continuation.resume()
            }
        }

        await MainActor.run {
            isBenchmarking = false
        }
    }

    private func thermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:    return "nominal"
        case .fair:       return "fair"
        case .serious:    return "serious"
        case .critical:   return "critical"
        @unknown default: return "unknown"
        }
    }

    var memoryReportJSON: String {
        memoryProfiler.diagnosticJSON
    }

    private func detectCapturedFrame(at point: CGPoint) {
        guard !isProcessingFrame, let pixelBuffer = capturedPixelBuffer else { return }
        isProcessingFrame = true
        let mode = optimizationMode
        let orientation = capturedGeometry?.visionOrientation ?? .up
        recordMemoryEvent("before_inference", metadata: pixelBufferMetadata(pixelBuffer).merging(promptMetadata(point)) { current, _ in current })

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            self.recordMemoryEvent("before_mask_decode", metadata: self.pixelBufferMetadata(pixelBuffer))
            let frame = autoreleasepool {
                self.detector.detect(
                    pixelBuffer: pixelBuffer,
                    orientation: orientation,
                    mode: mode,
                    promptPoint: point
                )
            }
            self.recordMemoryEvent("after_inference", metadata: frame.memoryMetadata)
            self.recordMemoryEvent(
                "after_mask_decode",
                metadata: frame.memoryMetadata.merging(self.detectionMemoryMetadata(frame.detections)) { current, _ in current }
            )

            DispatchQueue.main.async {
                self.isProcessingFrame = false
                guard frame.mode == self.optimizationMode else { return }
                let shouldPreservePreviousTarget = frame.detections.isEmpty && !self.detections.isEmpty
                if !shouldPreservePreviousTarget {
                    self.detections = frame.detections
                    self.selectedMaskSummary = self.makeMaskSummary(from: frame.detections)
                }
                self.activeBackend = frame.backend
                self.activeModel = frame.modelName
                self.activePolicySummary = frame.mode.policySummary
                self.bundleInventory = self.detector.bundleInventory
                self.metrics.record(latencyMs: frame.latencyMs)
                if !shouldPreservePreviousTarget {
                    self.currentRecipe = self.planner.makePlan(
                        from: frame.detections,
                        mode: frame.mode,
                        latencyMs: frame.latencyMs,
                        fps: self.metrics.fps
                    )
                }
                self.recordMemoryEvent(
                    "after_set_detections",
                    metadata: frame.memoryMetadata.merging(self.detectionMemoryMetadata(self.detections)) { current, _ in current }
                )
            }
        }
    }

    private func makeMaskSummary(from detections: [Detection]) -> String {
        guard let detection = detections.first else { return "Target: no candidate hit" }
        let confidence = Int(detection.confidence * 100)
        let maskPercent = detection.maskAreaRatio * 100
        let pixels = detection.mask?.activePixelCount ?? 0
        return String(
            format: "Target: %@ %d%% | mask %.1f%% | %d px",
            detection.label.capitalized,
            confidence,
            maskPercent,
            pixels
        )
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard !self.session.isRunning else { return }

            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd1280x720) {
                self.session.sessionPreset = .hd1280x720
            } else {
                self.session.sessionPreset = .medium
            }

            self.session.inputs.forEach { self.session.removeInput($0) }
            self.session.outputs.forEach { self.session.removeOutput($0) }

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input)
            else {
                self.session.commitConfiguration()
                return
            }

            self.session.addInput(input)

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.setSampleBufferDelegate(self, queue: self.outputQueue)

            if self.session.canAddOutput(output) {
                self.session.addOutput(output)
            }

            output.connection(with: .video)?.videoOrientation = .portrait
            self.session.commitConfiguration()
            self.session.startRunning()
            self.recordMemoryEvent("live_preview_steady")
        }
    }

    private func image(from pixelBuffer: CVPixelBuffer) -> UIImage? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let maxDimension = max(source.extent.width, source.extent.height)
        let scale = maxDimension > maxCapturedDisplayDimension
            ? maxCapturedDisplayDimension / maxDimension
            : 1
        let displayImage = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = imageContext.createCGImage(displayImage, from: displayImage.extent) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    private func copyPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        var copy: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attributes, &copy) == kCVReturnSuccess,
              let copy
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copy, [])
        defer {
            CVPixelBufferUnlockBaseAddress(copy, [])
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let sourceBase = CVPixelBufferGetBaseAddress(pixelBuffer),
              let targetBase = CVPixelBufferGetBaseAddress(copy)
        else {
            return nil
        }

        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let targetBytesPerRow = CVPixelBufferGetBytesPerRow(copy)
        let rows = CVPixelBufferGetHeight(pixelBuffer)
        let bytesToCopy = min(sourceBytesPerRow, targetBytesPerRow)

        for row in 0..<rows {
            memcpy(
                targetBase.advanced(by: row * targetBytesPerRow),
                sourceBase.advanced(by: row * sourceBytesPerRow),
                bytesToCopy
            )
        }

        return copy
    }
}

private extension CameraViewModel {
    func recordMemoryEvent(_ event: String, metadata: [String: String] = [:]) {
        let memoryEvent = memoryProfiler.record(
            event,
            mode: optimizationMode,
            model: detector.modelName,
            computeUnits: optimizationMode.preferredComputeUnits.label,
            metadata: metadata
        )

        guard let memoryEvent else { return }
        let detail = String(
            format: "Last %@ | rss %.1f MB | model %.2f MB | cache %.2f MB",
            memoryEvent.event,
            memoryEvent.rssMB,
            Double(detector.modelArtifactSizeBytes) / 1_048_576,
            Double(DetectionMaskImageCache.estimatedCostBytes) / 1_048_576
        )

        DispatchQueue.main.async {
            self.memoryDebugSummary = self.memoryProfiler.compactSummary
            self.memoryDetailSummary = detail
        }
    }

    func modeSwitchMetadata() -> [String: String] {
        [
            "model_file_size_mb": String(format: "%.3f", Double(detector.modelArtifactSizeBytes) / 1_048_576),
            "overlay_cache_cost": "\(DetectionMaskImageCache.estimatedCostBytes)",
            "overlay_cache_count": "\(DetectionMaskImageCache.estimatedCount)"
        ]
    }

    func promptMetadata(_ point: CGPoint) -> [String: String] {
        [
            "prompt_x": String(format: "%.3f", point.x),
            "prompt_y": String(format: "%.3f", point.y)
        ]
    }

    func captureStateMetadata() -> [String: String] {
        var metadata: [String: String] = [
            "detections_count": "\(detections.count)",
            "overlay_cache_cost": "\(DetectionMaskImageCache.estimatedCostBytes)",
            "overlay_cache_count": "\(DetectionMaskImageCache.estimatedCount)",
            "captured_pixel_buffer_present": capturedPixelBuffer == nil ? "false" : "true",
            "captured_image_present": capturedImage == nil ? "false" : "true"
        ]

        if let capturedPixelBuffer {
            metadata.merge(pixelBufferMetadata(capturedPixelBuffer)) { current, _ in current }
        }
        if let capturedImage {
            metadata.merge(imageMetadata(capturedImage)) { current, _ in current }
        }
        metadata.merge(detectionMemoryMetadata(detections)) { current, _ in current }
        return metadata
    }

    func pixelBufferMetadata(_ pixelBuffer: CVPixelBuffer) -> [String: String] {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let estimatedBytes = rowBytes * height
        return [
            "captured_pixel_buffer_size": "\(width)x\(height)",
            "captured_pixel_buffer_bytes": "\(estimatedBytes)",
            "captured_pixel_buffer_mb": String(format: "%.3f", Double(estimatedBytes) / 1_048_576)
        ]
    }

    func imageMetadata(_ image: UIImage) -> [String: String] {
        let width = Int(image.size.width * image.scale)
        let height = Int(image.size.height * image.scale)
        let estimatedBytes = width * height * 4
        return [
            "captured_image_pixels": "\(width)x\(height)",
            "captured_image_estimated_bytes": "\(estimatedBytes)",
            "captured_image_estimated_mb": String(format: "%.3f", Double(estimatedBytes) / 1_048_576)
        ]
    }

    func detectionMemoryMetadata(_ detections: [Detection]) -> [String: String] {
        let maskAlphaBytes = detections.reduce(0) { total, detection in
            total + (detection.mask?.alpha.count ?? 0)
        }
        let activePixels = detections.reduce(0) { total, detection in
            total + (detection.mask?.activePixelCount ?? 0)
        }
        return [
            "detections_count": "\(detections.count)",
            "total_detection_mask_alpha_bytes": "\(maskAlphaBytes)",
            "total_detection_active_pixels": "\(activePixels)",
            "overlay_cache_cost": "\(DetectionMaskImageCache.estimatedCostBytes)",
            "overlay_cache_count": "\(DetectionMaskImageCache.estimatedCount)"
        ]
    }
}

extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        latestPixelBuffer = pixelBuffer
    }
}

extension CameraViewModel: @unchecked Sendable {}
