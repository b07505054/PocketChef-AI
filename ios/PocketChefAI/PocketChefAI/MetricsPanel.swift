import SwiftUI

struct MetricsPanel: View {
    @ObservedObject var viewModel: CameraViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                metric("FPS", value: String(format: "%.1f", viewModel.metrics.fps))
                metric("p50", value: String(format: "%.1f", viewModel.metrics.p50LatencyMs))
                metric("p95", value: String(format: "%.1f ms", viewModel.metrics.p95LatencyMs))
            }

            HStack(spacing: 7) {
                ForEach(OptimizationMode.allCases) { mode in
                    Button {
                        viewModel.optimizationMode = mode
                    } label: {
                        Text(mode.shortName)
                            .font(.caption.weight(.bold))
                            .frame(minWidth: 42, minHeight: 32)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(viewModel.optimizationMode == mode ? .black : .white)
                    .background(viewModel.optimizationMode == mode ? .green : .white.opacity(0.17))
                    .clipShape(Capsule())
                }
            }

            Text("\(viewModel.optimizationMode.rawValue) | \(viewModel.activeBackend)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)

            Text("Model: \(viewModel.activeModel)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(2)

            Text(viewModel.activePolicySummary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(3)

            Text(viewModel.selectedMaskSummary)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.green.opacity(0.9))
                .lineLimit(1)

            Text(viewModel.memoryDebugSummary)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange.opacity(0.94))
                .lineLimit(2)

            Text(viewModel.memoryDetailSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.orange.opacity(0.74))
                .lineLimit(2)

            Text(viewModel.geometryDebugSummary)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.cyan.opacity(0.78))
                .lineLimit(2)

            Text(viewModel.bundleInventory)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(3)
        }
        .padding(13)
        .background(.black.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(minWidth: 66, alignment: .leading)
    }
}
