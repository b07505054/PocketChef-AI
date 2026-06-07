import Foundation

final class MetricsTracker: ObservableObject {
    @Published private(set) var fps: Double = 0
    @Published private(set) var latestLatencyMs: Double = 0
    @Published private(set) var p50LatencyMs: Double = 0
    @Published private(set) var p95LatencyMs: Double = 0
    @Published private(set) var frameCount: Int = 0

    private var latencies: [Double] = []
    private var lastFpsUpdate = Date()
    private var framesSinceLastFpsUpdate = 0

    func reset() {
        fps = 0
        latestLatencyMs = 0
        p50LatencyMs = 0
        p95LatencyMs = 0
        frameCount = 0
        latencies = []
        lastFpsUpdate = Date()
        framesSinceLastFpsUpdate = 0
    }

    func record(latencyMs: Double) {
        latestLatencyMs = latencyMs
        frameCount += 1
        framesSinceLastFpsUpdate += 1

        latencies.append(latencyMs)
        if latencies.count > 180 {
            latencies.removeFirst(latencies.count - 180)
        }

        p50LatencyMs = percentile(50)
        p95LatencyMs = percentile(95)

        let now = Date()
        let elapsed = now.timeIntervalSince(lastFpsUpdate)
        if elapsed >= 1.0 {
            fps = Double(framesSinceLastFpsUpdate) / elapsed
            framesSinceLastFpsUpdate = 0
            lastFpsUpdate = now
        }
    }

    private func percentile(_ value: Double) -> Double {
        guard !latencies.isEmpty else { return 0 }
        let sorted = latencies.sorted()
        let rank = (value / 100.0) * Double(sorted.count - 1)
        return sorted[Int(rank.rounded())]
    }
}
