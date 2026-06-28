import Foundation

// MARK: - Truth Boundary Constants

enum PortfolioTruthBoundary {
    static let deviceProfile    = "declared_device_profile_not_measured_silicon_performance"
    static let compilerArtifact = "artifact_backed_not_live_compilation"
    static let runtimeResult            = "live_runtime_on_device_not_compiler_plan"
    static let simulatedRuntimeSnapshot = "offline_simulation_not_live_device_execution"
    static let validationReport = "validation_of_compiler_runtime_consistency_not_measured_performance"
    static let performanceMetrics = "measured_on_device_inference"
}

// MARK: - Pipeline Stage Status

enum PipelineStageStatus: Equatable, Codable {
    case notStarted
    case loading
    case loaded
    case failed(String)
}

// MARK: - TargetDeviceProfile

struct TargetDeviceProfile: Codable, Equatable {
    let profileId: String
    let modelIdentifier: String
    let chipName: String
    let totalRAMBytes: UInt64
    let metalGPUName: String?
    let metalMaxWorkingSetMB: Int?
    let physicalProcessorCount: Int
    let configuredComputeUnits: String
    let thermalState: String
    let isLowPowerMode: Bool
    let iosVersion: String
    let truthBoundary: String
    let collectedAt: Date

    static var preview: TargetDeviceProfile {
        TargetDeviceProfile(
            profileId: "apple-a17pro-mobile",
            modelIdentifier: "iPhone16,2",
            chipName: "A17 Pro",
            totalRAMBytes: 8_589_934_592,
            metalGPUName: "Apple A17 Pro GPU",
            metalMaxWorkingSetMB: 5461,
            physicalProcessorCount: 6,
            configuredComputeUnits: "CPU+GPU+ANE",
            thermalState: "nominal",
            isLowPowerMode: false,
            iosVersion: "18.3.2",
            truthBoundary: PortfolioTruthBoundary.deviceProfile,
            collectedAt: Date()
        )
    }
}

// MARK: - ServingExecutionPlanSummary

struct ServingExecutionPlanSummary: Codable, Equatable {
    let modelName: String
    let schemaVersion: String
    let sourcePasses: [String]
    let targetProfileId: String
    let prefillBackend: String
    let decodeBackend: String
    let decisionSource: String
    let fallbackChain: [String]
    let requiredPrecision: String
    let kvLayout: String
    let kvPrefixCacheEnabled: Bool
    let kvEvictionPolicy: String
    let prefillReplayEligible: Bool
    let decodeReplayEligible: Bool
    let cudaGraphBucket: String
    let prefillCostMs: Double
    let decodeCostMs: Double
    let schedulingConfidence: String
    let costSource: String
    let cvTotalSteps: Int
    let cvMetalSteps: Int
    let cvCPUSteps: Int
    let truthBoundary: String
    let loadedAt: Date

    static var preview: ServingExecutionPlanSummary {
        ServingExecutionPlanSummary(
            modelName: "tiny-gpt",
            schemaVersion: "0.1",
            sourcePasses: [
                "serving-phase-analysis",
                "kv-layout-planning",
                "replay-eligibility",
                "execution-provider-planning"
            ],
            targetProfileId: "",
            prefillBackend: "gpu",
            decodeBackend: "cpu_or_gpu",
            decisionSource: "target_preferred",
            fallbackChain: ["metal", "cpu"],
            requiredPrecision: "fp16",
            kvLayout: "contiguous",
            kvPrefixCacheEnabled: true,
            kvEvictionPolicy: "lru_finished_prefix",
            prefillReplayEligible: false,
            decodeReplayEligible: true,
            cudaGraphBucket: "decode_static",
            prefillCostMs: 31.2,
            decodeCostMs: 4.8,
            schedulingConfidence: "low",
            costSource: "formula_synthetic",
            cvTotalSteps: 8,
            cvMetalSteps: 3,
            cvCPUSteps: 5,
            truthBoundary: PortfolioTruthBoundary.compilerArtifact,
            loadedAt: Date()
        )
    }
}

// MARK: - RuntimeExecutionPlanSummary

struct RuntimeExecutionPlanSummary: Codable, Equatable {
    let functionName: String
    let executionMode: String
    let backendPolicySummary: String
    let kvPolicySummary: String
    let replayPolicySummary: String
    let compilerProvenance: String
    let truthBoundary: String
    let loadedAt: Date

    static var preview: RuntimeExecutionPlanSummary {
        RuntimeExecutionPlanSummary(
            functionName: "decode",
            executionMode: "colocated",
            backendPolicySummary: "coreml / metal / cpu",
            kvPolicySummary: "contiguous",
            replayPolicySummary: "eligible",
            compilerProvenance: "compiler_execution_provider_plan_not_runtime_dispatch",
            truthBoundary: PortfolioTruthBoundary.simulatedRuntimeSnapshot,
            loadedAt: Date()
        )
    }
}

// MARK: - RuntimeResultSummary

struct RuntimeResultSummary: Codable, Equatable {
    let functionName: String
    let executionMode: String
    let schedulingPriority: String
    let schedulingAdmitted: Bool
    let kvLayoutUsed: String
    let estimatedMemoryMB: Double
    let memoryAdmitted: Bool
    let pageBudgetEstimate: Int
    let replayRequested: Bool
    let replayEligible: Bool
    let replayCaptured: Bool
    let replaySkippedReason: String
    let selectedBackend: String
    let vsCompilerBackend: String
    let overrideReason: String
    let liveBackendString: String
    let optimizationModeLabel: String
    let maskDecodePath: String
    let currentMemoryMB: Double
    let peakMemoryMB: Double
    let fpsSnapshot: Double
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let frameCount: Int
    let modelArtifactSizeMB: Double
    let decisionTrace: [String]
    let truthBoundary: String
    let snapshotAt: Date

    static var preview: RuntimeResultSummary {
        RuntimeResultSummary(
            functionName: "decode",
            executionMode: "colocated",
            schedulingPriority: "conservative",
            schedulingAdmitted: true,
            kvLayoutUsed: "contiguous",
            estimatedMemoryMB: 6.75,
            memoryAdmitted: true,
            pageBudgetEstimate: 7,
            replayRequested: true,
            replayEligible: true,
            replayCaptured: false,
            replaySkippedReason: "capture_not_implemented",
            selectedBackend: "coreml",
            vsCompilerBackend: "match",
            overrideReason: "",
            liveBackendString: "YOLO-Seg Vision/Core ML (CPU+GPU+ANE)",
            optimizationModeLabel: "Baseline",
            maskDecodePath: "baseline bbox-crop",
            currentMemoryMB: 142.3,
            peakMemoryMB: 168.7,
            fpsSnapshot: 12.4,
            p50LatencyMs: 81.3,
            p95LatencyMs: 94.7,
            frameCount: 37,
            modelArtifactSizeMB: 6.2,
            decisionTrace: [
                "compiler_runtime_adapter",
                "scheduling_decision_evaluator",
                "memory_decision_evaluator",
                "replay_decision_evaluator",
                "backend_dispatcher",
                "execution_engine"
            ],
            truthBoundary: PortfolioTruthBoundary.simulatedRuntimeSnapshot,
            snapshotAt: Date()
        )
    }
}

// MARK: - DecisionDelta

struct DecisionDelta: Codable, Equatable {
    let compilerValue: String
    let runtimeValue: String
    let status: String
    let deltaNote: String
}

// MARK: - CheckSummary

struct CheckSummary: Codable, Equatable {
    let totalChecks: Int
    let pass: Int
    let warn: Int
    let fail: Int
}

// MARK: - CompilerRuntimeConsistencySummary

struct CompilerRuntimeConsistencySummary: Codable, Equatable {
    let overallStatus: String
    let targetProfileId: String
    let backendDelta: DecisionDelta
    let kvDelta: DecisionDelta
    let replayDelta: DecisionDelta
    let schedulingDelta: DecisionDelta
    let decisionTraceOrdered: Bool
    let decisionTraceStages: [String]
    let decisionTraceStageStatus: [String]
    let compilerBoundaryPresent: Bool
    let memoryBoundaryPresent: Bool
    let replayBoundaryPresent: Bool
    let runtimeBoundaryPresent: Bool
    let checkSummary: CheckSummary
    let recommendations: [String]
    let truthBoundary: String
    let reportGeneratedAt: Date
    let loadedAt: Date

    static var preview: CompilerRuntimeConsistencySummary {
        CompilerRuntimeConsistencySummary(
            overallStatus: "warn",
            targetProfileId: "apple-a17pro-mobile",
            backendDelta: DecisionDelta(
                compilerValue: "coreml",
                runtimeValue: "coreml",
                status: "match",
                deltaNote: "Runtime selected compiler-preferred backend"
            ),
            kvDelta: DecisionDelta(
                compilerValue: "contiguous",
                runtimeValue: "contiguous",
                status: "match",
                deltaNote: "KV layout preserved through adapter"
            ),
            replayDelta: DecisionDelta(
                compilerValue: "eligible · decode_static",
                runtimeValue: "not captured",
                status: "not_implemented",
                deltaNote: "Compiler declared decode eligible; capture_not_implemented"
            ),
            schedulingDelta: DecisionDelta(
                compilerValue: "4.8 ms · confidence=low",
                runtimeValue: "conservative",
                status: "cost_to_priority",
                deltaNote: "confidence=low maps to priority=conservative"
            ),
            decisionTraceOrdered: true,
            decisionTraceStages: [
                "compiler_runtime_adapter",
                "scheduling_decision_evaluator",
                "memory_decision_evaluator",
                "replay_decision_evaluator",
                "backend_dispatcher",
                "execution_engine"
            ],
            decisionTraceStageStatus: ["pass", "pass", "pass", "pass", "pass", "pass"],
            compilerBoundaryPresent: true,
            memoryBoundaryPresent: true,
            replayBoundaryPresent: true,
            runtimeBoundaryPresent: true,
            checkSummary: CheckSummary(totalChecks: 20, pass: 19, warn: 1, fail: 0),
            recommendations: ["Provide execution_statistics to remove measurement gap warning"],
            truthBoundary: PortfolioTruthBoundary.validationReport,
            reportGeneratedAt: Date(),
            loadedAt: Date()
        )
    }
}
