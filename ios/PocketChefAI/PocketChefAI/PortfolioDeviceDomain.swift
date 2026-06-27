import Foundation

@MainActor
final class DeviceDomain: ObservableObject {
    @Published private(set) var profile: TargetDeviceProfile?
    @Published private(set) var status: PipelineStageStatus

    init(profile: TargetDeviceProfile? = nil, status: PipelineStageStatus = .notStarted) {
        self.profile = profile
        self.status = status
    }

    func update(_ profile: TargetDeviceProfile) {
        self.profile = profile
        self.status = .loaded
    }

    func markLoading() {
        status = .loading
    }

    func markFailed(_ reason: String) {
        status = .failed(reason)
    }

    static var preview: DeviceDomain {
        DeviceDomain(profile: .preview, status: .loaded)
    }

    static var failed: DeviceDomain {
        DeviceDomain(profile: nil, status: .failed("ios_api_error"))
    }
}
