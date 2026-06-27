import Foundation

protocol TargetDeviceProfileProviding: Sendable {
    func collect() async throws -> TargetDeviceProfile
}

protocol CompilerArtifactProviding: Sendable {
    func loadServingExecutionPlan() async throws -> ServingExecutionPlanSummary
}

protocol RuntimeArtifactProviding: Sendable {
    func loadRuntimeSnapshot() async throws -> (
        RuntimeExecutionPlanSummary,
        RuntimeResultSummary
    )
}

protocol ValidationArtifactProviding: Sendable {
    func loadConsistencyReport() async throws -> CompilerRuntimeConsistencySummary
}
