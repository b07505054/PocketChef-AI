import Foundation

enum LLMOptimizationMode: String, CaseIterable, Identifiable {
    case baseline = "Base"
    case runtime = "Run"
    case compiler = "Comp"
    case combined = "All"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .baseline: return "LLM baseline"
        case .runtime: return "LLM runtime"
        case .compiler: return "LLM compiler"
        case .combined: return "LLM combined"
        }
    }

    var decisionSummary: String {
        switch self {
        case .baseline:
            return "default Ollama streaming decode"
        case .runtime:
            return "runtime policy: warm model keep_alive + short answer budget"
        case .compiler:
            return "compiler policy: prompt lowering + compact structured context"
        case .combined:
            return "combined policy: warm runtime + prompt lowering"
        }
    }

    var numPredict: Int {
        switch self {
        case .baseline: return 180
        case .runtime: return 120
        case .compiler: return 140
        case .combined: return 110
        }
    }

    var temperature: Double {
        switch self {
        case .baseline: return 0.25
        case .runtime: return 0.2
        case .compiler: return 0.15
        case .combined: return 0.15
        }
    }

    var keepAlive: String? {
        switch self {
        case .baseline, .compiler: return nil
        case .runtime, .combined: return "10m"
        }
    }

    var usesPromptLowering: Bool {
        switch self {
        case .compiler, .combined: return true
        case .baseline, .runtime: return false
        }
    }
}

struct LLMMetrics: Equatable {
    let model: String
    let backend: String
    let mode: LLMOptimizationMode
    let decisionSummary: String
    let ttftMs: Double
    let totalLatencyMs: Double
    let promptTokens: Int
    let completionTokens: Int
    let tokensPerSecond: Double
    let question: String
    let selectedIngredients: [String]

    var summary: String {
        "TTFT \(String(format: "%.1f", ttftMs)) ms | total \(String(format: "%.1f", totalLatencyMs)) ms | \(String(format: "%.1f", tokensPerSecond)) tok/s"
    }

    var benchmarkJSON: String {
        let payload: [String: Any] = [
            "artifact_type": "pocketchef_llm_benchmark_result",
            "backend": backend,
            "mode": mode.rawValue,
            "decision_type": "local_llm_serving_runtime",
            "decision_summary": decisionSummary,
            "model": model,
            "ttft_ms": ttftMs,
            "total_latency_ms": totalLatencyMs,
            "prompt_tokens": promptTokens,
            "completion_tokens": completionTokens,
            "tokens_per_second": tokensPerSecond,
            "question": question,
            "selected_ingredients": selectedIngredients
        ]

        guard
            JSONSerialization.isValidJSONObject(payload),
            let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}

struct LLMResponse: Equatable {
    let answer: String
    let metrics: LLMMetrics
}

enum OllamaClientError: LocalizedError {
    case invalidHost
    case emptyQuestion
    case badHTTPStatus(Int)
    case emptyResponse
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Invalid Ollama host. Use a URL like http://127.0.0.1:11434 or http://192.168.x.x:11434."
        case .emptyQuestion:
            return "Type a question before asking the LLM."
        case .badHTTPStatus(let status):
            return "Ollama returned HTTP \(status). Check that ollama serve is running and the model is pulled."
        case .emptyResponse:
            return "Ollama returned an empty response."
        case .modelUnavailable(let model):
            return "Ollama model \(model) is unavailable. Pull qwen2.5:3b-instruct or llama3.2:3b."
        }
    }
}

struct OllamaClient {
    var host: String
    var preferredModel = "qwen2.5:3b-instruct"
    var fallbackModel = "llama3.2:3b"
    var mode: LLMOptimizationMode = .baseline

    func ask(question rawQuestion: String, recipe: RecipePlan) async throws -> LLMResponse {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { throw OllamaClientError.emptyQuestion }

        do {
            return try await ask(question: question, recipe: recipe, model: preferredModel)
        } catch {
            if shouldTryFallback(after: error), preferredModel != fallbackModel {
                return try await ask(question: question, recipe: recipe, model: fallbackModel)
            }
            throw error
        }
    }

    private func ask(question: String, recipe: RecipePlan, model: String) async throws -> LLMResponse {
        guard let url = URL(string: normalizedHost() + "/api/chat") else {
            throw OllamaClientError.invalidHost
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: requestPayload(question: question, recipe: recipe, model: model))

        let start = Date()
        var firstTokenDate: Date?
        var answer = ""
        var finalChunk: OllamaChatChunk?

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode < 200 || http.statusCode >= 300 {
            if http.statusCode == 404 {
                throw OllamaClientError.modelUnavailable(model)
            }
            throw OllamaClientError.badHTTPStatus(http.statusCode)
        }

        for try await line in bytes.lines {
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }
            let chunk = try JSONDecoder().decode(OllamaChatChunk.self, from: data)
            if let content = chunk.message?.content, !content.isEmpty {
                if firstTokenDate == nil {
                    firstTokenDate = Date()
                }
                answer += content
            }
            if chunk.done == true {
                finalChunk = chunk
            }
        }

        let cleanedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedAnswer.isEmpty else { throw OllamaClientError.emptyResponse }

        let totalLatencyMs = durationMs(from: start, to: Date())
        let ttftMs = firstTokenDate.map { durationMs(from: start, to: $0) } ?? totalLatencyMs
        let completionTokens = finalChunk?.evalCount ?? 0
        let tokensPerSecond = tokensPerSecond(completionTokens: completionTokens, evalDurationNs: finalChunk?.evalDuration)
        let ingredientNames = recipe.ingredients.map(\.name)

        return LLMResponse(
            answer: cleanedAnswer,
            metrics: LLMMetrics(
                model: finalChunk?.model ?? model,
                backend: "ollama_local_lan",
                mode: mode,
                decisionSummary: mode.decisionSummary,
                ttftMs: ttftMs,
                totalLatencyMs: totalLatencyMs,
                promptTokens: finalChunk?.promptEvalCount ?? 0,
                completionTokens: completionTokens,
                tokensPerSecond: tokensPerSecond,
                question: question,
                selectedIngredients: ingredientNames
            )
        )
    }

    private func normalizedHost() -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func shouldTryFallback(after error: Error) -> Bool {
        if case OllamaClientError.modelUnavailable = error {
            return true
        }

        let message = error.localizedDescription.lowercased()
        return message.contains("not found") || message.contains("model") || message.contains("404")
    }

    private func requestPayload(question: String, recipe: RecipePlan, model: String) -> [String: Any] {
        var payload: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                [
                    "role": "system",
                    "content": Self.systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPrompt(question: question, recipe: recipe)
                ]
            ],
            "options": [
                "temperature": mode.temperature,
                "num_predict": mode.numPredict
            ]
        ]

        if let keepAlive = mode.keepAlive {
            payload["keep_alive"] = keepAlive
        }

        return payload
    }

    private func userPrompt(question: String, recipe: RecipePlan) -> String {
        let ingredients = recipe.ingredients.isEmpty
            ? "none"
            : recipe.ingredients.map { "\($0.name) confidence \(Int($0.confidence * 100))%" }.joined(separator: ", ")

        if mode.usesPromptLowering {
            return """
            TASK: Answer the user's PocketChef question in under 90 words.
            VISUAL_FACTS: \(ingredients)
            NUTRITION_ESTIMATE: \(recipe.calories) kcal; P \(recipe.protein)g; C \(recipe.carbs)g; F \(recipe.fat)g; fiber \(recipe.fiber)g.
            PLAN: \(recipe.title)
            QUESTION: \(question)
            """
        }

        return """
        Detected visual ingredients: \(ingredients)
        Estimated nutrition: \(recipe.calories) kcal, protein \(recipe.protein)g, carbs \(recipe.carbs)g, fat \(recipe.fat)g, fiber \(recipe.fiber)g.
        Current recipe plan: \(recipe.title). \(recipe.subtitle)
        Local planner note: \(recipe.visualAnswer)
        User question: \(question)
        """
    }

    private func durationMs(from start: Date, to end: Date) -> Double {
        end.timeIntervalSince(start) * 1000
    }

    private func tokensPerSecond(completionTokens: Int, evalDurationNs: Int64?) -> Double {
        guard completionTokens > 0, let evalDurationNs, evalDurationNs > 0 else { return 0 }
        return Double(completionTokens) / (Double(evalDurationNs) / 1_000_000_000)
    }

    private static let systemPrompt = """
    You are PocketChef's visual food assistant. Use only the detected ingredients as visual facts. If you infer anything beyond the visual detections, label it as an assumption. Answer recipe, nutrition, substitution, and meal-planning questions. Do not make medical claims. Keep the answer under 120 words.
    """
}

private struct OllamaChatChunk: Decodable {
    let model: String?
    let message: OllamaMessage?
    let done: Bool?
    let totalDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?
    let evalDuration: Int64?

    enum CodingKeys: String, CodingKey {
        case model
        case message
        case done
        case totalDuration = "total_duration"
        case promptEvalCount = "prompt_eval_count"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
}

private struct OllamaMessage: Decodable {
    let role: String?
    let content: String?
}
