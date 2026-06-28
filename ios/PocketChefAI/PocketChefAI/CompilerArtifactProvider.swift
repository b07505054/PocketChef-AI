import Foundation

struct CompilerArtifactProvider: CompilerArtifactProviding {
    func loadServingExecutionPlan() async throws -> ServingExecutionPlanSummary {
        guard let url = Bundle.main.url(
            forResource: "serving_execution_plan_iphone15_5",
            withExtension: "json"
        ) else {
            throw PortfolioProviderError.notBundled
        }

        let data = try Data(contentsOf: url)
        let raw = try JSONDecoder().decode(ServingExecutionPlanRaw.self, from: data)

        guard raw.artifactType == "serving_execution_plan" else {
            throw PortfolioProviderError.invalidArtifact
        }

        return raw.toSummary()
    }
}

// MARK: - Wire format (compiler artifact schema v1.0.0)
// Matches ml-graph-compiler-runtime ServingExecutionPlanExporter output.
// Not exposed outside this file — callers receive ServingExecutionPlanSummary.

private struct ServingExecutionPlanRaw: Decodable {
    let schemaVersion: String
    let artifactType: String
    let targetProfileId: String
    let modelName: String
    let numLayers: Int
    let hiddenSize: Int
    let functionPlans: [FunctionPlanRaw]

    enum CodingKeys: String, CodingKey {
        case schemaVersion    = "schema_version"
        case artifactType     = "artifact_type"
        case targetProfileId  = "target_profile_id"
        case modelName        = "model_name"
        case numLayers        = "num_layers"
        case hiddenSize       = "hidden_size"
        case functionPlans    = "function_plans"
    }

    func toSummary() -> ServingExecutionPlanSummary {
        let prefill = functionPlans.first { $0.servingPhase == "prefill" }
        let decode  = functionPlans.first { $0.servingPhase == "decode" }

        let allPasses = functionPlans
            .flatMap(\.sourcePasses)
            .reduce(into: [String]()) { acc, p in
                if !acc.contains(p) { acc.append(p) }
            }

        return ServingExecutionPlanSummary(
            modelName:            modelName,
            schemaVersion:        schemaVersion,
            sourcePasses:         allPasses,
            targetProfileId:      targetProfileId,
            prefillBackend:       prefill?.backendExecutionPlan.primaryBackend ?? "",
            decodeBackend:        decode?.backendExecutionPlan.primaryBackend  ?? "",
            decisionSource:       decode?.backendExecutionPlan.decisionSource  ?? "",
            fallbackChain:        decode?.backendExecutionPlan.fallbackChain   ?? [],
            requiredPrecision:    decode?.backendExecutionPlan.requiredPrecision ?? "",
            kvLayout:             decode?.kvPlan.layout ?? "",
            kvPrefixCacheEnabled: false,
            kvEvictionPolicy:     "",
            prefillReplayEligible: prefill?.replayPlan.replayEligible ?? false,
            decodeReplayEligible:  decode?.replayPlan.replayEligible  ?? false,
            cudaGraphBucket:      decode?.replayPlan.cudaGraphBucket  ?? "",
            prefillCostMs:        prefill?.costSummary.colocatedTotalMs ?? 0,
            decodeCostMs:         decode?.costSummary.colocatedTotalMs  ?? 0,
            schedulingConfidence: decode?.costSummary.confidence ?? "",
            costSource:           decode?.costSummary.costSource ?? "",
            cvTotalSteps:         0,
            cvMetalSteps:         0,
            cvCPUSteps:           0,
            truthBoundary:        decode?.provenance.truthBoundary
                                    ?? PortfolioTruthBoundary.compilerArtifact,
            loadedAt:             Date()
        )
    }
}

private struct FunctionPlanRaw: Decodable {
    let functionName: String
    let servingPhase: String
    let executionMode: String
    let costSummary: CostSummaryRaw
    let kvPlan: KVPlanRaw
    let replayPlan: ReplayPlanRaw
    let backendExecutionPlan: BackendExecutionPlanRaw
    let provenance: ProvenanceRaw
    let sourcePasses: [String]

    enum CodingKeys: String, CodingKey {
        case functionName        = "function_name"
        case servingPhase        = "serving_phase"
        case executionMode       = "execution_mode"
        case costSummary         = "cost_summary"
        case kvPlan              = "kv_plan"
        case replayPlan          = "replay_plan"
        case backendExecutionPlan = "backend_execution_plan"
        case provenance
        case sourcePasses        = "source_passes"
    }
}

private struct CostSummaryRaw: Decodable {
    let colocatedTotalMs: Double
    let confidence: String
    let costSource: String

    enum CodingKeys: String, CodingKey {
        case colocatedTotalMs = "colocated_total_ms"
        case confidence
        case costSource       = "cost_source"
    }
}

private struct KVPlanRaw: Decodable {
    let layout: String
    let kvByteEstimateMb: Double
    let truthBoundary: String

    enum CodingKeys: String, CodingKey {
        case layout
        case kvByteEstimateMb = "kv_byte_estimate_mb"
        case truthBoundary    = "truth_boundary"
    }
}

private struct ReplayPlanRaw: Decodable {
    let replayEligible: Bool
    let cudaGraphBucket: String
    let truthBoundary: String

    enum CodingKeys: String, CodingKey {
        case replayEligible   = "replay_eligible"
        case cudaGraphBucket  = "cuda_graph_bucket"
        case truthBoundary    = "truth_boundary"
    }
}

private struct BackendExecutionPlanRaw: Decodable {
    let primaryBackend: String
    let fallbackChain: [String]
    let decisionSource: String
    let requiredPrecision: String
    let requiredKvLayout: String
    let requiresReplay: Bool

    enum CodingKeys: String, CodingKey {
        case primaryBackend   = "primary_backend"
        case fallbackChain    = "fallback_chain"
        case decisionSource   = "decision_source"
        case requiredPrecision = "required_precision"
        case requiredKvLayout  = "required_kv_layout"
        case requiresReplay    = "requires_replay"
    }
}

private struct ProvenanceRaw: Decodable {
    let truthBoundary: String
    let costSource: String

    enum CodingKeys: String, CodingKey {
        case truthBoundary = "truth_boundary"
        case costSource    = "cost_source"
    }
}
