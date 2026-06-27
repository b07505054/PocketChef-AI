import SwiftUI

// RuntimeTracePlaybackCard displays a baseline vs. compiler-guided runtime comparison
// derived from the bundled runtime_profile_trace.json.
//
// It reads from RuntimeTracePlaybackDomain (not raw events) and drives the
// ComparisonPlaybackEngine only through the domain's seekPreview() method.
//
// Truth boundary is always visible: this is offline simulation, not iPhone execution.

struct RuntimeTracePlaybackCard: View {
    @ObservedObject var traceDomain: RuntimeTracePlaybackDomain
    @State private var previewProgress: Double = 0.5

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader

            switch traceDomain.status {
            case .notStarted:
                emptyStateRow("Runtime trace not loaded.")
            case .loading:
                HStack(spacing: 10) {
                    ProgressView().tint(.green)
                    Text("Loading runtime trace…")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .padding(.vertical, 4)
            case .failed(let msg):
                Text("Failed: \(msg)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            case .loaded:
                if let trace = traceDomain.trace {
                    loadedBody(trace: trace)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack(spacing: 8) {
            Text("Runtime Trace Replay")
                .font(.title3.weight(.black))
                .foregroundStyle(.white)
            Spacer()
            Image(systemName: "waveform.path")
                .font(.headline.weight(.bold))
                .foregroundStyle(.green)
        }
    }

    // MARK: - Loaded content

    @ViewBuilder
    private func loadedBody(trace: RuntimeProfileTraceSummary) -> some View {
        metaRows(trace: trace)

        Divider().background(.white.opacity(0.12))

        // Warning / artifact provenance badge
        if trace.doNotUseForDemo {
            warningBanner("Development Fixture — compiler pipeline is bypassed.")
        } else if trace.isCompilerArtifact {
            artifactBadge("Compiler artifact linked")
        }

        // Permanent truth boundary notice
        Text("Offline runtime trace replay. Live iPhone metrics are separate.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.48))
            .fixedSize(horizontal: false, vertical: true)

        Divider().background(.white.opacity(0.12))

        // Comparison headline
        Text(trace.comparisonHeadline)
            .font(.headline.weight(.black))
            .foregroundStyle(.green)
            .fixedSize(horizontal: false, vertical: true)

        summaryTable(trace: trace)

        Divider().background(.white.opacity(0.12))

        // Engine-derived state at current scrubber position
        if let state = traceDomain.comparisonState {
            playbackSection(state: state)
        }

        scrubber
    }

    // MARK: - Meta rows

    private func metaRows(trace: RuntimeProfileTraceSummary) -> some View {
        VStack(spacing: 0) {
            infoRow("Model", trace.modelName)
            infoRow("Target", trace.targetProfileId)
            infoRow("Plan source", trace.compilerPlanSource)
        }
    }

    // MARK: - Summary comparison table

    private func summaryTable(trace: RuntimeProfileTraceSummary) -> some View {
        let bl = trace.baselineSummary
        let op = trace.optimizedSummary
        return VStack(spacing: 8) {
            comparisonColumnHeader
            comparisonRow(
                label: "p95 latency",
                baseline: String(format: "%.0f ms", bl.p95LatencyMs),
                optimized: String(format: "%.0f ms", op.p95LatencyMs),
                barRatio: safeRatio(numerator: op.p95LatencyMs, denominator: bl.p95LatencyMs)
            )
            comparisonRow(
                label: "Peak mem",
                baseline: String(format: "%.0f MB", bl.peakMemoryMb),
                optimized: String(format: "%.0f MB", op.peakMemoryMb),
                barRatio: safeRatio(numerator: op.peakMemoryMb, denominator: bl.peakMemoryMb)
            )
            comparisonRow(
                label: "Duration",
                baseline: String(format: "%.0f ms", trace.baselineVariant.totalDurationMs),
                optimized: String(format: "%.0f ms", trace.optimizedVariant.totalDurationMs),
                barRatio: safeRatio(
                    numerator:   trace.optimizedVariant.totalDurationMs,
                    denominator: trace.baselineVariant.totalDurationMs
                )
            )
        }
    }

    private var comparisonColumnHeader: some View {
        HStack {
            Text("")
                .frame(width: 72, alignment: .leading)
            Text("Baseline")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Compiler")
                .font(.caption.weight(.black))
                .foregroundStyle(.green)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func comparisonRow(
        label: String,
        baseline: String,
        optimized: String,
        barRatio: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 72, alignment: .leading)
                Text(baseline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(optimized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Relative bar: white = baseline (full width), green = compiler-guided (scaled)
            GeometryReader { geo in
                let w = geo.size.width
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.20))
                        .frame(width: w, height: 5)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green.opacity(0.70))
                        .frame(width: max(w * barRatio, 8), height: 5)
                }
            }
            .frame(height: 14)
        }
    }

    private func safeRatio(numerator: Double, denominator: Double) -> Double {
        guard denominator > 0 else { return 1.0 }
        return min(numerator / denominator, 1.0)
    }

    // MARK: - Playback state at scrubber position

    @ViewBuilder
    private func playbackSection(state: ComparisonPlaybackState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("At preview timestamp")
                .font(.caption.weight(.black))
                .foregroundStyle(.white.opacity(0.54))

            HStack(alignment: .top, spacing: 0) {
                playbackColumn("Baseline", state: state.baseline, tint: .white.opacity(0.75))
                Divider()
                    .frame(width: 1)
                    .background(.white.opacity(0.12))
                    .padding(.horizontal, 8)
                playbackColumn("Compiler", state: state.optimized, tint: .green)
            }
        }
        .padding(10)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func playbackColumn(
        _ label: String,
        state: RuntimePlaybackState,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption.weight(.black))
                .foregroundStyle(tint)
            playbackMetric("Backend",  state.currentBackend.isEmpty  ? "—" : state.currentBackend)
            playbackMetric("KV",       state.currentKVLayout.isEmpty ? "—" : state.currentKVLayout)
            playbackMetric("Queue",    "\(state.currentQueueDepth)")
            playbackMetric("Memory",   String(format: "%.0f MB", state.currentMemoryMB))
            playbackMetric("Events",   "\(state.activeEvents.count) active")
            if let ttft = state.currentTTFT {
                playbackMetric("TTFT", String(format: "%.0f ms", ttft))
            }
            if let tpot = state.currentTPOT {
                playbackMetric("TPOT", String(format: "%.0f ms", tpot))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func playbackMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .monospacedDigit()
        }
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trace preview")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.54))
                Spacer()
                Text("\(Int(previewProgress * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            Slider(value: $previewProgress, in: 0...1)
                .tint(.green)
                .onChange(of: previewProgress) { _, newValue in
                    traceDomain.seekPreview(to: newValue)
                }
        }
    }

    // MARK: - Shared helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 16)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
    }

    private func warningBanner(_ message: String) -> some View {
        Text(message)
            .font(.callout.weight(.bold))
            .foregroundStyle(.orange)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.orange.opacity(0.32), lineWidth: 1)
            )
    }

    private func artifactBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.black))
            .foregroundStyle(.green)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.green.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.green.opacity(0.32), lineWidth: 1))
    }

    private func emptyStateRow(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
