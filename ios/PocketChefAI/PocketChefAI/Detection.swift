import CoreGraphics
import Foundation
import ImageIO

struct CapturedFrameGeometry: Equatable {
    let imageSize: CGSize
    let pixelBufferSize: CGSize
    let visionOrientation: CGImagePropertyOrientation

    var debugSummary: String {
        let image = "\(Int(imageSize.width))x\(Int(imageSize.height))"
        let buffer = "\(Int(pixelBufferSize.width))x\(Int(pixelBufferSize.height))"
        return "Geometry: image=\(image) buffer=\(buffer) vision=\(visionOrientation.debugName)"
    }

    func aspectFillFrame(in viewSize: CGSize) -> CGRect {
        guard
            imageSize.width > 0,
            imageSize.height > 0,
            viewSize.width > 0,
            viewSize.height > 0
        else {
            return CGRect(origin: .zero, size: viewSize)
        }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let renderedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (viewSize.width - renderedSize.width) / 2,
            y: (viewSize.height - renderedSize.height) / 2,
            width: renderedSize.width,
            height: renderedSize.height
        )
    }

    func normalizedPoint(from viewPoint: CGPoint, in viewSize: CGSize) -> CGPoint {
        let frame = aspectFillFrame(in: viewSize)
        guard frame.width > 0, frame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }

        let x = (viewPoint.x - frame.minX) / frame.width
        let y = 1 - ((viewPoint.y - frame.minY) / frame.height)
        return CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }

    func viewPoint(for normalizedPoint: CGPoint, in viewSize: CGSize) -> CGPoint {
        let frame = aspectFillFrame(in: viewSize)
        return CGPoint(
            x: frame.minX + normalizedPoint.x * frame.width,
            y: frame.minY + (1 - normalizedPoint.y) * frame.height
        )
    }

    func viewRect(for normalizedRect: CGRect, in viewSize: CGSize) -> CGRect {
        let frame = aspectFillFrame(in: viewSize)
        return CGRect(
            x: frame.minX + normalizedRect.minX * frame.width,
            y: frame.minY + (1 - normalizedRect.maxY) * frame.height,
            width: normalizedRect.width * frame.width,
            height: normalizedRect.height * frame.height
        )
    }
}

extension CGImagePropertyOrientation {
    var debugName: String {
        switch self {
        case .up: return "up"
        case .upMirrored: return "upMirrored"
        case .down: return "down"
        case .downMirrored: return "downMirrored"
        case .left: return "left"
        case .leftMirrored: return "leftMirrored"
        case .right: return "right"
        case .rightMirrored: return "rightMirrored"
        }
    }
}

struct DetectionMask: Equatable {
    let cacheKey = UUID()
    let width: Int
    let height: Int
    let alpha: [UInt8]

    var activePixelCount: Int {
        alpha.reduce(0) { $0 + ($1 > 0 ? 1 : 0) }
    }

    var normalizedCentroid: CGPoint? {
        var totalWeight: CGFloat = 0
        var weightedX: CGFloat = 0
        var weightedY: CGFloat = 0

        for y in 0..<height {
            for x in 0..<width {
                let weight = CGFloat(alpha[y * width + x])
                guard weight > 0 else { continue }
                totalWeight += weight
                weightedX += (CGFloat(x) + 0.5) * weight
                weightedY += (CGFloat(y) + 0.5) * weight
            }
        }

        guard totalWeight > 0 else { return nil }
        return CGPoint(
            x: weightedX / totalWeight / CGFloat(width),
            y: weightedY / totalWeight / CGFloat(height)
        )
    }

    func contains(_ point: CGPoint, in normalizedFrame: CGRect) -> Bool {
        guard normalizedFrame.width > 0, normalizedFrame.height > 0 else { return false }
        guard normalizedFrame.insetBy(dx: -0.01, dy: -0.01).contains(point) else { return false }

        let localX = (point.x - normalizedFrame.minX) / normalizedFrame.width
        let localY = (normalizedFrame.maxY - point.y) / normalizedFrame.height
        let x = min(max(Int(localX * CGFloat(width)), 0), width - 1)
        let y = min(max(Int(localY * CGFloat(height)), 0), height - 1)
        return alpha[y * width + x] > 0
    }
}

struct Detection: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let confidence: Float
    let boundingBox: CGRect
    let maskPolygon: [CGPoint]
    let mask: DetectionMask?
    let maskAreaRatio: CGFloat

    init(
        label: String,
        confidence: Float,
        boundingBox: CGRect,
        maskPolygon: [CGPoint] = [],
        mask: DetectionMask? = nil,
        maskAreaRatio: CGFloat = 0
    ) {
        self.label = label
        self.confidence = confidence
        self.boundingBox = boundingBox
        self.maskPolygon = maskPolygon
        self.mask = mask
        self.maskAreaRatio = maskAreaRatio
    }
}

struct DetectionFrame: Equatable {
    var detections: [Detection]
    var latencyMs: Double
    var mode: OptimizationMode
    var backend: String
    var modelName: String
    var timestamp: Date
}
