import Foundation

// MARK: - Protocol

protocol RuntimeProfileTraceProviding: Sendable {
    func loadTraceSummary() async throws -> RuntimeProfileTraceSummary
}

// MARK: - Bundle loader

struct RuntimeProfileTraceProvider: RuntimeProfileTraceProviding {
    func loadTraceSummary() async throws -> RuntimeProfileTraceSummary {
        guard let url = Bundle.main.url(
            forResource: "runtime_profile_trace",
            withExtension: "json"
        ) else {
            throw PortfolioProviderError.notBundled
        }

        let data = try Data(contentsOf: url)

        let wire: RuntimeProfileTraceWire
        do {
            wire = try JSONDecoder().decode(RuntimeProfileTraceWire.self, from: data)
        } catch {
            throw PortfolioProviderError.malformedArtifact
        }

        guard wire.artifactType == "runtime_profile_trace" else {
            throw PortfolioProviderError.invalidArtifact
        }

        // do_not_use_for_demo == true is NOT an error here — the domain layer
        // surfaces it as a warning string. Loading proceeds regardless.
        // (RuntimeTracePlaybackDomain sets warning when this is true.)
        return RuntimeProfileTraceSummary(wire: wire)
    }
}
