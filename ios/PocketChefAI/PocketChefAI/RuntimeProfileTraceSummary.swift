import Foundation

// MARK: - RuntimeProfileTraceSummary
//
// Decoded from Resources/runtime_profile_trace.json.
// Source: heterogeneous-inference-runtime RuntimeProfileTrace schema v1.
//
// Full events arrays are NOT decoded here — they are large and not needed
// until a PlaybackEngine is implemented. Only top-level provenance fields
// and per-variant summaries are decoded.
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
            comparisonHeadline: "Compiler-guided runtime reduces p95 latency by 81.2%"
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
            comparisonHeadline: "[FIXTURE] Compiler artifact missing. Compiler-guided runtime reduces p95 latency by 81.2%"
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

// MARK: - Decodable wire format
//
// Separate Decodable types mirror the JSON schema from the runtime repo.
// RuntimeProfileTraceSummary itself uses camelCase stored properties
// (decoded via RuntimeProfileTraceWire adapter below).

extension RuntimeProfileTraceSummary {
    init(wire: RuntimeProfileTraceWire) {
        schemaVersion     = wire.schemaVersion
        artifactType      = wire.artifactType
        targetProfileId   = wire.targetProfileId
        modelName         = wire.modelName
        traceTruthBoundary = wire.traceTruthBoundary
        compilerPlanRef   = wire.compilerPlanRef
        compilerPlanSource = wire.compilerPlanSource
        compilerPlanPath  = wire.compilerPlanPath
        doNotUseForDemo   = wire.doNotUseForDemo
        provenanceNotes   = wire.provenanceNotes
        baselineSummary   = wire.variants.baseline.summary.toModel()
        optimizedSummary  = wire.variants.optimized.summary.toModel()
        comparisonHeadline = wire.comparisonSummary.headline
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
        case schemaVersion     = "schema_version"
        case artifactType      = "artifact_type"
        case targetProfileId   = "target_profile_id"
        case modelName         = "model_name"
        case traceTruthBoundary = "trace_truth_boundary"
        case compilerPlanRef   = "compiler_plan_ref"
        case compilerPlanSource = "compiler_plan_source"
        case compilerPlanPath  = "compiler_plan_path"
        case doNotUseForDemo   = "do_not_use_for_demo"
        case provenanceNotes   = "provenance_notes"
        case variants
        case comparisonSummary = "comparison_summary"
    }

    struct VariantsWire: Decodable {
        let baseline: VariantWire
        let optimized: VariantWire
    }

    struct VariantWire: Decodable {
        let summary: VariantSummaryWire
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
