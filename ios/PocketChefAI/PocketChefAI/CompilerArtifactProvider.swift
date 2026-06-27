import Foundation

struct CompilerArtifactProvider: CompilerArtifactProviding {
    func loadServingExecutionPlan() async throws -> ServingExecutionPlanSummary {
        throw PortfolioProviderError.notBundled
    }
}
