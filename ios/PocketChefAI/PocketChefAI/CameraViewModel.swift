import AVFoundation
import CoreVideo
import Foundation
import UIKit

final class CameraViewModel: NSObject, ObservableObject {
    @Published var detections: [Detection] = []
    @Published var optimizationMode: OptimizationMode = .baseline {
        didSet {
            metrics.reset()
            detections = []
            DetectionMaskImageCache.clear()
            selectedMaskSummary = "Target: none"
            currentRecipe = RecipePlan.empty
            detector.configure(mode: optimizationMode)
            activeBackend = detector.backendName
            activeModel = detector.modelName
            activePolicySummary = optimizationMode.policySummary
            bundleInventory = detector.bundleInventory
            if capturedPixelBuffer != nil, let targetPrompt {
                detectCapturedFrame(at: targetPrompt)
            }
        }
    }
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
    @Published var isPhotoCaptured = false

    let session = AVCaptureSession()
    let metrics = MetricsTracker()

    private let detector = FoodDetector(mode: .baseline)
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
            guard let frozenBuffer = autoreleasepool(invoking: {
                self.copyPixelBuffer(latestPixelBuffer)
            }) else { return }
            guard let frozenImage = autoreleasepool(invoking: {
                self.image(from: frozenBuffer)
            }) else { return }
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
            }
        }
    }

    func retakePhoto() {
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
        configureAndStart()
    }

    private func detectCapturedFrame(at point: CGPoint) {
        guard !isProcessingFrame, let pixelBuffer = capturedPixelBuffer else { return }
        isProcessingFrame = true
        let mode = optimizationMode
        let orientation = capturedGeometry?.visionOrientation ?? .up

        inferenceQueue.async { [weak self] in
            guard let self else { return }
            let frame = autoreleasepool {
                self.detector.detect(
                    pixelBuffer: pixelBuffer,
                    orientation: orientation,
                    mode: mode,
                    promptPoint: point
                )
            }

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
