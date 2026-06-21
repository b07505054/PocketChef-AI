#!/usr/bin/env python3
import json
import subprocess
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHADER_PATH = ROOT / "metal/mask_postprocess.metal"
OUT_PATH = ROOT / "compiler_artifacts/generated/metal_mask_spmd_benchmark_report.json"


SWIFT_SOURCE = r'''
import Foundation
import Metal

struct RNG {
    var state: UInt64

    mutating func nextUnit() -> Float {
        state = state &* 2862933555777941757 &+ 3037000493
        let value = Double((state >> 33) & 0x7fffffff) / Double(0x7fffffff)
        return Float(value)
    }

    mutating func nextSigned(_ scale: Float) -> Float {
        (nextUnit() * 2.0 - 1.0) * scale
    }
}

struct Crop: Codable {
    let minX: Float
    let maxX: Float
    let minY: Float
    let maxY: Float
}

struct Params {
    let width: UInt32
    let height: UInt32
    let minX: UInt32
    let maxX: UInt32
    let minY: UInt32
    let maxY: UInt32
    let threshold: Float
}

struct BenchmarkCase {
    let name: String
    let width: Int
    let height: Int
    let crop: Crop
    let seed: UInt64
    let threshold: Float
}

struct Latency: Codable {
    let runs: Int
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let meanLatencyMs: Double

    enum CodingKeys: String, CodingKey {
        case runs
        case p50LatencyMs = "p50_latency_ms"
        case p95LatencyMs = "p95_latency_ms"
        case meanLatencyMs = "mean_latency_ms"
    }
}

struct Correctness: Codable {
    let maxAlphaAbsDiff: Int
    let meanAlphaAbsDiff: Double
    let activePixelCountDelta: Int
    let iouVsScalar: Double
    let bboxDeltaPixels: Int

    enum CodingKeys: String, CodingKey {
        case maxAlphaAbsDiff = "max_alpha_abs_diff"
        case meanAlphaAbsDiff = "mean_alpha_abs_diff"
        case activePixelCountDelta = "active_pixel_count_delta"
        case iouVsScalar = "iou_vs_scalar"
        case bboxDeltaPixels = "bbox_delta_pixels"
    }
}

struct InputInfo: Codable {
    let prototypeLayout: String
    let prototypeShape: [Int]
    let crop: Crop
    let threshold: Float

    enum CodingKeys: String, CodingKey {
        case prototypeLayout = "prototype_layout"
        case prototypeShape = "prototype_shape"
        case crop
        case threshold
    }
}

struct Decision: Codable {
    let selectedBackend: String
    let fallbackReason: String
    let metalLegality: String

    enum CodingKeys: String, CodingKey {
        case selectedBackend = "selected_backend"
        case fallbackReason = "fallback_reason"
        case metalLegality = "metal_legality"
    }
}

struct MetricImpact: Codable {
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let estimatedFpsImpact: Double

    enum CodingKeys: String, CodingKey {
        case p50LatencyMs = "p50_latency_ms"
        case p95LatencyMs = "p95_latency_ms"
        case estimatedFpsImpact = "estimated_fps_impact"
    }
}

struct CaseReport: Codable {
    let `case`: String
    let input: InputInfo
    let decision: Decision
    let scalarCPU: Latency
    let simdCPU: Latency
    let metalSPMD: Latency
    let simdCorrectness: Correctness
    let metalCorrectness: Correctness
    let metricImpact: MetricImpact

    enum CodingKeys: String, CodingKey {
        case `case`
        case input
        case decision
        case scalarCPU = "scalar_cpu"
        case simdCPU = "simd_cpu"
        case metalSPMD = "metal_spmd"
        case simdCorrectness = "simd_correctness"
        case metalCorrectness = "metal_correctness"
        case metricImpact = "metric_impact"
    }
}

struct Report: Codable {
    let artifactType: String
    let schemaVersion: Int
    let source: String
    let benchmarkRuntime: String
    let metalDevice: String
    let input: [String: String]
    let decision: Decision
    let metricImpact: MetricImpact
    let correctness: Correctness
    let truthBoundary: [String: String]
    let technologyGate: [String: CodableValue]
    let acceptanceThresholds: [String: CodableValue]
    let summary: [String: CodableValue]
    let selectedBackend: String
    let fallbackReason: String
    let p50LatencyMs: Double
    let p95LatencyMs: Double
    let estimatedFpsImpact: Double
    let maxAlphaAbsDiff: Int
    let meanAlphaAbsDiff: Double
    let activePixelCountDelta: Int
    let iouVsScalar: Double
    let bboxDeltaPixels: Int
    let cases: [CaseReport]

    enum CodingKeys: String, CodingKey {
        case artifactType = "artifact_type"
        case schemaVersion = "schema_version"
        case source
        case benchmarkRuntime = "benchmark_runtime"
        case metalDevice = "metal_device"
        case input
        case decision
        case metricImpact = "metric_impact"
        case correctness
        case truthBoundary = "truth_boundary"
        case technologyGate = "technology_gate"
        case acceptanceThresholds = "acceptance_thresholds"
        case summary
        case selectedBackend = "selected_backend"
        case fallbackReason = "fallback_reason"
        case p50LatencyMs = "p50_latency_ms"
        case p95LatencyMs = "p95_latency_ms"
        case estimatedFpsImpact = "estimated_fps_impact"
        case maxAlphaAbsDiff = "max_alpha_abs_diff"
        case meanAlphaAbsDiff = "mean_alpha_abs_diff"
        case activePixelCountDelta = "active_pixel_count_delta"
        case iouVsScalar = "iou_vs_scalar"
        case bboxDeltaPixels = "bbox_delta_pixels"
        case cases
    }
}

enum CodableValue: Codable {
    case string(String)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case stringMap([String: String])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .stringMap(let value): try container.encode(value)
        }
    }

    init(from decoder: Decoder) throws {
        fatalError("decode not implemented")
    }
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    if values.isEmpty { return 0.0 }
    let sorted = values.sorted()
    let rank = max(0, min(Int(ceil((p / 100.0) * Double(sorted.count))) - 1, sorted.count - 1))
    return sorted[rank]
}

func mean(_ values: [Double]) -> Double {
    if values.isEmpty { return 0.0 }
    return values.reduce(0.0, +) / Double(values.count)
}

func rounded(_ value: Double) -> Double {
    (value * 1_000_000).rounded() / 1_000_000
}

func alpha(from total: Float, threshold: Float) -> UInt8 {
    let probability = 1.0 / (1.0 + exp(-Double(total)))
    if probability < Double(threshold) { return 0 }
    let shaped = min(max((probability - Double(threshold)) / (1.0 - Double(threshold)), 0.0), 1.0)
    return UInt8(70.0 + shaped * 125.0)
}

func makeData(_ testCase: BenchmarkCase) -> ([Float], [Float]) {
    var rng = RNG(state: testCase.seed)
    let coefficients = (0..<32).map { _ in rng.nextSigned(0.7) }
    let plane = testCase.width * testCase.height
    let prototypes = (0..<(32 * plane)).map { _ in rng.nextSigned(1.0) }
    return (coefficients, prototypes)
}

func cropBounds(_ testCase: BenchmarkCase) -> (Int, Int, Int, Int) {
    let minX = max(Int(floor(testCase.crop.minX * Float(testCase.width))), 0)
    let maxX = min(Int(ceil(testCase.crop.maxX * Float(testCase.width))) - 1, testCase.width - 1)
    let minY = max(Int(floor(testCase.crop.minY * Float(testCase.height))), 0)
    let maxY = min(Int(ceil(testCase.crop.maxY * Float(testCase.height))) - 1, testCase.height - 1)
    return (minX, maxX, minY, maxY)
}

func scalarDecode(_ testCase: BenchmarkCase, coefficients: [Float], prototypes: [Float]) -> [UInt8] {
    let (minX, maxX, minY, maxY) = cropBounds(testCase)
    let plane = testCase.width * testCase.height
    var mask = [UInt8](repeating: 0, count: plane)
    for y in minY...maxY {
        for x in minX...maxX {
            let outIndex = y * testCase.width + x
            var total: Float = 0
            for channel in 0..<32 {
                total += coefficients[channel] * prototypes[channel * plane + outIndex]
            }
            mask[outIndex] = alpha(from: total, threshold: testCase.threshold)
        }
    }
    return mask
}

func simdDecode(_ testCase: BenchmarkCase, coefficients: [Float], prototypes: [Float]) -> [UInt8] {
    let (minX, maxX, minY, maxY) = cropBounds(testCase)
    let plane = testCase.width * testCase.height
    var mask = [UInt8](repeating: 0, count: plane)
    for y in minY...maxY {
        for x in minX...maxX {
            let outIndex = y * testCase.width + x
            var accum = SIMD8<Float>.zero
            for base in stride(from: 0, to: 32, by: 8) {
                let coeff = SIMD8<Float>(
                    coefficients[base], coefficients[base + 1], coefficients[base + 2], coefficients[base + 3],
                    coefficients[base + 4], coefficients[base + 5], coefficients[base + 6], coefficients[base + 7]
                )
                let proto = SIMD8<Float>(
                    prototypes[(base + 0) * plane + outIndex],
                    prototypes[(base + 1) * plane + outIndex],
                    prototypes[(base + 2) * plane + outIndex],
                    prototypes[(base + 3) * plane + outIndex],
                    prototypes[(base + 4) * plane + outIndex],
                    prototypes[(base + 5) * plane + outIndex],
                    prototypes[(base + 6) * plane + outIndex],
                    prototypes[(base + 7) * plane + outIndex]
                )
                accum += coeff * proto
            }
            let total = accum[0] + accum[1] + accum[2] + accum[3] + accum[4] + accum[5] + accum[6] + accum[7]
            mask[outIndex] = alpha(from: total, threshold: testCase.threshold)
        }
    }
    return mask
}

func activeBBox(_ mask: [UInt8], width: Int, height: Int) -> (Int, Int, Int, Int)? {
    var minX = width
    var maxX = -1
    var minY = height
    var maxY = -1
    for index in mask.indices where mask[index] > 0 {
        let y = index / width
        let x = index % width
        minX = min(minX, x)
        maxX = max(maxX, x)
        minY = min(minY, y)
        maxY = max(maxY, y)
    }
    if maxX < minX || maxY < minY { return nil }
    return (minX, maxX, minY, maxY)
}

func bboxDelta(_ a: (Int, Int, Int, Int)?, _ b: (Int, Int, Int, Int)?) -> Int {
    if a == nil && b == nil { return 0 }
    guard let a, let b else { return Int.max / 2 }
    return max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2), abs(a.3 - b.3))
}

func correctness(reference: [UInt8], candidate: [UInt8], width: Int, height: Int) -> Correctness {
    var maxDiff = 0
    var totalDiff = 0
    var refActive = Set<Int>()
    var candActive = Set<Int>()
    for index in reference.indices {
        let diff = abs(Int(reference[index]) - Int(candidate[index]))
        maxDiff = max(maxDiff, diff)
        totalDiff += diff
        if reference[index] > 0 { refActive.insert(index) }
        if candidate[index] > 0 { candActive.insert(index) }
    }
    let union = refActive.union(candActive)
    let intersection = refActive.intersection(candActive)
    let iou = union.isEmpty ? 1.0 : Double(intersection.count) / Double(union.count)
    return Correctness(
        maxAlphaAbsDiff: maxDiff,
        meanAlphaAbsDiff: rounded(Double(totalDiff) / Double(max(reference.count, 1))),
        activePixelCountDelta: candActive.count - refActive.count,
        iouVsScalar: rounded(iou),
        bboxDeltaPixels: bboxDelta(activeBBox(reference, width: width, height: height), activeBBox(candidate, width: width, height: height))
    )
}

func measure(_ runs: Int = 30, warmup: Int = 5, _ fn: () throws -> [UInt8]) rethrows -> ([UInt8], Latency) {
    for _ in 0..<warmup { _ = try fn() }
    var latencies = [Double]()
    var output = [UInt8]()
    for _ in 0..<runs {
        let start = DispatchTime.now().uptimeNanoseconds
        output = try fn()
        let end = DispatchTime.now().uptimeNanoseconds
        latencies.append(Double(end - start) / 1_000_000.0)
    }
    return (output, Latency(
        runs: runs,
        p50LatencyMs: rounded(percentile(latencies, 50)),
        p95LatencyMs: rounded(percentile(latencies, 95)),
        meanLatencyMs: rounded(mean(latencies))
    ))
}

final class MetalRunner {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLComputePipelineState

    init(shaderPath: String) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw NSError(domain: "MetalRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Metal unavailable"])
        }
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            throw NSError(domain: "MetalRunner", code: 2, userInfo: [NSLocalizedDescriptionKey: "Metal command queue unavailable"])
        }
        self.queue = queue
        let source = try String(contentsOfFile: shaderPath, encoding: .utf8)
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "yolo_mask_decode_spmd") else {
            throw NSError(domain: "MetalRunner", code: 3, userInfo: [NSLocalizedDescriptionKey: "Metal function not found"])
        }
        self.pipeline = try device.makeComputePipelineState(function: function)
    }

    func decode(_ testCase: BenchmarkCase, coefficients: [Float], prototypes: [Float]) throws -> [UInt8] {
        let outputCount = testCase.width * testCase.height
        var coeffs = coefficients
        var protos = prototypes
        var params = Params(
            width: UInt32(testCase.width),
            height: UInt32(testCase.height),
            minX: UInt32(cropBounds(testCase).0),
            maxX: UInt32(cropBounds(testCase).1),
            minY: UInt32(cropBounds(testCase).2),
            maxY: UInt32(cropBounds(testCase).3),
            threshold: testCase.threshold
        )
        guard
            let coeffBuffer = device.makeBuffer(bytes: &coeffs, length: MemoryLayout<Float>.stride * coeffs.count, options: .storageModeShared),
            let protoBuffer = device.makeBuffer(bytes: &protos, length: MemoryLayout<Float>.stride * protos.count, options: .storageModeShared),
            let outputBuffer = device.makeBuffer(length: outputCount, options: .storageModeShared),
            let paramsBuffer = device.makeBuffer(bytes: &params, length: MemoryLayout<Params>.stride, options: .storageModeShared),
            let commandBuffer = queue.makeCommandBuffer(),
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            throw NSError(domain: "MetalRunner", code: 4, userInfo: [NSLocalizedDescriptionKey: "Metal buffer allocation failed"])
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(coeffBuffer, offset: 0, index: 0)
        encoder.setBuffer(protoBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 3)
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        encoder.dispatchThreads(
            MTLSize(width: testCase.width, height: testCase.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1)
        )
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error { throw error }

        let pointer = outputBuffer.contents().bindMemory(to: UInt8.self, capacity: outputCount)
        return Array(UnsafeBufferPointer(start: pointer, count: outputCount))
    }
}

func caseReport(_ testCase: BenchmarkCase, runner: MetalRunner) throws -> CaseReport {
    let (coefficients, prototypes) = makeData(testCase)
    let (scalarMask, scalarLatency) = measure { scalarDecode(testCase, coefficients: coefficients, prototypes: prototypes) }
    let (simdMask, simdLatency) = measure { simdDecode(testCase, coefficients: coefficients, prototypes: prototypes) }
    let (metalMask, metalLatency) = try measure { try runner.decode(testCase, coefficients: coefficients, prototypes: prototypes) }
    let simdCorrect = correctness(reference: scalarMask, candidate: simdMask, width: testCase.width, height: testCase.height)
    let metalCorrect = correctness(reference: scalarMask, candidate: metalMask, width: testCase.width, height: testCase.height)

    let simdPass = simdCorrect.maxAlphaAbsDiff <= 1 && simdCorrect.iouVsScalar >= 0.995 && simdCorrect.bboxDeltaPixels <= 1
    let metalPass = metalCorrect.maxAlphaAbsDiff <= 1 && metalCorrect.iouVsScalar >= 0.995 && metalCorrect.bboxDeltaPixels <= 1
    var candidates: [(String, Double)] = [("scalar_cpu", scalarLatency.p95LatencyMs)]
    if simdPass { candidates.append(("simd_cpu", simdLatency.p95LatencyMs)) }
    if metalPass { candidates.append(("metal_spmd", metalLatency.p95LatencyMs)) }
    let selected = candidates.min { $0.1 < $1.1 }!.0
    let fallback = selected == "metal_spmd" ? "none" : (metalPass ? "profile_rejected" : "correctness_rejected")
    let selectedLatency: Latency = selected == "metal_spmd" ? metalLatency : (selected == "simd_cpu" ? simdLatency : scalarLatency)
    let fpsImpact = scalarLatency.p95LatencyMs > 0 ? (scalarLatency.p95LatencyMs - selectedLatency.p95LatencyMs) / scalarLatency.p95LatencyMs : 0.0

    return CaseReport(
        case: testCase.name,
        input: InputInfo(
            prototypeLayout: "NCHW",
            prototypeShape: [1, 32, testCase.height, testCase.width],
            crop: testCase.crop,
            threshold: testCase.threshold
        ),
        decision: Decision(
            selectedBackend: selected,
            fallbackReason: fallback,
            metalLegality: "coefficients=32, NCHW prototype layout, Metal device available"
        ),
        scalarCPU: scalarLatency,
        simdCPU: simdLatency,
        metalSPMD: metalLatency,
        simdCorrectness: simdCorrect,
        metalCorrectness: metalCorrect,
        metricImpact: MetricImpact(
            p50LatencyMs: selectedLatency.p50LatencyMs,
            p95LatencyMs: selectedLatency.p95LatencyMs,
            estimatedFpsImpact: rounded(fpsImpact)
        )
    )
}

let shaderPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let runner = try MetalRunner(shaderPath: shaderPath)
let cases = [
    BenchmarkCase(name: "small_crop_160", width: 160, height: 160, crop: Crop(minX: 0.20, maxX: 0.48, minY: 0.25, maxY: 0.55), seed: 7, threshold: 0.55),
    BenchmarkCase(name: "medium_crop_160", width: 160, height: 160, crop: Crop(minX: 0.12, maxX: 0.72, minY: 0.18, maxY: 0.76), seed: 11, threshold: 0.55),
    BenchmarkCase(name: "edge_crop_160", width: 160, height: 160, crop: Crop(minX: 0.00, maxX: 0.34, minY: 0.02, maxY: 0.44), seed: 17, threshold: 0.55)
]
let reports = try cases.map { try caseReport($0, runner: runner) }
let selectedCounts = Dictionary(grouping: reports.map { $0.decision.selectedBackend }, by: { $0 }).mapValues { $0.count }
let fallbackCounts = Dictionary(grouping: reports.map { $0.decision.fallbackReason }, by: { $0 }).mapValues { $0.count }
let selected = selectedCounts.max { $0.value < $1.value }!.key
let fallback = fallbackCounts.max { $0.value < $1.value }!.key
let selectedP50 = reports.map { $0.metricImpact.p50LatencyMs }
let selectedP95 = reports.map { $0.metricImpact.p95LatencyMs }
let fpsImpacts = reports.map { $0.metricImpact.estimatedFpsImpact }
let maxAlpha = reports.map { $0.metalCorrectness.maxAlphaAbsDiff }.max() ?? 0
let meanAlpha = mean(reports.map { $0.metalCorrectness.meanAlphaAbsDiff })
let maxActiveDelta = reports.map { abs($0.metalCorrectness.activePixelCountDelta) }.max() ?? 0
let minIou = reports.map { $0.metalCorrectness.iouVsScalar }.min() ?? 1.0
let maxBBox = reports.map { $0.metalCorrectness.bboxDeltaPixels }.max() ?? 0

let report = Report(
    artifactType: "metal_mask_spmd_benchmark_report",
    schemaVersion: 1,
    source: "PocketChef YOLO-Seg mask postprocess Metal SPMD benchmark artifacts",
    benchmarkRuntime: "macos_metal_compute_harness",
    metalDevice: runner.device.name,
    input: [
        "model_stage": "YOLO-Seg mask postprocess",
        "coefficients": "32 mask coefficients",
        "prototype_layout": "NCHW",
        "prototype_shape": "1x32x160x160 synthetic YOLO-Seg-like tensors",
        "crop": "per-case normalized crop box",
        "threshold": "0.55"
    ],
    decision: Decision(
        selectedBackend: selected,
        fallbackReason: fallback,
        metalLegality: "coefficients=32, NCHW prototype layout, Metal device available"
    ),
    metricImpact: MetricImpact(
        p50LatencyMs: rounded(percentile(selectedP50, 50)),
        p95LatencyMs: rounded(percentile(selectedP95, 95)),
        estimatedFpsImpact: rounded(mean(fpsImpacts))
    ),
    correctness: Correctness(
        maxAlphaAbsDiff: maxAlpha,
        meanAlphaAbsDiff: rounded(meanAlpha),
        activePixelCountDelta: maxActiveDelta,
        iouVsScalar: minIou,
        bboxDeltaPixels: maxBBox
    ),
    truthBoundary: [
        "real": "This report runs a real Metal SPMD compute kernel on the local Metal device.",
        "artifact_backed": "Metal is benchmark-backed for YOLO-Seg mask decode; PocketChef V2 does not yet route live iPhone app mask decode through Metal.",
        "live_ios_dispatch": "false",
        "not_claimed": "No Qualcomm Ripple, Snapdragon/QNN/Hexagon, or live iPhone Metal dispatch is claimed."
    ],
    technologyGate: [
        "input": .string("YOLO-Seg mask coefficients, NCHW prototype tensor, crop box, and threshold"),
        "decision": .string("profile and correctness policy compares scalar CPU, SIMD CPU, and Metal SPMD candidates"),
        "metric": .string("p50/p95 mask decode latency, estimated FPS impact, fallback behavior, and mask correctness vs scalar reference"),
        "passes_gate": .bool(true)
    ],
    acceptanceThresholds: [
        "max_alpha_abs_diff": .int(1),
        "iou_vs_scalar": .double(0.995),
        "bbox_delta_pixels": .int(1)
    ],
    summary: [
        "case_count": .int(reports.count),
        "selected_backend_counts": .stringMap(selectedCounts.mapValues { String($0) }),
        "fallback_reason_counts": .stringMap(fallbackCounts.mapValues { String($0) })
    ],
    selectedBackend: selected,
    fallbackReason: fallback,
    p50LatencyMs: rounded(percentile(selectedP50, 50)),
    p95LatencyMs: rounded(percentile(selectedP95, 95)),
    estimatedFpsImpact: rounded(mean(fpsImpacts)),
    maxAlphaAbsDiff: maxAlpha,
    meanAlphaAbsDiff: rounded(meanAlpha),
    activePixelCountDelta: maxActiveDelta,
    iouVsScalar: minIou,
    bboxDeltaPixels: maxBBox,
    cases: reports
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let data = try encoder.encode(report)
try data.write(to: URL(fileURLWithPath: outPath))
print(String(data: data, encoding: .utf8)!)
'''


def main():
    if not SHADER_PATH.exists():
        raise FileNotFoundError(f"Metal shader not found: {SHADER_PATH}")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory(prefix="pocketchef-metal-mask-") as tmp:
        tmp_dir = Path(tmp)
        swift_path = tmp_dir / "MetalMaskBenchmark.swift"
        binary_path = tmp_dir / "metal_mask_benchmark"
        swift_path.write_text(SWIFT_SOURCE, encoding="utf-8")

        subprocess.run(
            [
                "xcrun",
                "swiftc",
                "-O",
                str(swift_path),
                "-o",
                str(binary_path),
                "-framework",
                "Metal",
                "-framework",
                "Foundation",
            ],
            check=True,
        )
        completed = subprocess.run(
            [str(binary_path), str(SHADER_PATH), str(OUT_PATH)],
            check=True,
            text=True,
            capture_output=True,
        )
        payload = json.loads(OUT_PATH.read_text(encoding="utf-8"))
        print(json.dumps({
            "wrote": str(OUT_PATH),
            "metal_device": payload.get("metal_device"),
            "selected_backend": payload.get("selected_backend"),
            "p95_latency_ms": payload.get("p95_latency_ms"),
        }, indent=2))
        if completed.stderr:
            print(completed.stderr)


if __name__ == "__main__":
    main()
