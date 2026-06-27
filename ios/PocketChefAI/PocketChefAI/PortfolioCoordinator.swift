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
    let trace: RuntimeTracePlaybackDomain

    private let deviceProvider: any TargetDeviceProfileProviding
    private let compilerProvider: any CompilerArtifactProviding
    private let runtimeProvider: any RuntimeArtifactProviding
    private let validationProvider: any ValidationArtifactProviding

    // Default no-arg init: creates all domains and providers on the main actor.
    // Avoids @ActorIsolatedCall errors that arise from using @MainActor domain
    // initializers as default parameter expressions.
    init() {
        device = DeviceDomain()
        compiler = CompilerDomain()
        runtime = RuntimeDomain()
        validation = ValidationDomain()
        trace = RuntimeTracePlaybackDomain()
        deviceProvider = TargetDeviceProfileProvider()
        compilerProvider = CompilerArtifactProvider()
        runtimeProvider = RuntimeArtifactProvider()
        validationProvider = ValidationArtifactProvider()
    }

    // Injection init for testing and SwiftUI previews.
    init(
        device: DeviceDomain,
        compiler: CompilerDomain,
        runtime: RuntimeDomain,
        validation: ValidationDomain,
        trace: RuntimeTracePlaybackDomain,
        deviceProvider: any TargetDeviceProfileProviding = TargetDeviceProfileProvider(),
        compilerProvider: any CompilerArtifactProviding = CompilerArtifactProvider(),
        runtimeProvider: any RuntimeArtifactProviding = RuntimeArtifactProvider(),
        validationProvider: any ValidationArtifactProviding = ValidationArtifactProvider()
    ) {
        self.device = device
        self.compiler = compiler
        self.runtime = runtime
        self.validation = validation
        self.trace = trace
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

    // Load compiler plan and runtime trace concurrently.
    func loadCompilerArtifacts() async {
        async let compilerLoad: Void = loadCompilerPlan()
        async let traceLoad: Void    = trace.load()
        _ = await (compilerLoad, traceLoad)
    }

    func loadCompilerPlan() async {
        compiler.markLoading()
        do {
            let plan = try await compilerProvider.loadServingExecutionPlan()
            compiler.update(plan)
        } catch {
            compiler.markFailed(String(describing: error))
        }
    }

    static var preview: PortfolioCoordinator {
        PortfolioCoordinator(
            device: .preview,
            compiler: .preview,
            runtime: .preview,
            validation: .preview,
            trace: .preview
        )
    }
}
