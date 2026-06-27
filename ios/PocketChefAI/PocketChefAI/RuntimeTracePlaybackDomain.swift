import Foundation

// RuntimeTracePlaybackDomain owns loading and provenance validation of the
// bundled runtime_profile_trace.json artifact.
//
// PlaybackEngine (future commit) will be injected into this domain.
// This commit only loads, validates provenance, and exposes warning state.
//
// Warning contract (PocketChef must render when warning != nil):
//   "⚠ Development Fixture — compiler pipeline is bypassed."
// This is the visible warning promised by the runtime repo's do_not_use_for_demo flag.

@MainActor
final class RuntimeTracePlaybackDomain: ObservableObject {
    @Published private(set) var trace: RuntimeProfileTraceSummary?
    @Published private(set) var status: PipelineStageStatus = .notStarted
    @Published private(set) var warning: String?

    private let provider: any RuntimeProfileTraceProviding

    init(provider: any RuntimeProfileTraceProviding = RuntimeProfileTraceProvider()) {
        self.provider = provider
    }

    func load() async {
        status = .loading
        warning = nil
        do {
            let loaded = try await provider.loadTraceSummary()
            trace = loaded
            if loaded.doNotUseForDemo || !loaded.isCompilerArtifact {
                warning = "⚠ Development Fixture — compiler pipeline is bypassed."
            }
            status = .loaded
        } catch {
            status = .failed(String(describing: error))
        }
    }

    // MARK: - Previews

    static var preview: RuntimeTracePlaybackDomain {
        let d = RuntimeTracePlaybackDomain(provider: _PreviewProvider(trace: .preview))
        d.trace = .preview
        d.status = .loaded
        return d
    }

    static var fixtureWarningPreview: RuntimeTracePlaybackDomain {
        let d = RuntimeTracePlaybackDomain(provider: _PreviewProvider(trace: .fixturePreview))
        d.trace = .fixturePreview
        d.status = .loaded
        d.warning = "⚠ Development Fixture — compiler pipeline is bypassed."
        return d
    }
}

// Private preview provider — returns a fixed summary without touching the bundle.
private struct _PreviewProvider: RuntimeProfileTraceProviding {
    let trace: RuntimeProfileTraceSummary
    func loadTraceSummary() async throws -> RuntimeProfileTraceSummary { trace }
}
