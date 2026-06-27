import Foundation

struct RuntimeArtifactProvider: RuntimeArtifactProviding {
    func loadRuntimeSnapshot() async throws -> (RuntimeExecutionPlanSummary, RuntimeResultSummary) {
        throw PortfolioProviderError.notBundled
    }
}
