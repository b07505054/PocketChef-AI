import CoreML
import Foundation

struct BenchmarkConfig: Identifiable {
    let id: UUID
    let label: String
    let modelName: String
    let computeUnits: MLComputeUnits
    let optimizationMode: OptimizationMode

    static func computeUnitSweep(
        modelName: String,
        optimizationMode: OptimizationMode
    ) -> [BenchmarkConfig] {
        [
            BenchmarkConfig(id: UUID(), label: "CPU",     modelName: modelName, computeUnits: .cpuOnly,            optimizationMode: optimizationMode),
            BenchmarkConfig(id: UUID(), label: "CPU+GPU", modelName: modelName, computeUnits: .cpuAndGPU,          optimizationMode: optimizationMode),
            BenchmarkConfig(id: UUID(), label: "CPU+ANE", modelName: modelName, computeUnits: .cpuAndNeuralEngine, optimizationMode: optimizationMode),
            BenchmarkConfig(id: UUID(), label: "All",     modelName: modelName, computeUnits: .all,                optimizationMode: optimizationMode),
        ]
    }
}

struct BenchmarkSample {
    let totalMs: Double
    let maskDecodeMs: Double
}

struct BenchmarkResult: Identifiable {
    let id: UUID
    let config: BenchmarkConfig
    let modelLoadMs: Double
    let warmupRuns: Int
    let measuredRuns: Int
    let samples: [BenchmarkSample]
    let p50TotalMs: Double
    let p95TotalMs: Double
    let thermalState: String
    let lowPowerMode: Bool
    let capturedAt: Date

    static func make(
        config: BenchmarkConfig,
        modelLoadMs: Double,
        warmupRuns: Int,
        measuredRuns: Int,
        samples: [BenchmarkSample],
        thermalState: String,
        lowPowerMode: Bool
    ) -> BenchmarkResult {
        let totals = samples.map(\.totalMs)
        return BenchmarkResult(
            id: UUID(),
            config: config,
            modelLoadMs: modelLoadMs,
            warmupRuns: warmupRuns,
            measuredRuns: measuredRuns,
            samples: samples,
            p50TotalMs: benchPercentile(totals, 50),
            p95TotalMs: benchPercentile(totals, 95),
            thermalState: thermalState,
            lowPowerMode: lowPowerMode,
            capturedAt: Date()
        )
    }
}

func benchmarkExportJSON(
    results: [BenchmarkResult],
    warmupRuns: Int,
    measuredRuns: Int
) -> String {
    let fastest = results.min(by: { $0.p50TotalMs < $1.p50TotalMs })?.config.label ?? "unknown"

    let rows: [[String: Any]] = results.map { r in
        let sampleDicts: [[String: Double]] = r.samples.map { s in
            ["total_ms": (s.totalMs * 10).rounded() / 10,
             "mask_decode_ms": (s.maskDecodeMs * 10).rounded() / 10]
        }
        return [
            "config_label":      r.config.label,
            "model":             r.config.modelName,
            "compute_unit":      r.config.computeUnits.jsonLabel,
            "optimization_mode": r.config.optimizationMode.rawValue,
            "model_load_ms":     r.modelLoadMs.rounded(),
            "p50_total_ms":      r.p50TotalMs.rounded(),
            "p95_total_ms":      r.p95TotalMs.rounded(),
            "thermal_state":     r.thermalState,
            "low_power_mode":    r.lowPowerMode,
            "samples":           sampleDicts,
        ]
    }

    let root: [String: Any] = [
        "artifact_type":           "pocketchef_coreml_device_benchmark",
        "schema_version":          "1.0",
        "truth_boundary":          "measured_on_device_single_session_not_production_benchmark",
        "captured_at":             ISO8601DateFormatter().string(from: Date()),
        "warmup_runs":             warmupRuns,
        "measured_runs":           measuredRuns,
        "fastest_by_p50_total_ms": fastest,
        "results":                 rows,
    ]

    guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
          let string = String(data: data, encoding: .utf8) else {
        return "{}"
    }
    return string
}

private func benchPercentile(_ values: [Double], _ p: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let rank = p / 100.0 * Double(sorted.count - 1)
    return sorted[Int(rank.rounded())]
}

extension MLComputeUnits {
    var jsonLabel: String {
        switch self {
        case .cpuOnly:            return "cpuOnly"
        case .cpuAndGPU:          return "cpuAndGPU"
        case .cpuAndNeuralEngine: return "cpuAndNeuralEngine"
        case .all:                return "all"
        @unknown default:         return "unknown"
        }
    }
}
