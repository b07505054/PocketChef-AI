import Foundation

// PortfolioCoordinator owns the four pipeline domains and anchors their lifetimes
// via @StateObject. It conforms to ObservableObject solely for @StateObject compatibility.
// It has zero @Published properties: views must observe the individual domains,
// not the coordinator.
@MainActor
final class PortfolioCoordinator: ObservableObject {

    let device: DeviceDomain
    let compiler: CompilerDomain
    let runtime: RuntimeDomain
    let validation: ValidationDomain

    init(
        device: DeviceDomain = DeviceDomain(),
        compiler: CompilerDomain = CompilerDomain(),
        runtime: RuntimeDomain = RuntimeDomain(),
        validation: ValidationDomain = ValidationDomain()
    ) {
        self.device = device
        self.compiler = compiler
        self.runtime = runtime
        self.validation = validation
    }

    static var preview: PortfolioCoordinator {
        PortfolioCoordinator(
            device: .preview,
            compiler: .preview,
            runtime: .preview,
            validation: .preview
        )
    }
}
