import Foundation
import MachO

struct MemorySample: Equatable {
    let physicalFootprintMB: Double
    let residentSizeMB: Double
}

struct MemoryEvent: Codable, Equatable, Identifiable {
    let id: UUID
    let timestamp: Date
    let event: String
    let mode: String
    let rssMB: Double
    let physicalFootprintMB: Double
    let peakPhysicalFootprintMB: Double
    let deltaFromPreviousMB: Double
    let model: String
    let computeUnits: String
    let metadata: [String: String]

    init(
        event: String,
        mode: String,
        sample: MemorySample,
        peakPhysicalFootprintMB: Double,
        deltaFromPreviousMB: Double,
        model: String,
        computeUnits: String,
        metadata: [String: String]
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.event = event
        self.mode = mode
        self.rssMB = sample.residentSizeMB
        self.physicalFootprintMB = sample.physicalFootprintMB
        self.peakPhysicalFootprintMB = peakPhysicalFootprintMB
        self.deltaFromPreviousMB = deltaFromPreviousMB
        self.model = model
        self.computeUnits = computeUnits
        self.metadata = metadata
    }
}

struct MemoryReport: Codable, Equatable {
    let artifactType: String
    let generatedAt: Date
    let primaryMetric: String
    let events: [MemoryEvent]
}

final class MemoryProfiler {
    private(set) var events: [MemoryEvent] = []
    private(set) var peakPhysicalFootprintMB: Double = 0
    private var previousPhysicalFootprintMB: Double?

    var latestEvent: MemoryEvent? {
        events.last
    }

    var compactSummary: String {
        guard let latestEvent else {
            return "Mem: pending"
        }

        return String(
            format: "Mem %.1f MB | peak %.1f | jump %@%.1f | %@",
            latestEvent.physicalFootprintMB,
            latestEvent.peakPhysicalFootprintMB,
            latestEvent.deltaFromPreviousMB >= 0 ? "+" : "",
            latestEvent.deltaFromPreviousMB,
            latestEvent.event
        )
    }

    var diagnosticJSON: String {
        let report = MemoryReport(
            artifactType: "pocketchef_iphone_memory_report",
            generatedAt: Date(),
            primaryMetric: "physical_footprint_mb",
            events: events
        )

        guard
            let data = try? JSONEncoder.memoryReportEncoder.encode(report),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    @discardableResult
    func record(
        _ event: String,
        mode: OptimizationMode,
        model: String,
        computeUnits: String,
        metadata: [String: String] = [:]
    ) -> MemoryEvent? {
        guard let sample = Self.currentSample() else {
            return nil
        }

        let previous = previousPhysicalFootprintMB ?? sample.physicalFootprintMB
        let delta = sample.physicalFootprintMB - previous
        previousPhysicalFootprintMB = sample.physicalFootprintMB
        peakPhysicalFootprintMB = max(peakPhysicalFootprintMB, sample.physicalFootprintMB)

        let memoryEvent = MemoryEvent(
            event: event,
            mode: mode.rawValue,
            sample: sample,
            peakPhysicalFootprintMB: peakPhysicalFootprintMB,
            deltaFromPreviousMB: delta,
            model: model,
            computeUnits: computeUnits,
            metadata: metadata
        )
        events.append(memoryEvent)
        if events.count > 240 {
            events.removeFirst(events.count - 240)
        }
        return memoryEvent
    }

    static func currentSample() -> MemorySample? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    reboundPointer,
                    &count
                )
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return MemorySample(
            physicalFootprintMB: Double(info.phys_footprint) / 1_048_576,
            residentSizeMB: Double(info.resident_size) / 1_048_576
        )
    }
}

private extension JSONEncoder {
    static var memoryReportEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
