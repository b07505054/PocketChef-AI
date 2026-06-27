import Foundation

// MARK: - RuntimeProfileTraceSummary
//
// Decoded from Resources/runtime_profile_trace.json.
// Source: heterogeneous-inference-runtime RuntimeProfileTrace schema v1.
//
// Full variant data (events + timeseries) is decoded and available via
// baselineVariant / optimizedVariant for use by RuntimePlaybackEngine.
// The summary fields (baselineSummary, optimizedSummary) remain for lightweight
// display without accessing the full event arrays.
//
// Truth boundary: offline_runtime_simulation_not_iphone_execution.
// When compilerPlanSource == "built_in_fixture", doNotUseForDemo is true
// and RuntimeTracePlaybackDomain exposes a warning string.

struct RuntimeProfileTraceSummary: Codable, Equatable {
    let schemaVersion: String
    let artifactType: String
    let targetProfileId: String
    let modelName: String
    let traceTruthBoundary: String
    let compilerPlanRef: String
    let compilerPlanSource: String   // "compiler_artifact" | "built_in_fixture"
    let compilerPlanPath: String
    let doNotUseForDemo: Bool
    let provenanceNotes: [String]
    let baselineSummary: TraceVariantSummary
    let optimizedSummary: TraceVariantSummary
    let comparisonHeadline: String
    // Full variants — decoded from events/timeseries arrays.
    let baselineVariant: RuntimeTraceVariant
    let optimizedVariant: RuntimeTraceVariant

    var isCompilerArtifact: Bool {
        compilerPlanSource == "compiler_artifact"
    }

    static var preview: RuntimeProfileTraceSummary {
        RuntimeProfileTraceSummary(
            schemaVersion: "1",
            artifactType: "runtime_profile_trace",
            targetProfileId: "apple-a17pro-mobile",
            modelName: "tiny-gpt",
            traceTruthBoundary: "offline_runtime_simulation_not_iphone_execution",
            compilerPlanRef: "apple-a17pro-mobile/serving_execution_plan_iphone.json",
            compilerPlanSource: "compiler_artifact",
            compilerPlanPath: "artifacts/apple_demo/serving_execution_plan_iphone.json",
            doNotUseForDemo: false,
            provenanceNotes: [],
            baselineSummary: .previewBaseline,
            optimizedSummary: .previewOptimized,
            comparisonHeadline: "Compiler-guided runtime reduces p95 latency by 81.2%",
            baselineVariant: .previewBaseline,
            optimizedVariant: .previewOptimized
        )
    }

    static var fixturePreview: RuntimeProfileTraceSummary {
        RuntimeProfileTraceSummary(
            schemaVersion: "1",
            artifactType: "runtime_profile_trace",
            targetProfileId: "apple-a17pro-mobile",
            modelName: "tiny-gpt",
            traceTruthBoundary: "offline_runtime_simulation_not_iphone_execution",
            compilerPlanRef: "fixture:built_in",
            compilerPlanSource: "built_in_fixture",
            compilerPlanPath: "",
            doNotUseForDemo: true,
            provenanceNotes: ["compiler_not_in_pipeline"],
            baselineSummary: .previewBaseline,
            optimizedSummary: .previewOptimized,
            comparisonHeadline: "[FIXTURE] Compiler artifact missing. Compiler-guided runtime reduces p95 latency by 81.2%",
            baselineVariant: .previewBaseline,
            optimizedVariant: .previewOptimized
        )
    }
}

// MARK: - RuntimeTraceEvent

struct RuntimeTraceEvent: Codable, Equatable {
    let tsMs: Double          // start_ms from wire
    let durMs: Double         // duration_ms from wire
    let category: String
    let name: String
    let lane: String
    let requestId: String
    let metadata: [String: String]
    let truthBoundary: String

    var endMs: Double { tsMs + durMs }
}

// MARK: - RuntimeTraceTimeseries

struct RuntimeTraceTimeseries: Codable, Equatable {
    let timestampsMs: [Double]
    let queueDepth: [Int]
    let memoryMb: [Double]
    let activeRequests: [Int]

    static var empty: RuntimeTraceTimeseries {
        RuntimeTraceTimeseries(
            timestampsMs: [],
            queueDepth: [],
            memoryMb: [],
            activeRequests: []
        )
    }
}

// MARK: - RuntimeTraceVariant

struct RuntimeTraceVariant: Codable, Equatable {
    let variantId: String
    let totalDurationMs: Double
    let events: [RuntimeTraceEvent]
    let timeseries: RuntimeTraceTimeseries
    let summary: TraceVariantSummary

    static var previewBaseline: RuntimeTraceVariant {
        RuntimeTraceVariant(
            variantId: "baseline",
            totalDurationMs: 7900.0,
            events: [],
            timeseries: .empty,
            summary: .previewBaseline
        )
    }

    static var previewOptimized: RuntimeTraceVariant {
        RuntimeTraceVariant(
            variantId: "optimized",
            totalDurationMs: 1426.0,
            events: [],
            timeseries: .empty,
            summary: .previewOptimized
        )
    }
}

// MARK: - TraceVariantSummary

struct TraceVariantSummary: Codable, Equatable {
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let peakMemoryMb: Double
    let avgQueueDepth: Double
    let totalEvents: Int
    let totalRequests: Int
    let truthBoundary: String

    static var previewBaseline: TraceVariantSummary {
        TraceVariantSummary(
            p50LatencyMs: 226.9,
            p95LatencyMs: 226.9,
            peakMemoryMb: 580.0,
            avgQueueDepth: 6.0,
            totalEvents: 160,
            totalRequests: 32,
            truthBoundary: "offline_runtime_simulation_not_iphone_execution"
        )
    }

    static var previewOptimized: TraceVariantSummary {
        TraceVariantSummary(
            p50LatencyMs: 42.6,
            p95LatencyMs: 42.6,
            peakMemoryMb: 162.0,
            avgQueueDepth: 2.0,
            totalEvents: 160,
            totalRequests: 32,
            truthBoundary: "offline_runtime_simulation_not_iphone_execution"
        )
    }
}

// MARK: - Wire decoding
//
// RuntimeProfileTraceWire mirrors the JSON schema from the runtime repo.
// RuntimeProfileTraceSummary is always constructed via init(wire:), never
// directly via JSONDecoder, so its own Codable keys do not need to match JSON.

extension RuntimeProfileTraceSummary {
    init(wire: RuntimeProfileTraceWire) {
        schemaVersion      = wire.schemaVersion
        artifactType       = wire.artifactType
        targetProfileId    = wire.targetProfileId
        modelName          = wire.modelName
        traceTruthBoundary = wire.traceTruthBoundary
        compilerPlanRef    = wire.compilerPlanRef
        compilerPlanSource = wire.compilerPlanSource
        compilerPlanPath   = wire.compilerPlanPath
        doNotUseForDemo    = wire.doNotUseForDemo
        provenanceNotes    = wire.provenanceNotes
        baselineSummary    = wire.variants.baseline.summary.toModel()
        optimizedSummary   = wire.variants.optimized.summary.toModel()
        comparisonHeadline = wire.comparisonSummary.headline
        baselineVariant    = wire.variants.baseline.toModel()
        optimizedVariant   = wire.variants.optimized.toModel()
    }
}

struct RuntimeProfileTraceWire: Decodable {
    let schemaVersion: String
    let artifactType: String
    let targetProfileId: String
    let modelName: String
    let traceTruthBoundary: String
    let compilerPlanRef: String
    let compilerPlanSource: String
    let compilerPlanPath: String
    let doNotUseForDemo: Bool
    let provenanceNotes: [String]
    let variants: VariantsWire
    let comparisonSummary: ComparisonSummaryWire

    enum CodingKeys: String, CodingKey {
        case schemaVersion      = "schema_version"
        case artifactType       = "artifact_type"
        case targetProfileId    = "target_profile_id"
        case modelName          = "model_name"
        case traceTruthBoundary = "trace_truth_boundary"
        case compilerPlanRef    = "compiler_plan_ref"
        case compilerPlanSource = "compiler_plan_source"
        case compilerPlanPath   = "compiler_plan_path"
        case doNotUseForDemo    = "do_not_use_for_demo"
        case provenanceNotes    = "provenance_notes"
        case variants
        case comparisonSummary  = "comparison_summary"
    }

    struct VariantsWire: Decodable {
        let baseline: VariantWire
        let optimized: VariantWire
    }

    struct VariantWire: Decodable {
        let variantId: String
        let totalDurationMs: Double
        let events: [EventWire]
        let timeseries: TimeseriesWire
        let summary: VariantSummaryWire

        enum CodingKeys: String, CodingKey {
            case variantId      = "variant_id"
            case totalDurationMs = "total_duration_ms"
            case events
            case timeseries
            case summary
        }

        func toModel() -> RuntimeTraceVariant {
            RuntimeTraceVariant(
                variantId: variantId,
                totalDurationMs: totalDurationMs,
                events: events.map { $0.toModel() },
                timeseries: timeseries.toModel(),
                summary: summary.toModel()
            )
        }
    }

    struct EventWire: Decodable {
        let category: String
        let name: String
        let lane: String
        let startMs: Double
        let endMs: Double
        let durationMs: Double
        let requestId: String
        let metadata: [String: String]
        let truthBoundary: String

        enum CodingKeys: String, CodingKey {
            case category
            case name
            case lane
            case startMs      = "start_ms"
            case endMs        = "end_ms"
            case durationMs   = "duration_ms"
            case requestId    = "request_id"
            case metadata
            case truthBoundary = "truth_boundary"
        }

        func toModel() -> RuntimeTraceEvent {
            RuntimeTraceEvent(
                tsMs: startMs,
                durMs: durationMs,
                category: category,
                name: name,
                lane: lane,
                requestId: requestId,
                metadata: metadata,
                truthBoundary: truthBoundary
            )
        }
    }

    struct TimeseriesWire: Decodable {
        let timestampsMs: [Double]
        let queueDepth: [Int]
        let memoryMb: [Double]
        let activeRequests: [Int]

        enum CodingKeys: String, CodingKey {
            case timestampsMs   = "timestamps_ms"
            case queueDepth     = "queue_depth"
            case memoryMb       = "memory_mb"
            case activeRequests = "active_requests"
        }

        func toModel() -> RuntimeTraceTimeseries {
            RuntimeTraceTimeseries(
                timestampsMs: timestampsMs,
                queueDepth: queueDepth,
                memoryMb: memoryMb,
                activeRequests: activeRequests
            )
        }
    }

    struct VariantSummaryWire: Decodable {
        let p50LatencyMs: Double
        let p95LatencyMs: Double
        let peakMemoryMb: Double
        let avgQueueDepth: Double
        let totalEvents: Int
        let totalRequests: Int
        let truthBoundary: String

        enum CodingKeys: String, CodingKey {
            case p50LatencyMs  = "p50_latency_ms"
            case p95LatencyMs  = "p95_latency_ms"
            case peakMemoryMb  = "peak_memory_mb"
            case avgQueueDepth = "avg_queue_depth"
            case totalEvents   = "total_events"
            case totalRequests = "total_requests"
            case truthBoundary = "truth_boundary"
        }

        func toModel() -> TraceVariantSummary {
            TraceVariantSummary(
                p50LatencyMs:  p50LatencyMs,
                p95LatencyMs:  p95LatencyMs,
                peakMemoryMb:  peakMemoryMb,
                avgQueueDepth: avgQueueDepth,
                totalEvents:   totalEvents,
                totalRequests: totalRequests,
                truthBoundary: truthBoundary
            )
        }
    }

    struct ComparisonSummaryWire: Decodable {
        let headline: String
    }
}
