import Foundation

// PortfolioCoordinator owns the four pipeline domains and the provider layer.
// It conforms to ObservableObject solely for @StateObject lifetime anchoring in SwiftUI.
// It has zero @Published properties: views must observe the individual domains,
// not the coordinator.
@MainActor
final class PortfolioCoordinator: ObservableObject {

    let device: DeviceDomain
    let compiler: CompilerDomain
    let runtime: RuntimeDomain
    let validation: ValidationDomain

    private let deviceProvider: any TargetDeviceProfileProviding
    private let compilerProvider: any CompilerArtifactProviding
    private let runtimeProvider: any RuntimeArtifactProviding
    private let validationProvider: any ValidationArtifactProviding

    init(
        device: DeviceDomain = DeviceDomain(),
        compiler: CompilerDomain = CompilerDomain(),
        runtime: RuntimeDomain = RuntimeDomain(),
        validation: ValidationDomain = ValidationDomain(),
        deviceProvider: any TargetDeviceProfileProviding = TargetDeviceProfileProvider(),
        compilerProvider: any CompilerArtifactProviding = CompilerArtifactProvider(),
        runtimeProvider: any RuntimeArtifactProviding = RuntimeArtifactProvider(),
        validationProvider: any ValidationArtifactProviding = ValidationArtifactProvider()
    ) {
        self.device = device
        self.compiler = compiler
        self.runtime = runtime
        self.validation = validation
        self.deviceProvider = deviceProvider
        self.compilerProvider = compilerProvider
        self.runtimeProvider = runtimeProvider
        self.validationProvider = validationProvider
    }

    func refreshDeviceProfile() async {
        device.markLoading()
        do {
            let profile = try await deviceProvider.collect()
            device.update(profile)
        } catch {
            device.markFailed(String(describing: error))
        }
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
