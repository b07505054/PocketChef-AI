import Foundation

@MainActor
final class CompilerDomain: ObservableObject {
    @Published private(set) var servingPlan: ServingExecutionPlanSummary?
    @Published private(set) var status: PipelineStageStatus

    init(servingPlan: ServingExecutionPlanSummary? = nil, status: PipelineStageStatus = .notStarted) {
        self.servingPlan = servingPlan
        self.status = status
    }

    func update(_ plan: ServingExecutionPlanSummary) {
        self.servingPlan = plan
        self.status = .loaded
    }

    func markLoading() {
        status = .loading
    }

    func markFailed(_ reason: String) {
        status = .failed(reason)
    }

    static var preview: CompilerDomain {
        CompilerDomain(servingPlan: .preview, status: .loaded)
    }

    static var notBundled: CompilerDomain {
        CompilerDomain(servingPlan: nil, status: .failed("artifact_not_bundled"))
    }
}
