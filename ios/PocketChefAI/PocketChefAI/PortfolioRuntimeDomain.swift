import Foundation

@MainActor
final class RuntimeDomain: ObservableObject {
    @Published private(set) var runtimePlan: RuntimeExecutionPlanSummary?
    @Published private(set) var runtimeResult: RuntimeResultSummary?
    @Published private(set) var status: PipelineStageStatus

    init(
        runtimePlan: RuntimeExecutionPlanSummary? = nil,
        runtimeResult: RuntimeResultSummary? = nil,
        status: PipelineStageStatus = .notStarted
    ) {
        self.runtimePlan = runtimePlan
        self.runtimeResult = runtimeResult
        self.status = status
    }

    func updatePlan(_ plan: RuntimeExecutionPlanSummary) {
        self.runtimePlan = plan
        if case .loaded = status {} else {
            status = .loading
        }
    }

    func updateResult(_ result: RuntimeResultSummary) {
        self.runtimeResult = result
        self.status = .loaded
    }

    func markLoading() {
        status = .loading
    }

    func markFailed(_ reason: String) {
        status = .failed(reason)
    }

    static var preview: RuntimeDomain {
        RuntimeDomain(
            runtimePlan: .preview,
            runtimeResult: .preview,
            status: .loaded
        )
    }

    static var waiting: RuntimeDomain {
        RuntimeDomain(runtimePlan: nil, runtimeResult: nil, status: .notStarted)
    }
}
