import Foundation

struct IngredientSummary: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let confidence: Float
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fiber: Int
}

struct RecipePlan: Equatable {
    let title: String
    let subtitle: String
    let sceneSummary: String
    let visualAnswer: String
    let ingredients: [IngredientSummary]
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let fiber: Int
    let dietTags: [String]
    let missingItems: [String]
    let shoppingSuggestions: [String]
    let steps: [String]
    let nutritionNote: String
    let benchmarkNote: String
    let llmRuntimeNote: String

    static let empty = RecipePlan(
        title: "Point Camera at Food",
        subtitle: "Detected ingredients will become a recipe snapshot.",
        sceneSummary: "No target ingredient has been selected yet.",
        visualAnswer: "Capture a frame, tap the food item, then PocketChef will turn the visual result into a recipe and nutrition snapshot.",
        ingredients: [],
        calories: 0,
        protein: 0,
        carbs: 0,
        fat: 0,
        fiber: 0,
        dietTags: ["Waiting for target"],
        missingItems: [],
        shoppingSuggestions: [],
        steps: [
            "Run food detection on a real ingredient.",
            "Capture a snapshot after labels stabilize."
        ],
        nutritionNote: "Nutrition is estimated locally from detected labels.",
        benchmarkNote: "No ingredients detected yet.",
        llmRuntimeNote: "Visual Intelligence v1 uses a local deterministic planner. LLM serving is deferred until it has artifact-backed metrics."
    )
}

final class PocketChefPlanner {
    private struct NutritionProfile {
        let displayName: String
        let calories: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let fiber: Int
        let role: String
    }

    private let profiles: [String: NutritionProfile] = [
        "banana": .init(displayName: "Banana", calories: 105, protein: 1, carbs: 27, fat: 0, fiber: 3, role: "natural sweetness"),
        "apple": .init(displayName: "Apple", calories: 95, protein: 0, carbs: 25, fat: 0, fiber: 4, role: "crisp freshness"),
        "granny smith": .init(displayName: "Granny Smith", calories: 95, protein: 0, carbs: 25, fat: 0, fiber: 4, role: "crisp tartness"),
        "sandwich": .init(displayName: "Sandwich", calories: 360, protein: 18, carbs: 42, fat: 13, fiber: 4, role: "hearty base"),
        "orange": .init(displayName: "Orange", calories: 62, protein: 1, carbs: 15, fat: 0, fiber: 3, role: "bright acidity"),
        "lemon": .init(displayName: "Lemon", calories: 17, protein: 1, carbs: 5, fat: 0, fiber: 2, role: "bright acidity"),
        "pineapple": .init(displayName: "Pineapple", calories: 82, protein: 1, carbs: 22, fat: 0, fiber: 2, role: "tropical sweetness"),
        "strawberry": .init(displayName: "Strawberry", calories: 49, protein: 1, carbs: 12, fat: 0, fiber: 3, role: "berry brightness"),
        "fig": .init(displayName: "Fig", calories: 37, protein: 0, carbs: 10, fat: 0, fiber: 1, role: "jammy sweetness"),
        "pomegranate": .init(displayName: "Pomegranate", calories: 144, protein: 3, carbs: 33, fat: 2, fiber: 7, role: "tart crunch"),
        "broccoli": .init(displayName: "Broccoli", calories: 55, protein: 4, carbs: 11, fat: 1, fiber: 5, role: "green crunch"),
        "cauliflower": .init(displayName: "Cauliflower", calories: 25, protein: 2, carbs: 5, fat: 0, fiber: 2, role: "mild vegetable base"),
        "zucchini": .init(displayName: "Zucchini", calories: 33, protein: 2, carbs: 6, fat: 1, fiber: 2, role: "light vegetable base"),
        "cucumber": .init(displayName: "Cucumber", calories: 16, protein: 1, carbs: 4, fat: 0, fiber: 1, role: "fresh crunch"),
        "bell pepper": .init(displayName: "Bell Pepper", calories: 31, protein: 1, carbs: 7, fat: 0, fiber: 2, role: "sweet crunch"),
        "mushroom": .init(displayName: "Mushroom", calories: 15, protein: 2, carbs: 2, fat: 0, fiber: 1, role: "savory depth"),
        "corn": .init(displayName: "Corn", calories: 96, protein: 3, carbs: 21, fat: 1, fiber: 2, role: "sweet starch"),
        "carrot": .init(displayName: "Carrot", calories: 41, protein: 1, carbs: 10, fat: 0, fiber: 3, role: "sweet crunch"),
        "hot dog": .init(displayName: "Hot Dog", calories: 290, protein: 10, carbs: 24, fat: 17, fiber: 1, role: "savory protein"),
        "hotdog": .init(displayName: "Hotdog", calories: 290, protein: 10, carbs: 24, fat: 17, fiber: 1, role: "savory protein"),
        "cheeseburger": .init(displayName: "Cheeseburger", calories: 303, protein: 15, carbs: 30, fat: 14, fiber: 2, role: "savory base"),
        "bagel": .init(displayName: "Bagel", calories: 245, protein: 10, carbs: 48, fat: 2, fiber: 2, role: "bread base"),
        "pretzel": .init(displayName: "Pretzel", calories: 226, protein: 7, carbs: 48, fat: 2, fiber: 2, role: "salty starch"),
        "french loaf": .init(displayName: "French Loaf", calories: 170, protein: 6, carbs: 33, fat: 1, fiber: 2, role: "bread base"),
        "burrito": .init(displayName: "Burrito", calories: 300, protein: 13, carbs: 40, fat: 10, fiber: 5, role: "wrapped meal base"),
        "potpie": .init(displayName: "Potpie", calories: 410, protein: 16, carbs: 36, fat: 24, fiber: 3, role: "comfort base"),
        "meat loaf": .init(displayName: "Meat Loaf", calories: 260, protein: 20, carbs: 12, fat: 15, fiber: 1, role: "savory protein"),
        "mashed potato": .init(displayName: "Mashed Potato", calories: 214, protein: 4, carbs: 35, fat: 7, fiber: 3, role: "soft starch"),
        "carbonara": .init(displayName: "Carbonara", calories: 420, protein: 18, carbs: 46, fat: 18, fiber: 2, role: "pasta base"),
        "dough": .init(displayName: "Dough", calories: 130, protein: 4, carbs: 25, fat: 2, fiber: 1, role: "starch base"),
        "pizza": .init(displayName: "Pizza", calories: 285, protein: 12, carbs: 36, fat: 10, fiber: 2, role: "comfort base"),
        "guacamole": .init(displayName: "Guacamole", calories: 150, protein: 2, carbs: 8, fat: 13, fiber: 6, role: "creamy fat"),
        "donut": .init(displayName: "Donut", calories: 260, protein: 3, carbs: 31, fat: 14, fiber: 1, role: "sweet finish"),
        "cake": .init(displayName: "Cake", calories: 350, protein: 4, carbs: 52, fat: 15, fiber: 1, role: "dessert component"),
        "ice cream": .init(displayName: "Ice Cream", calories: 207, protein: 4, carbs: 24, fat: 11, fiber: 1, role: "sweet finish"),
        "ice lolly": .init(displayName: "Ice Lolly", calories: 70, protein: 0, carbs: 18, fat: 0, fiber: 0, role: "sweet finish"),
        "trifle": .init(displayName: "Trifle", calories: 300, protein: 5, carbs: 45, fat: 10, fiber: 2, role: "sweet finish"),
        "eggnog": .init(displayName: "Eggnog", calories: 224, protein: 10, carbs: 20, fat: 11, fiber: 0, role: "rich dairy"),
        "consomme": .init(displayName: "Consomme", calories: 45, protein: 5, carbs: 3, fat: 1, fiber: 0, role: "light broth"),
        "hot pot": .init(displayName: "Hot Pot", calories: 350, protein: 22, carbs: 20, fat: 20, fiber: 4, role: "warm mixed meal"),
        "soup bowl": .init(displayName: "Soup Bowl", calories: 120, protein: 5, carbs: 14, fat: 4, fiber: 2, role: "light meal"),
        "plate": .init(displayName: "Plate", calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, role: "serving vessel"),
        "cup": .init(displayName: "Cup", calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, role: "serving vessel"),
        "bowl": .init(displayName: "Bowl", calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0, role: "serving vessel")
    ]

    func makePlan(from detections: [Detection], mode: OptimizationMode, latencyMs: Double, fps: Double) -> RecipePlan {
        let ingredients = summarize(detections: detections)
        guard !ingredients.isEmpty else { return .empty }

        let calories = ingredients.reduce(0) { $0 + $1.calories }
        let protein = ingredients.reduce(0) { $0 + $1.protein }
        let carbs = ingredients.reduce(0) { $0 + $1.carbs }
        let fat = ingredients.reduce(0) { $0 + $1.fat }
        let fiber = ingredients.reduce(0) { $0 + $1.fiber }
        let title = recipeTitle(for: ingredients)
        let missingItems = missingItems(for: ingredients)
        let tags = dietTags(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber)

        return RecipePlan(
            title: title,
            subtitle: subtitle(for: ingredients),
            sceneSummary: sceneSummary(for: ingredients),
            visualAnswer: visualAnswer(title: title, ingredients: ingredients, missingItems: missingItems),
            ingredients: ingredients,
            calories: calories,
            protein: protein,
            carbs: carbs,
            fat: fat,
            fiber: fiber,
            dietTags: tags,
            missingItems: missingItems,
            shoppingSuggestions: Array(missingItems.prefix(3)),
            steps: steps(for: ingredients),
            nutritionNote: nutritionNote(calories: calories, protein: protein, carbs: carbs, fat: fat, fiber: fiber),
            benchmarkNote: "\(mode.rawValue) snapshot - \(String(format: "%.1f", fps)) FPS, \(String(format: "%.1f", latencyMs)) ms latest latency",
            llmRuntimeNote: llmRuntimeNote(mode: mode, latencyMs: latencyMs)
        )
    }

    private func summarize(detections: [Detection]) -> [IngredientSummary] {
        let grouped = Dictionary(grouping: detections) { $0.label.lowercased() }

        return grouped.compactMap { label, detections in
            guard let profile = profiles[label] else { return nil }
            guard profile.calories > 0 || label != "bowl" else { return nil }
            let confidence = detections.map(\.confidence).max() ?? 0

            return IngredientSummary(
                name: profile.displayName,
                confidence: confidence,
                calories: profile.calories,
                protein: profile.protein,
                carbs: profile.carbs,
                fat: profile.fat,
                fiber: profile.fiber
            )
        }
        .sorted { lhs, rhs in
            if lhs.confidence == rhs.confidence {
                return lhs.name < rhs.name
            }
            return lhs.confidence > rhs.confidence
        }
        .prefix(5)
        .map { $0 }
    }

    private func recipeTitle(for ingredients: [IngredientSummary]) -> String {
        let names = ingredients.map(\.name)

        if names.contains("Broccoli") || names.contains("Carrot") {
            return "\(names.first ?? "Veggie") Power Bowl"
        }

        if names.contains("Pizza") || names.contains("Sandwich") || names.contains("Hot Dog") || names.contains("Hotdog") || names.contains("Cheeseburger") || names.contains("Burrito") {
            return "Fast Plate Remix"
        }

        if names.contains("Donut") || names.contains("Cake") || names.contains("Ice Cream") || names.contains("Trifle") {
            return "Smart Dessert Plate"
        }

        if names.contains("Banana") || names.contains("Apple") || names.contains("Granny Smith") || names.contains("Orange") || names.contains("Pineapple") || names.contains("Strawberry") {
            return "Fresh Fruit Bowl"
        }

        return "\(names.first ?? "PocketChef") Bowl"
    }

    private func subtitle(for ingredients: [IngredientSummary]) -> String {
        let names = ingredients.map(\.name)
        if names.count == 1 {
            return "Built from \(names[0])"
        }
        return "Built from \(names.prefix(3).joined(separator: ", "))"
    }

    private func steps(for ingredients: [IngredientSummary]) -> [String] {
        let names = ingredients.map { $0.name.lowercased() }
        var steps = [
            "Clean and portion the detected ingredients.",
            "Build a balanced plate with the highest-confidence items first."
        ]

        if names.contains("broccoli") || names.contains("carrot") {
            steps.append("Saute vegetables for 4-6 minutes with salt, pepper, and a little oil.")
        }

        if names.contains("sandwich") || names.contains("pizza") || names.contains("hot dog") || names.contains("hotdog") || names.contains("cheeseburger") || names.contains("burrito") {
            steps.append("Warm the savory base, then add fresh items on top for texture.")
        }

        if names.contains("banana") || names.contains("apple") || names.contains("granny smith") || names.contains("orange") || names.contains("pineapple") || names.contains("strawberry") {
            steps.append("Slice fruit last so it stays bright and crisp.")
        }

        if names.contains("donut") || names.contains("cake") || names.contains("ice cream") || names.contains("trifle") {
            steps.append("Keep dessert as the side component and pair with fruit if available.")
        }

        steps.append("Capture benchmark mode and latency with the final snapshot.")
        return Array(steps.prefix(5))
    }

    private func nutritionNote(calories: Int, protein: Int, carbs: Int, fat: Int, fiber: Int) -> String {
        if protein >= 20 {
            return "Higher-protein plate with \(protein)g protein and \(fiber)g fiber."
        }

        if carbs >= 50 {
            return "Carb-forward plate. Add tofu, meat, or another protein source later."
        }

        if calories <= 180 {
            return "Light snack profile. Add a protein source for a fuller meal."
        }

        return "Balanced estimate: \(calories) kcal, \(protein)g protein, \(carbs)g carbs, \(fat)g fat."
    }

    private func sceneSummary(for ingredients: [IngredientSummary]) -> String {
        let strongest = ingredients.first
        let names = ingredients.map(\.name)
        let confidence = strongest.map { "\(Int($0.confidence * 100))%" } ?? "--"

        if names.count == 1, let name = names.first {
            return "The selected visual target looks like \(name) with \(confidence) confidence."
        }

        return "The selected scene contains \(names.prefix(3).joined(separator: ", ")); the strongest target is \(strongest?.name ?? "unknown") at \(confidence)."
    }

    private func visualAnswer(title: String, ingredients: [IngredientSummary], missingItems: [String]) -> String {
        let names = ingredients.map(\.name)
        let base = names.isEmpty ? "the selected item" : names.prefix(3).joined(separator: ", ")

        if missingItems.isEmpty {
            return "Make \(title) from \(base). The detected items are enough for a simple snapshot recipe."
        }

        return "Make \(title) from \(base). To turn it into a fuller meal, add \(missingItems.prefix(2).joined(separator: " and "))."
    }

    private func missingItems(for ingredients: [IngredientSummary]) -> [String] {
        let names = Set(ingredients.map { $0.name.lowercased() })

        if names.contains("banana") || names.contains("apple") || names.contains("granny smith") || names.contains("orange") || names.contains("pineapple") || names.contains("strawberry") || names.contains("fig") || names.contains("pomegranate") {
            return ["Greek yogurt", "oats", "nuts", "cinnamon"]
        }

        if names.contains("broccoli") || names.contains("cauliflower") || names.contains("zucchini") || names.contains("cucumber") || names.contains("bell pepper") || names.contains("mushroom") || names.contains("carrot") {
            return ["egg", "tofu", "quinoa", "olive oil"]
        }

        if names.contains("sandwich") || names.contains("pizza") || names.contains("hot dog") || names.contains("hotdog") || names.contains("cheeseburger") || names.contains("burrito") {
            return ["leafy greens", "tomato", "fruit side", "water"]
        }

        if names.contains("donut") || names.contains("cake") || names.contains("ice cream") || names.contains("trifle") {
            return ["berries", "Greek yogurt", "unsweetened tea"]
        }

        return ["protein source", "green vegetable", "whole grain"]
    }

    private func dietTags(calories: Int, protein: Int, carbs: Int, fat: Int, fiber: Int) -> [String] {
        var tags: [String] = []

        if calories <= 180 {
            tags.append("Light snack")
        }

        if protein >= 20 {
            tags.append("High protein")
        }

        if carbs >= 45 {
            tags.append("Carb forward")
        }

        if fiber >= 4 {
            tags.append("Fiber source")
        }

        if carbs <= 10 && fat >= 10 {
            tags.append("Low carb")
        }

        if tags.isEmpty {
            tags.append("Balanced")
        }

        return tags
    }

    private func llmRuntimeNote(mode: OptimizationMode, latencyMs: Double) -> String {
        "Local Visual Intelligence planner. Input=selected segmentation labels; decision=recipe/nutrition rules; metric=\(mode.rawValue) CV latency \(String(format: "%.1f", latencyMs)) ms. External LLM serving remains future work."
    }
}
