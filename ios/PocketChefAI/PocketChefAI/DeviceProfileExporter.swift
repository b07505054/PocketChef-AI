import Foundation

// DeviceProfileExporter serializes a TargetDeviceProfile to the canonical
// target_device_profile.json schema for export to the compiler repo.
// All field values originate from TargetDeviceProfileProvider — nothing is
// collected here.

private struct TargetDeviceProfileExportWire: Encodable {
    let schemaVersion: String
    let capturedAt: Date
    let modelIdentifier: String
    let systemName: String
    let systemVersion: String
    let chipName: String
    let metalDeviceName: String?
    let metalMaxWorkingSetMb: Int?
    let physicalMemoryBytes: UInt64
    let processorCount: Int
    let activeProcessorCount: Int
    let configuredComputeUnits: String
    let thermalState: String
    let lowPowerModeEnabled: Bool
    let isSimulator: Bool
    let profileId: String
    let truthBoundary: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion          = "schema_version"
        case capturedAt             = "captured_at"
        case modelIdentifier        = "model_identifier"
        case systemName             = "system_name"
        case systemVersion          = "system_version"
        case chipName               = "chip_name"
        case metalDeviceName        = "metal_device_name"
        case metalMaxWorkingSetMb   = "metal_max_working_set_mb"
        case physicalMemoryBytes    = "physical_memory_bytes"
        case processorCount         = "processor_count"
        case activeProcessorCount   = "active_processor_count"
        case configuredComputeUnits = "configured_compute_units"
        case thermalState           = "thermal_state"
        case lowPowerModeEnabled    = "low_power_mode_enabled"
        case isSimulator            = "is_simulator"
        case profileId              = "profile_id"
        case truthBoundary          = "truth_boundary"
    }

    init(profile: TargetDeviceProfile) {
        schemaVersion          = profile.schemaVersion
        capturedAt             = profile.collectedAt
        modelIdentifier        = profile.modelIdentifier
        systemName             = profile.systemName
        systemVersion          = profile.iosVersion
        chipName               = profile.chipName
        metalDeviceName        = profile.metalGPUName
        metalMaxWorkingSetMb   = profile.metalMaxWorkingSetMB
        physicalMemoryBytes    = profile.totalRAMBytes
        processorCount         = profile.physicalProcessorCount
        activeProcessorCount   = profile.activeProcessorCount
        configuredComputeUnits = profile.configuredComputeUnits
        thermalState           = profile.thermalState
        lowPowerModeEnabled    = profile.isLowPowerMode
        isSimulator            = profile.isSimulator
        profileId              = profile.profileId
        truthBoundary          = profile.truthBoundary
    }
}

func deviceProfileJSON(from profile: TargetDeviceProfile) -> String {
    let wire = TargetDeviceProfileExportWire(profile: profile)
    guard
        let data = try? JSONEncoder.deviceProfileEncoder.encode(wire),
        let text = String(data: data, encoding: .utf8)
    else { return "{}" }
    return text
}

private extension JSONEncoder {
    static var deviceProfileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
