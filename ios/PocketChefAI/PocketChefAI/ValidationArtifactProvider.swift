import Foundation

struct ValidationArtifactProvider: ValidationArtifactProviding {
    func loadConsistencyReport() async throws -> CompilerRuntimeConsistencySummary {
        throw PortfolioProviderError.notBundled
    }
}
