import Foundation

// MARK: - RuntimePlaybackState
//
// Snapshot of engine state at a given currentTimeMs.
// All fields are derived from immutable trace data by RuntimePlaybackEngine.
// SwiftUI consumes this struct; it never mutates it directly.

struct RuntimePlaybackState {
    let currentTimeMs: Double
    let progress: Double          // 0...1
    let playbackFinished: Bool
    let activeEvents: [RuntimeTraceEvent]
    let currentBackend: String
    let currentKVLayout: String
    let currentReplayState: String
    let currentSchedulerState: String
    let currentQueueDepth: Int
    let currentMemoryMB: Double
    let currentTTFT: Double?      // nil until first prefill completes
    let currentTPOT: Double?      // nil until first decode completes
    let requestsCompleted: Int
    let variantId: String
    let targetProfileId: String
    let compilerPlanRef: String
    let truthBoundary: String
}

// MARK: - ComparisonPlaybackState

struct ComparisonPlaybackState {
    let baseline: RuntimePlaybackState
    let optimized: RuntimePlaybackState
    let sharedTimeMs: Double
    let progress: Double          // 0...1, based on longer variant's duration
}
