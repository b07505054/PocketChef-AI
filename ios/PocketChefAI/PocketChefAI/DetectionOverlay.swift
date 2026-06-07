import SwiftUI

struct DetectionOverlay: View {
    let detections: [Detection]
    let promptPoint: CGPoint?
    let geometry: CapturedFrameGeometry?

    var body: some View {
        GeometryReader { proxy in
            if let promptPoint {
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
                    .position(viewPoint(for: promptPoint, in: proxy.size))
                    .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
            }

            ForEach(detections) { detection in
                if let maskImage = cgImage(from: detection.mask) {
                    let rect = viewRect(for: detection.boundingBox, in: proxy.size)
                    Image(decorative: maskImage, scale: 1)
                        .resizable()
                        .interpolation(.medium)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func viewPoint(for normalizedPoint: CGPoint, in viewSize: CGSize) -> CGPoint {
        if let geometry {
            return geometry.viewPoint(for: normalizedPoint, in: viewSize)
        }
        return CGPoint(x: normalizedPoint.x * viewSize.width, y: (1 - normalizedPoint.y) * viewSize.height)
    }

    private func viewRect(for normalizedRect: CGRect, in viewSize: CGSize) -> CGRect {
        if let geometry {
            return geometry.viewRect(for: normalizedRect, in: viewSize)
        }
        return CGRect(
            x: normalizedRect.minX * viewSize.width,
            y: (1 - normalizedRect.maxY) * viewSize.height,
            width: normalizedRect.width * viewSize.width,
            height: normalizedRect.height * viewSize.height
        )
    }

    private func cgImage(from mask: DetectionMask?) -> CGImage? {
        guard let mask, mask.width > 0, mask.height > 0, mask.alpha.count == mask.width * mask.height else {
            return nil
        }
        let key = mask.cacheKey.uuidString as NSString
        if let cached = DetectionMaskImageCache.image(forKey: key) {
            return cached.image
        }

        var rgba = [UInt8](repeating: 0, count: mask.width * mask.height * 4)
        for index in mask.alpha.indices {
            let alpha = mask.alpha[index]
            guard alpha > 0 else { continue }
            let offset = index * 4
            rgba[offset] = 18
            rgba[offset + 1] = 154
            rgba[offset + 2] = 255
            rgba[offset + 3] = alpha
        }

        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let image = CGImage(
            width: mask.width,
            height: mask.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: mask.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        if let image {
            DetectionMaskImageCache.insert(CGImageBox(image), forKey: key, cost: rgba.count)
        }
        return image
    }
}

enum DetectionMaskImageCache {
    nonisolated(unsafe) private static let cache: NSCache<NSString, CGImageBox> = {
        let cache = NSCache<NSString, CGImageBox>()
        cache.countLimit = 8
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    static func image(forKey key: NSString) -> CGImageBox? {
        cache.object(forKey: key)
    }

    static func insert(_ image: CGImageBox, forKey key: NSString, cost: Int) {
        cache.setObject(image, forKey: key, cost: cost)
    }

    static func clear() {
        cache.removeAllObjects()
    }
}

final class CGImageBox {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}
