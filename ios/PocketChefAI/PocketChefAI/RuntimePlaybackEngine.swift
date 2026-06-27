import Foundation

// MARK: - RuntimePlaybackEngine
//
// Pure state machine over an immutable RuntimeTraceVariant.
// No Timer, no @MainActor, no ObservableObject, no Combine, no UI imports.
//
// The engine stores only currentTimeMs and isPlaying.
// All other state (activeEvents, backend, memory, etc.) is derived on demand
// via currentState(), which reads the immutable event/timeseries arrays.
//
// Caller is responsible for driving time forward via step(deltaMs:).
// Typical use: a Timer or display-link callback on the @MainActor domain
// calls step() and publishes the resulting RuntimePlaybackState.

final class RuntimePlaybackEngine {
    private let variant: RuntimeTraceVariant
    private let targetProfileId: String
    private let compilerPlanRef: String
    private let truthBoundary: String

    private(set) var currentTimeMs: Double = 0
    private(set) var isPlaying: Bool = false

    var totalDurationMs: Double { variant.totalDurationMs }

    init(
        variant: RuntimeTraceVariant,
        targetProfileId: String,
        compilerPlanRef: String,
        truthBoundary: String
    ) {
        self.variant       = variant
        self.targetProfileId = targetProfileId
        self.compilerPlanRef = compilerPlanRef
        self.truthBoundary = truthBoundary
    }

    // MARK: - Transport

    func play()  { isPlaying = true }
    func pause() { isPlaying = false }

    func stop() {
        isPlaying = false
        currentTimeMs = 0
    }

    func reset() {
        isPlaying = false
        currentTimeMs = 0
    }

    func seek(toMs ms: Double) {
        currentTimeMs = ms.clamped(to: 0...totalDurationMs)
    }

    // Advances time if playing. Stops at totalDurationMs and sets isPlaying = false.
    func step(deltaMs: Double) {
        guard isPlaying else { return }
        currentTimeMs = min(currentTimeMs + deltaMs, totalDurationMs)
        if currentTimeMs >= totalDurationMs { isPlaying = false }
    }

    // MARK: - State derivation

    func currentState() -> RuntimePlaybackState {
        let t      = currentTimeMs
        let events = variant.events
        let ts     = variant.timeseries
        let total  = variant.totalDurationMs

        // Active events: visible while currentTimeMs is within [tsMs, tsMs + max(durMs, 25)]
        let active = events.filter { e in
            e.tsMs <= t && t < e.tsMs + max(e.durMs, 25.0)
        }

        // Persistent state from most recent event of each category at or before t.
        // Persists after the event's display window closes (state machine, not animation).
        let backendMeta    = lastMetadata(category: "backend",    at: t, in: events)
        let memMeta        = lastMetadata(category: "memory",     at: t, in: events)
        let replayMeta     = lastMetadata(category: "replay",     at: t, in: events)
        let schedulerMeta  = lastMetadata(category: "scheduler",  at: t, in: events)

        let currentBackend        = backendMeta["selected_backend"]  ?? backendMeta["backend"]           ?? ""
        let currentKVLayout       = memMeta["kv_layout_used"]        ?? memMeta["kv_layout"]             ?? ""
        let currentReplayState    = replayMeta["eligible"]           ?? replayMeta["replay_requested"]   ?? ""
        let currentSchedulerState = schedulerMeta["priority"]        ?? schedulerMeta["confidence"]      ?? ""

        // Timeseries: linear interpolation for memory, rounded for queue depth
        let currentMemoryMB   = interpolateLinear(ts.memoryMb,                   timestamps: ts.timestampsMs, at: t)
        let queueRaw          = interpolateLinear(ts.queueDepth.map(Double.init), timestamps: ts.timestampsMs, at: t)
        let currentQueueDepth = Int(queueRaw.rounded())

        // TTFT: end_ms of most recent completed prefill compute event
        // TPOT: duration_ms of most recent completed decode compute event
        let completedPrefill = events.filter { $0.category == "compute" && $0.name.contains("prefill") && $0.endMs <= t }
        let completedDecode  = events.filter { $0.category == "compute" && $0.name.contains("decode")  && $0.endMs <= t }
        let currentTTFT = completedPrefill.max(by: { $0.tsMs < $1.tsMs }).map { $0.endMs }
        let currentTPOT = completedDecode .max(by: { $0.tsMs < $1.tsMs }).map { $0.durMs }

        // Requests completed: no request_completed events in this trace schema.
        // Fallback: each request = one prefill + one decode compute step.
        let requestsCompleted = completedDecode.count

        let progress = total > 0 ? min(t / total, 1.0) : 0.0

        return RuntimePlaybackState(
            currentTimeMs:        t,
            progress:             progress,
            playbackFinished:     t >= total,
            activeEvents:         active,
            currentBackend:       currentBackend,
            currentKVLayout:      currentKVLayout,
            currentReplayState:   currentReplayState,
            currentSchedulerState: currentSchedulerState,
            currentQueueDepth:    currentQueueDepth,
            currentMemoryMB:      currentMemoryMB,
            currentTTFT:          currentTTFT,
            currentTPOT:          currentTPOT,
            requestsCompleted:    requestsCompleted,
            variantId:            variant.variantId,
            targetProfileId:      targetProfileId,
            compilerPlanRef:      compilerPlanRef,
            truthBoundary:        truthBoundary
        )
    }

    // MARK: - Private helpers

    private func lastMetadata(category: String, at t: Double, in events: [RuntimeTraceEvent]) -> [String: String] {
        events
            .filter { $0.category == category && $0.tsMs <= t }
            .max(by: { $0.tsMs < $1.tsMs })?
            .metadata ?? [:]
    }

    // Linear interpolation over a parallel (timestamps, values) pair.
    // Clamps to first/last value outside the covered range.
    private func interpolateLinear(_ values: [Double], timestamps: [Double], at t: Double) -> Double {
        guard !timestamps.isEmpty, timestamps.count == values.count else { return 0 }
        if t <= timestamps[0] { return values[0] }
        let last = timestamps.count - 1
        if t >= timestamps[last] { return values[last] }

        // Find bracket via linear scan (arrays are short: ≤32 points)
        var lo = 0
        for i in 1...last {
            if timestamps[i] > t { break }
            lo = i
        }
        let hi = lo + 1
        let t0 = timestamps[lo], t1 = timestamps[hi]
        guard t1 > t0 else { return values[lo] }
        let frac = (t - t0) / (t1 - t0)
        return values[lo] + frac * (values[hi] - values[lo])
    }
}

// MARK: - ComparisonPlaybackEngine
//
// Synchronises two RuntimePlaybackEngine instances over a shared time axis.
// sharedTimeMs tracks a single shared clock; both sub-engines are seeked
// to sharedTimeMs on every step/seek call. The optimized variant finishes
// earlier and its state freezes at totalDurationMs while baseline continues.

final class ComparisonPlaybackEngine {
    private let baselineEngine: RuntimePlaybackEngine
    private let optimizedEngine: RuntimePlaybackEngine

    private(set) var sharedTimeMs: Double = 0
    private(set) var isPlaying: Bool = false

    var totalDurationMs: Double {
        max(baselineEngine.totalDurationMs, optimizedEngine.totalDurationMs)
    }

    init(trace: RuntimeProfileTraceSummary) {
        baselineEngine = RuntimePlaybackEngine(
            variant:       trace.baselineVariant,
            targetProfileId: trace.targetProfileId,
            compilerPlanRef: trace.compilerPlanRef,
            truthBoundary: trace.traceTruthBoundary
        )
        optimizedEngine = RuntimePlaybackEngine(
            variant:       trace.optimizedVariant,
            targetProfileId: trace.targetProfileId,
            compilerPlanRef: trace.compilerPlanRef,
            truthBoundary: trace.traceTruthBoundary
        )
    }

    // MARK: - Transport

    func play()  { isPlaying = true }
    func pause() { isPlaying = false }

    func stop() {
        isPlaying = false
        sharedTimeMs = 0
        baselineEngine.seek(toMs: 0)
        optimizedEngine.seek(toMs: 0)
    }

    func reset() { stop() }

    func seek(toMs ms: Double) {
        sharedTimeMs = ms.clamped(to: 0...totalDurationMs)
        baselineEngine.seek(toMs: sharedTimeMs)
        optimizedEngine.seek(toMs: sharedTimeMs)
    }

    func step(deltaMs: Double) {
        guard isPlaying else { return }
        sharedTimeMs = min(sharedTimeMs + deltaMs, totalDurationMs)
        baselineEngine.seek(toMs: sharedTimeMs)
        optimizedEngine.seek(toMs: sharedTimeMs)
        if sharedTimeMs >= totalDurationMs { isPlaying = false }
    }

    func currentState() -> ComparisonPlaybackState {
        let maxDuration = totalDurationMs
        return ComparisonPlaybackState(
            baseline:    baselineEngine.currentState(),
            optimized:   optimizedEngine.currentState(),
            sharedTimeMs: sharedTimeMs,
            progress:    maxDuration > 0 ? min(sharedTimeMs / maxDuration, 1.0) : 0.0
        )
    }
}

// MARK: - Utility

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        max(range.lowerBound, min(self, range.upperBound))
    }
}
