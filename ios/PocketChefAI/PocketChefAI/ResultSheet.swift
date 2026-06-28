import SwiftUI
import UIKit

struct ResultSheet: View {
    @ObservedObject var viewModel: CameraViewModel
    var traceDomain: RuntimeTracePlaybackDomain? = nil
    var servingPlan: ServingExecutionPlanSummary? = nil
    var onReturnToCamera: () -> Void = {}
    @AppStorage("ollamaHost") private var ollamaHost = "http://127.0.0.1:11434"
    @AppStorage("ollamaModel") private var ollamaModel = "qwen2.5:3b-instruct"
    @State private var llmQuestion = ""
    @State private var llmAnswer = ""
    @State private var llmMetrics: LLMMetrics?
    @State private var llmError: String?
    @State private var isAskingLLM = false
    @State private var llmMode: LLMOptimizationMode = .baseline
    @FocusState private var focusedField: FocusedField?

    private var recipe: RecipePlan { viewModel.currentRecipe }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    heroCard
                    visualIntelligenceCard
                    nutritionCard
                    ingredientsCard
                    recipeStepsCard
                    shoppingCard
                    benchmarkCard
                    if let plan = servingPlan {
                        compilerPlanCard(plan: plan)
                    }
                    if let td = traceDomain {
                        RuntimeTracePlaybackCard(traceDomain: td)
                    }
                }
                .padding(16)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(red: 0.07, green: 0.08, blue: 0.075))
            .navigationTitle("PocketChef Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                    .font(.callout.weight(.bold))
                }
            }
        }
    }

    private enum FocusedField {
        case question
        case host
        case model
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.title)
                        .font(.largeTitle.weight(.black))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    Text(recipe.subtitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }

                Spacer()

                Image(systemName: recipe.ingredients.isEmpty ? "camera.viewfinder" : "fork.knife.circle.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.green)
            }

            Text(recipe.nutritionNote)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            if !recipe.dietTags.isEmpty {
                tagRow(recipe.dietTags, tint: .green)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.16, blue: 0.13),
                    Color(red: 0.09, green: 0.10, blue: 0.10)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(cardBorder)
    }

    private var visualIntelligenceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cardTitle("Visual Intelligence")
                Spacer()
                Image(systemName: "sparkles")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.green)
            }

            Text(recipe.sceneSummary)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Ask")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.green)
                Text("What can I cook from this?")
                    .font(.headline.weight(.black))
                    .foregroundStyle(.white)
                Text(recipe.visualAnswer)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !recipe.missingItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Helpful additions")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white.opacity(0.55))
                    tagRow(recipe.missingItems, tint: .cyan)
                }
            }

            llmAskPanel
        }
        .cardStyle()
    }

    private var llmAskPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Local LLM")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.green)
                Spacer()
                Text(llmMetrics?.model ?? ollamaModel)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.52))
                    .lineLimit(1)
            }

            llmModePicker

            Text(llmMode.decisionSummary)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Ask about this food, recipe, nutrition, or substitutions...", text: $llmQuestion, axis: .vertical)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .question)
                    .submitLabel(.return)
                    .padding(12)
                    .background(.black.opacity(0.24))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Ollama Host", text: $ollamaHost)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .host)
                            .submitLabel(.done)
                            .onSubmit {
                                dismissKeyboard()
                            }
                            .padding(10)
                            .background(.black.opacity(0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        TextField("Ollama Model", text: $ollamaModel)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .focused($focusedField, equals: .model)
                            .submitLabel(.done)
                            .onSubmit {
                                dismissKeyboard()
                            }
                            .padding(10)
                            .background(.black.opacity(0.24))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("Simulator can use 127.0.0.1. Real iPhone needs your Mac LAN IP, for example http://192.168.x.x:11434.")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.48))

                        Text("On this Mac, try http://192.168.1.2:11434 if your iPhone is on the same Wi-Fi.")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.green.opacity(0.78))
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Ollama settings")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }

                Button {
                    dismissKeyboard()
                    askLLM()
                } label: {
                HStack(spacing: 8) {
                    if isAskingLLM {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.86)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }
                    Text(isAskingLLM ? "Asking..." : "Ask LLM")
                }
                .font(.callout.weight(.black))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(.green)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isAskingLLM || llmQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(isAskingLLM || llmQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.55 : 1)

            if let llmError {
                Text(llmError)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !llmAnswer.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(llmAnswer)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    if let metrics = llmMetrics {
                        tagRow([
                            metrics.mode.rawValue,
                            "TTFT \(String(format: "%.0f", metrics.ttftMs)) ms",
                            "Total \(String(format: "%.0f", metrics.totalLatencyMs)) ms",
                            "\(String(format: "%.1f", metrics.tokensPerSecond)) tok/s",
                            "\(metrics.completionTokens) out"
                        ], tint: .green)

                        Button {
                            viewModel.recordLLMMemoryEvent("after_llm_copy_json", metadata: [
                                "llm_benchmark_json_bytes": "\(metrics.benchmarkJSON.utf8.count)"
                            ])
                            UIPasteboard.general.string = metrics.benchmarkJSON
                        } label: {
                            Label("Copy benchmark JSON", systemImage: "doc.on.doc.fill")
                                .font(.caption.weight(.black))
                                .foregroundStyle(.white.opacity(0.86))
                        }
                    }
                }
                .padding(12)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.green.opacity(0.18), lineWidth: 1)
        )
    }

    private var llmModePicker: some View {
        HStack(spacing: 7) {
            ForEach(LLMOptimizationMode.allCases) { mode in
                Button {
                    dismissKeyboard()
                    llmMode = mode
                    llmAnswer = ""
                    llmMetrics = nil
                    llmError = nil
                } label: {
                    Text(mode.rawValue)
                        .font(.caption.weight(.black))
                        .foregroundStyle(llmMode == mode ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(llmMode == mode ? .green : .white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(isAskingLLM)
                .opacity(isAskingLLM && llmMode != mode ? 0.55 : 1)
            }
        }
    }

    private var nutritionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Nutrition")

            HStack(spacing: 10) {
                nutritionTile("Calories", value: recipe.calories > 0 ? "\(recipe.calories)" : "--", unit: "kcal", tint: .green)
                nutritionTile("Protein", value: recipe.protein > 0 ? "\(recipe.protein)" : "--", unit: "g", tint: .cyan)
            }

            HStack(spacing: 10) {
                nutritionTile("Carbs", value: recipe.carbs > 0 ? "\(recipe.carbs)" : "--", unit: "g", tint: .orange)
                nutritionTile("Fat", value: recipe.fat > 0 ? "\(recipe.fat)" : "--", unit: "g", tint: .pink)
                nutritionTile("Fiber", value: recipe.fiber > 0 ? "\(recipe.fiber)" : "--", unit: "g", tint: .mint)
            }
        }
        .cardStyle()
    }

    private var ingredientsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Detected Ingredients")

            if recipe.ingredients.isEmpty {
                emptyState("No ingredients detected yet.")
            } else {
                ForEach(recipe.ingredients) { ingredient in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ingredient.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                            Text("\(ingredient.calories) kcal | P \(ingredient.protein)g C \(ingredient.carbs)g F \(ingredient.fat)g")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.56))
                        }

                        Spacer()

                        Text("\(Int(ingredient.confidence * 100))%")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.green)
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .cardStyle()
    }

    private var recipeStepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Recipe")

            ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.black)
                        .frame(width: 24, height: 24)
                        .background(.green)
                        .clipShape(Circle())

                    Text(step)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .cardStyle()
    }

    private var shoppingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Next Shopping")

            if recipe.shoppingSuggestions.isEmpty {
                emptyState("Suggestions appear after a food target is selected.")
            } else {
                ForEach(recipe.shoppingSuggestions, id: \.self) { item in
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.green)
                        Text(item)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(12)
                    .background(.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .cardStyle()
    }

    private var benchmarkCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardTitle("Benchmark")
            row("Mode", viewModel.optimizationMode.rawValue)
            row("Backend", viewModel.activeBackend)
            row("Model", viewModel.activeModel)
            row("Policy", viewModel.activePolicySummary)
            row("FPS", String(format: "%.1f", viewModel.metrics.fps))
            row("p50 latency", String(format: "%.1f ms", viewModel.metrics.p50LatencyMs))
            row("p95 latency", String(format: "%.1f ms", viewModel.metrics.p95LatencyMs))
            row("Memory", viewModel.memoryDebugSummary)
            row("Memory detail", viewModel.memoryDetailSummary)
            row("VI planner", recipe.llmRuntimeNote)
            row("LLM mode", llmMetrics?.mode.title ?? llmMode.title)
            row("LLM decision", llmMetrics?.decisionSummary ?? llmMode.decisionSummary)
            row("Bundle", viewModel.bundleInventory.replacingOccurrences(of: "Bundle models: ", with: ""))

            Text(recipe.benchmarkNote)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 4)

            Button {
                UIPasteboard.general.string = viewModel.memoryReportJSON
            } label: {
                Label("Copy iPhone memory JSON", systemImage: "memorychip.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
        .cardStyle()
    }

    private func compilerPlanCard(plan: ServingExecutionPlanSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                cardTitle("Compiler Serving Plan")
                Spacer()
                Image(systemName: "cpu.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.green)
            }

            Text("Compiler artifact — not live execution")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.48))
                .fixedSize(horizontal: false, vertical: true)

            row("Model", plan.modelName)
            row("Target", plan.targetProfileId)
            row("Decision", plan.decisionSource)

            HStack(alignment: .firstTextBaseline) {
                Text("Cost source")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer(minLength: 16)
                Text(plan.costSource)
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(.green.opacity(0.32), lineWidth: 1))
            }
            .padding(.vertical, 3)
        }
        .cardStyle()
    }

    private func nutritionTile(_ title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.54))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title2.weight(.black))
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    .minimumScaleFactor(0.78)
                Text(unit)
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardTitle(_ title: String) -> some View {
        Text(title)
            .font(.title3.weight(.black))
            .foregroundStyle(.white)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.white.opacity(0.62))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.callout.weight(.bold))
                .foregroundStyle(.white.opacity(0.82))
            Spacer(minLength: 16)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .padding(.vertical, 3)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(.white.opacity(0.10), lineWidth: 1)
    }

    private func tagRow(_ tags: [String], tint: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.black))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(tint.opacity(0.22))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(tint.opacity(0.34), lineWidth: 1)
                        )
                }
            }
        }
    }

    private func askLLM() {
        let question = llmQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }

        isAskingLLM = true
        llmError = nil
        llmAnswer = ""
        llmMetrics = nil
        viewModel.recordLLMMemoryEvent("before_llm_ask", metadata: [
            "llm_question_chars": "\(question.count)",
            "llm_mode": llmMode.rawValue
        ])

        if isLikelyDeviceLocalhost(ollamaHost) {
            llmError = "On a real iPhone, 127.0.0.1 means the iPhone itself. Use your Mac LAN IP, for example http://192.168.1.2:11434, and make sure ollama serve is running."
            isAskingLLM = false
            viewModel.recordLLMMemoryEvent("after_llm_stream_finish", metadata: [
                "llm_error": "device_localhost",
                "llm_response_chars": "0"
            ])
            return
        }

        let client = OllamaClient(host: ollamaHost, preferredModel: ollamaModel, mode: llmMode)
        Task {
            do {
                let response = try await client.ask(question: question, recipe: recipe)
                await MainActor.run {
                    llmAnswer = response.answer
                    llmMetrics = response.metrics
                    isAskingLLM = false
                    viewModel.recordLLMMemoryEvent("after_llm_stream_finish", metadata: [
                        "llm_response_chars": "\(response.answer.count)",
                        "llm_benchmark_json_bytes": "\(response.metrics.benchmarkJSON.utf8.count)",
                        "llm_mode": response.metrics.mode.rawValue,
                        "llm_completion_tokens": "\(response.metrics.completionTokens)"
                    ])
                }
            } catch {
                await MainActor.run {
                    llmError = error.localizedDescription
                    isAskingLLM = false
                    viewModel.recordLLMMemoryEvent("after_llm_stream_finish", metadata: [
                        "llm_error": error.localizedDescription,
                        "llm_response_chars": "0"
                    ])
                }
            }
        }
    }

    private func isLikelyDeviceLocalhost(_ host: String) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("127.0.0.1") || normalized.contains("localhost")
        #endif
    }

    private func dismissKeyboard() {
        focusedField = nil
    }
}

extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Color(red: 0.12, green: 0.12, blue: 0.125))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
