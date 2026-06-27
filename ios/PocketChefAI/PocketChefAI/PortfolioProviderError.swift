import Foundation

enum PortfolioProviderError: Error {
    case notBundled
    case unsupported
    case permissionDenied
    case invalidArtifact
    case malformedArtifact
}
