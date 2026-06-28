// scripts/test_playback_engine.swift
//
// Standalone test for RuntimePlaybackEngine.
// Compile and run with:
//   xcrun swiftc \
//     ios/PocketChefAI/PocketChefAI/RuntimeProfileTraceSummary.swift \
//     ios/PocketChefAI/PocketChefAI/RuntimePlaybackState.swift \
//     ios/PocketChefAI/PocketChefAI/RuntimePlaybackEngine.swift \
//     scripts/test_playback_engine.swift \
//     -o /tmp/test_playback_engine && /tmp/test_playback_engine

import Foundation

@main struct PlaybackEngineTests {
    static func main() { runAllTests() }
}

// MARK: - Assertion helpers

var passCount = 0
var failCount = 0

func check(_ condition: Bool, _ label: String) {
    if condition {
        print("PASS: \(label)")
        passCount += 1
    } else {
        print("FAIL: \(label)")
        failCount += 1
    }
}

func checkEq<T: Equatable>(_ a: T, _ b: T, _ label: String) {
    if a == b {
        print("PASS: \(label)")
        passCount += 1
    } else {
        print("FAIL: \(label) — got \(a), want \(b)")
        failCount += 1
    }
}

func checkNear(_ a: Double, _ b: Double, tol: Double = 0.01, _ label: String) {
    if abs(a - b) <= tol {
        print("PASS: \(label)")
        passCount += 1
    } else {
        print("FAIL: \(label) — got \(a), want \(b) ± \(tol)")
        failCount += 1
    }
}

// MARK: - Test runner

func runAllTests() {

// Timeline:
//  t=0..50   backend event (selected_backend: "cpu")  [duration 0 → 25ms window]
//  t=10..60  memory event  (kv_layout_used: "contiguous") [duration 0 → 25ms window]
//  t=20..30  scheduler event (priority: "conservative", confidence: "low")
//  t=30..30  replay event (eligible: "False") [duration 0]
//  t=50..200 compute prefill (backend: "cpu")
//  t=60..120 backend event 2 (selected_backend: "coreml")
//  t=220..340 compute decode (backend: "coreml")
//
// Timeseries: timestamps [50, 150, 250], memory [100, 200, 150], queue [4, 2, 1]
// totalDurationMs: 400

func makeBackendEvent(tsMs: Double, backend: String) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: tsMs, durMs: 0,
        category: "backend", name: "backend_dispatch", lane: "runtime",
        requestId: "req1",
        metadata: ["selected_backend": backend, "override_reason": "", "attempted": backend],
        truthBoundary: "test"
    )
}

func makeMemoryEvent(tsMs: Double, kvLayout: String) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: tsMs, durMs: 0,
        category: "memory", name: "memory_decision", lane: "kv_cache",
        requestId: "req1",
        metadata: ["kv_layout_used": kvLayout, "allocator_kind": kvLayout, "admitted": "True", "page_budget_estimate": "0"],
        truthBoundary: "test"
    )
}

func makeSchedulerEvent(tsMs: Double) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: tsMs, durMs: 10,
        category: "scheduler", name: "scheduling_decision", lane: "scheduler",
        requestId: "req1",
        metadata: ["priority": "conservative", "admitted": "True", "confidence": "low", "batch_policy": "single_request"],
        truthBoundary: "test"
    )
}

func makeReplayEvent(tsMs: Double) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: tsMs, durMs: 0,
        category: "replay", name: "replay_decision", lane: "runtime",
        requestId: "req1",
        metadata: ["replay_requested": "False", "eligible": "False", "bucket": "", "skipped_reason": "not_eligible"],
        truthBoundary: "test"
    )
}

func makePrefillEvent(startMs: Double, endMs: Double) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: startMs, durMs: endMs - startMs,
        category: "compute", name: "tiny_gpt_prefill", lane: "cpu",
        requestId: "req1",
        metadata: ["backend": "cpu", "kv_layout": "contiguous", "replay_requested": "False", "vs_compiler_backend": "match"],
        truthBoundary: "test"
    )
}

func makeDecodeEvent(startMs: Double, endMs: Double) -> RuntimeTraceEvent {
    RuntimeTraceEvent(
        tsMs: startMs, durMs: endMs - startMs,
        category: "compute", name: "tiny_gpt_decode", lane: "cpu",
        requestId: "req1",
        metadata: ["backend": "coreml", "kv_layout": "contiguous", "replay_requested": "False", "vs_compiler_backend": "match"],
        truthBoundary: "test"
    )
}

let fixtureEvents: [RuntimeTraceEvent] = [
    makeBackendEvent(tsMs: 0,  backend: "cpu"),
    makeMemoryEvent(tsMs: 10,  kvLayout: "contiguous"),
    makeSchedulerEvent(tsMs: 20),
    makeReplayEvent(tsMs: 30),
    makePrefillEvent(startMs: 50, endMs: 200),
    makeBackendEvent(tsMs: 60, backend: "coreml"),
    makeDecodeEvent(startMs: 220, endMs: 340),
]

let fixtureTimeseries = RuntimeTraceTimeseries(
    timestampsMs:   [50,   150,  250],
    queueDepth:     [4,    2,    1  ],
    memoryMb:       [100,  200,  150],
    activeRequests: [1,    1,    0  ]
)

let fixtureSummary = TraceVariantSummary(
    p50LatencyMs: 200, p95LatencyMs: 340,
    peakMemoryMb: 200, avgQueueDepth: 2,
    totalEvents: 7, totalRequests: 1,
    truthBoundary: "test"
)

let fixtureVariant = RuntimeTraceVariant(
    variantId: "test",
    totalDurationMs: 400,
    events: fixtureEvents,
    timeseries: fixtureTimeseries,
    summary: fixtureSummary
)

func makeEngine() -> RuntimePlaybackEngine {
    RuntimePlaybackEngine(
        variant: fixtureVariant,
        targetProfileId: "apple-a17pro-mobile",
        compilerPlanRef: "test/plan.json",
        truthBoundary: "test_boundary"
    )
}

// MARK: - Tests: seek / step / reset

let e1 = makeEngine()
e1.seek(toMs: 100)
checkEq(e1.currentTimeMs, 100.0, "seek sets currentTimeMs")

let e2 = makeEngine()
e2.seek(toMs: -50)
checkEq(e2.currentTimeMs, 0.0, "seek clamps to 0 below range")

let e3 = makeEngine()
e3.seek(toMs: 9999)
checkEq(e3.currentTimeMs, 400.0, "seek clamps to totalDurationMs above range")

let e4 = makeEngine()
e4.play()
e4.step(deltaMs: 50)
checkEq(e4.currentTimeMs, 50.0, "step advances currentTimeMs when playing")

let e5 = makeEngine()
e5.step(deltaMs: 50)
checkEq(e5.currentTimeMs, 0.0, "step does nothing when paused")

let e6 = makeEngine()
e6.play()
e6.step(deltaMs: 500)
checkEq(e6.currentTimeMs, 400.0, "step clamps to totalDurationMs")
check(!e6.isPlaying, "step stops playback at end")

let e7 = makeEngine()
e7.play()
e7.seek(toMs: 200)
e7.reset()
checkEq(e7.currentTimeMs, 0.0, "reset returns to zero")
check(!e7.isPlaying, "reset stops playback")

// MARK: - Tests: active events

let eActive = makeEngine()
// At t=15: backend (tsMs=0, durMs=0, window=25ms → active until 25)
//           memory (tsMs=10, durMs=0, window=25ms → active until 35)
eActive.seek(toMs: 15)
let stateAt15 = eActive.currentState()
check(stateAt15.activeEvents.contains { $0.category == "backend" && $0.name == "backend_dispatch" },
      "backend event active at t=15 (within 25ms window)")
check(stateAt15.activeEvents.contains { $0.category == "memory" },
      "memory event active at t=15 (within 25ms window)")

// At t=30: backend window [0,25) expired; replay just arrived (tsMs=30, window=25ms)
eActive.seek(toMs: 30)
let stateAt30 = eActive.currentState()
check(!stateAt30.activeEvents.contains { $0.category == "backend" && $0.tsMs == 0 },
      "first backend event expired at t=30")
check(stateAt30.activeEvents.contains { $0.category == "replay" },
      "replay event active at t=30")

// At t=100: prefill compute active [50,200)
eActive.seek(toMs: 100)
let stateAt100 = eActive.currentState()
check(stateAt100.activeEvents.contains { $0.category == "compute" && $0.name.contains("prefill") },
      "prefill compute active at t=100")

// At t=210: prefill ended at 200; decode not yet started at 220
eActive.seek(toMs: 210)
let stateAt210 = eActive.currentState()
check(!stateAt210.activeEvents.contains { $0.name.contains("prefill") },
      "prefill expired at t=210")
check(!stateAt210.activeEvents.contains { $0.name.contains("decode") },
      "decode not yet active at t=210")

// MARK: - Tests: persistent backend state

// At t=55: first backend (cpu) emitted at t=0; second (coreml) at t=60 — not yet seen
eActive.seek(toMs: 55)
let stateAt55 = eActive.currentState()
checkEq(stateAt55.currentBackend, "cpu", "backend persists as cpu before second backend event")

// At t=70: second backend event (coreml) at t=60 — now seen
eActive.seek(toMs: 70)
let stateAt70 = eActive.currentState()
checkEq(stateAt70.currentBackend, "coreml", "backend updates to coreml after t=60 event")

// Backend persists long after its display window closes
eActive.seek(toMs: 300)
let stateAt300 = eActive.currentState()
checkEq(stateAt300.currentBackend, "coreml", "backend persists after display window expires")

// MARK: - Tests: kvLayout

eActive.seek(toMs: 50)
checkEq(eActive.currentState().currentKVLayout, "contiguous",
        "kv_layout persists from memory event at t=10")

// MARK: - Tests: scheduler + replay state

eActive.seek(toMs: 200)
let s200 = eActive.currentState()
checkEq(s200.currentSchedulerState, "conservative", "scheduler priority persists")
checkEq(s200.currentReplayState,    "False",         "replay eligible persists")

// MARK: - Tests: memory interpolation

// t=50 → exactly at first timeseries point → 100 MB
eActive.seek(toMs: 50)
checkNear(eActive.currentState().currentMemoryMB, 100.0, tol: 0.1, "memory at t=50 = 100 MB (exact first point)")

// t=100 → midpoint between ts[0]=50 (100MB) and ts[1]=150 (200MB)
// frac = (100-50)/(150-50) = 0.5 → 100 + 0.5*100 = 150 MB
eActive.seek(toMs: 100)
checkNear(eActive.currentState().currentMemoryMB, 150.0, tol: 0.5, "memory at t=100 interpolates to 150 MB")

// t=250 → exactly at ts[2]=250 → 150 MB
eActive.seek(toMs: 250)
checkNear(eActive.currentState().currentMemoryMB, 150.0, tol: 0.1, "memory at t=250 = 150 MB (last point)")

// t=350 → past last timeseries point → clamps to last value (150 MB)
eActive.seek(toMs: 350)
checkNear(eActive.currentState().currentMemoryMB, 150.0, tol: 0.1, "memory at t=350 clamps to last value")

// MARK: - Tests: queue depth

// t=50 → 4
eActive.seek(toMs: 50)
checkEq(eActive.currentState().currentQueueDepth, 4, "queue depth at t=50 = 4")

// t=100 → midpoint between 4 and 2 = 3.0 → rounds to 3
eActive.seek(toMs: 100)
checkEq(eActive.currentState().currentQueueDepth, 3, "queue depth at t=100 interpolates to 3")

// t=200 → midpoint between 2 and 1 = 1.5 → rounds to 2
eActive.seek(toMs: 200)
checkEq(eActive.currentState().currentQueueDepth, 2, "queue depth at t=200 rounds to 2")

// MARK: - Tests: TTFT / TPOT / requests completed

// At t=100: prefill not yet done (end_ms=200)
eActive.seek(toMs: 100)
let sNoTTFT = eActive.currentState()
check(sNoTTFT.currentTTFT == nil, "TTFT nil before prefill completes")
checkEq(sNoTTFT.requestsCompleted, 0, "zero requests completed before decode done")

// At t=210: prefill ended at 200, decode not yet done
eActive.seek(toMs: 210)
let sTTFT = eActive.currentState()
check(sTTFT.currentTTFT != nil, "TTFT non-nil after prefill completes")
checkNear(sTTFT.currentTTFT!, 200.0, tol: 0.1, "TTFT = prefill end_ms = 200")
check(sTTFT.currentTPOT == nil, "TPOT nil before decode completes")
checkEq(sTTFT.requestsCompleted, 0, "requests completed still 0 before decode done")

// At t=350: decode ended at 340
eActive.seek(toMs: 350)
let sTPOT = eActive.currentState()
check(sTPOT.currentTPOT != nil, "TPOT non-nil after decode completes")
checkNear(sTPOT.currentTPOT!, 120.0, tol: 0.1, "TPOT = decode duration = 120 ms")
checkEq(sTPOT.requestsCompleted, 1, "1 request completed after decode done")

// MARK: - Tests: playbackFinished

let eFin = makeEngine()
eFin.seek(toMs: 399)
check(!eFin.currentState().playbackFinished, "not finished before totalDurationMs")
eFin.seek(toMs: 400)
check(eFin.currentState().playbackFinished, "finished at totalDurationMs")

// MARK: - Tests: ComparisonPlaybackEngine

// Build a second (optimized) variant with shorter duration
let optimizedEvents: [RuntimeTraceEvent] = [
    makeBackendEvent(tsMs: 0, backend: "coreml"),
    makePrefillEvent(startMs: 5, endMs: 25),
    makeDecodeEvent(startMs: 30, endMs: 55),
]
let optimizedTimeseries = RuntimeTraceTimeseries(
    timestampsMs: [10, 30, 50], queueDepth: [2, 1, 0], memoryMb: [50, 80, 40], activeRequests: [1, 1, 0]
)
let optimizedVariant2 = RuntimeTraceVariant(
    variantId: "optimized",
    totalDurationMs: 60,
    events: optimizedEvents,
    timeseries: optimizedTimeseries,
    summary: TraceVariantSummary(p50LatencyMs: 55, p95LatencyMs: 55, peakMemoryMb: 80, avgQueueDepth: 1, totalEvents: 3, totalRequests: 1, truthBoundary: "test")
)

let traceSummary = RuntimeProfileTraceSummary(
    schemaVersion: "1", artifactType: "runtime_profile_trace",
    targetProfileId: "apple-a17pro-mobile", modelName: "tiny-gpt",
    traceTruthBoundary: "test", compilerPlanRef: "test/plan.json",
    compilerPlanSource: "compiler_artifact", compilerPlanPath: "test/plan.json",
    doNotUseForDemo: false, provenanceNotes: [],
    baselineSummary: fixtureSummary, optimizedSummary: optimizedVariant2.summary,
    comparisonHeadline: "test headline",
    baselineVariant: fixtureVariant,
    optimizedVariant: optimizedVariant2
)

let cmp = ComparisonPlaybackEngine(trace: traceSummary)

// max duration = max(400, 60) = 400
checkNear(cmp.totalDurationMs, 400.0, tol: 0.01, "comparison totalDurationMs = max of both variants")

// seek to 50 → both engines at 50 (optimized clamps to its 60ms limit, still < 60)
cmp.seek(toMs: 50)
let cs50 = cmp.currentState()
checkNear(cs50.sharedTimeMs, 50.0, tol: 0.01, "comparison sharedTimeMs after seek")
checkNear(cs50.baseline.currentTimeMs, 50.0, tol: 0.01, "baseline engine at 50ms")
checkNear(cs50.optimized.currentTimeMs, 50.0, tol: 0.01, "optimized engine at 50ms")

// optimized finishes at 60ms; baseline continues to 400ms
cmp.seek(toMs: 100)
let cs100 = cmp.currentState()
check(cs100.optimized.playbackFinished, "optimized variant finished at t=100 (past its 60ms)")
check(!cs100.baseline.playbackFinished,  "baseline still running at t=100")

// progress at t=200 out of 400 = 0.5
cmp.seek(toMs: 200)
checkNear(cmp.currentState().progress, 0.5, tol: 0.01, "comparison progress = 0.5 at midpoint")

// comparison engines stay synchronized after multiple steps
cmp.reset()
cmp.play()
cmp.step(deltaMs: 30)
cmp.step(deltaMs: 20)
let csStepped = cmp.currentState()
checkNear(csStepped.sharedTimeMs, 50.0, tol: 0.01, "comparison engine advances via step")
checkNear(csStepped.baseline.currentTimeMs, 50.0, tol: 0.01, "baseline synchronized after steps")
checkNear(csStepped.optimized.currentTimeMs, 50.0, tol: 0.01, "optimized synchronized after steps")

// reset returns both sub-engines to zero
cmp.reset()
checkEq(cmp.sharedTimeMs, 0.0, "comparison reset returns to zero")
check(!cmp.isPlaying, "comparison not playing after reset")

    // MARK: - Results

    print()
    print("Results: \(passCount) passed, \(failCount) failed")
    if failCount > 0 { exit(1) }
} // end runAllTests
