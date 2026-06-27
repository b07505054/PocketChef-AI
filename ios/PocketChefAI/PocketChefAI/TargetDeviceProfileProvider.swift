import Foundation
import UIKit
import Metal

struct TargetDeviceProfileProvider: TargetDeviceProfileProviding {

    func collect() async throws -> TargetDeviceProfile {
        // Metal — safe to create on any thread
        let metalDevice = MTLCreateSystemDefaultDevice()
        let metalName = metalDevice?.name
        let metalMaxWorkingSetMB = metalDevice.map {
            Int($0.recommendedMaxWorkingSetSize / (1024 * 1024))
        }

        // ProcessInfo — documented thread-safe
        let physicalMemory = ProcessInfo.processInfo.physicalMemory
        let physicalProcessorCount = Self.physicalProcessorCount()
        let thermalState = Self.thermalString(ProcessInfo.processInfo.thermalState)
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // UIDevice — MainActor-isolated in iOS SDK
        let systemVersion = await MainActor.run { UIDevice.current.systemVersion }

        let modelIdentifier = Self.modelIdentifier()
        let chipName = Self.chipName(from: metalName)
        let profileId = Self.profileId(modelIdentifier: modelIdentifier, chip: chipName)
        // Derive compute units from hardware availability; ANE assumed present on Metal-capable iPhones.
        // configuredComputeUnits reflects platform capability, not a measured CoreML configuration.
        let configuredComputeUnits = metalDevice != nil ? "CPU+GPU+ANE" : "CPU"

        return TargetDeviceProfile(
            profileId: profileId,
            modelIdentifier: modelIdentifier,
            chipName: chipName,
            totalRAMBytes: physicalMemory,
            metalGPUName: metalName,
            metalMaxWorkingSetMB: metalMaxWorkingSetMB,
            physicalProcessorCount: physicalProcessorCount,
            configuredComputeUnits: configuredComputeUnits,
            thermalState: thermalState,
            isLowPowerMode: isLowPowerMode,
            iosVersion: systemVersion,
            truthBoundary: PortfolioTruthBoundary.deviceProfile,
            collectedAt: Date()
        )
    }

    // Returns hw.machine identifier (e.g. "iPhone16,2") via POSIX uname.
    private static func modelIdentifier() -> String {
        var info = utsname()
        guard uname(&info) == 0 else { return "unknown" }
        return withUnsafeBytes(of: &info.machine) { buffer in
            guard let base = buffer.bindMemory(to: CChar.self).baseAddress else {
                return "unknown"
            }
            return String(cString: base)
        }
    }

    // Extracts chip name from MTLDevice.name (e.g. "Apple A17 Pro GPU" → "A17 Pro").
    private static func chipName(from metalName: String?) -> String {
        guard let name = metalName else { return "unknown" }
        return name
            .replacingOccurrences(of: "Apple ", with: "")
            .replacingOccurrences(of: " GPU", with: "")
    }

    private static func profileId(modelIdentifier: String, chip: String) -> String {
        let model = modelIdentifier.lowercased().replacingOccurrences(of: ",", with: "-")
        let chipSlug = chip.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
        return "apple-\(model)-\(chipSlug)"
    }

    // physicalProcessorCount is macOS-only; use processorCount on iOS (logical count).
    // Value is device metadata only — not a measured performance figure.
    private static func physicalProcessorCount() -> Int {
#if os(iOS)
        return ProcessInfo.processInfo.processorCount
#else
        return ProcessInfo.processInfo.physicalProcessorCount
#endif
    }

    private static func thermalString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
