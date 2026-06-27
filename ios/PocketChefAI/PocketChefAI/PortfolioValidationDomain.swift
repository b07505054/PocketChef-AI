import Foundation

@MainActor
final class ValidationDomain: ObservableObject {
    @Published private(set) var report: CompilerRuntimeConsistencySummary?
    @Published private(set) var status: PipelineStageStatus

    init(report: CompilerRuntimeConsistencySummary? = nil, status: PipelineStageStatus = .notStarted) {
        self.report = report
        self.status = status
    }

    func update(_ report: CompilerRuntimeConsistencySummary) {
        self.report = report
        self.status = .loaded
    }

    func markLoading() {
        status = .loading
    }

    func markFailed(_ reason: String) {
        status = .failed(reason)
    }

    static var preview: ValidationDomain {
        ValidationDomain(report: .preview, status: .loaded)
    }

    static var notBundled: ValidationDomain {
        ValidationDomain(report: nil, status: .failed("report_not_bundled"))
    }
}
