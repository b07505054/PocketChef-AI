import CoreML
import CoreVideo
import Foundation
import Vision

struct FoodClassification {
    let label: String
    let confidence: Float
}

final class FoodClassifier {
    private var request: VNCoreMLRequest?
    private(set) var modelName = "missing_food_classifier"
    private let confidenceThreshold: Float = 0.20

    private let foodLabels: Set<String> = [
        "banana", "orange", "lemon", "pineapple", "strawberry", "fig",
        "jackfruit", "custard_apple", "pomegranate", "Granny_Smith",
        "guacamole", "broccoli", "cauliflower", "zucchini", "cucumber",
        "bell_pepper", "mushroom", "corn", "acorn", "pizza", "hotdog",
        "cheeseburger", "bagel", "pretzel", "French_loaf", "burrito",
        "potpie", "meat_loaf", "mashed_potato", "carbonara", "dough",
        "soup_bowl", "plate", "cup", "eggnog", "ice_cream", "ice_lolly",
        "trifle", "consomme", "hot_pot"
    ]

    var isLoaded: Bool { request != nil }

    func configure(computeUnits: MLComputeUnits) {
        request = nil
        modelName = "missing_food_classifier"

        guard let url = modelURL(named: "food_classifier_fp32") else { return }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = computeUnits
            let model = try MLModel(contentsOf: url, configuration: config)
            let visionModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = .centerCrop
            self.request = request
            modelName = "food_classifier_fp32"
        } catch {
            modelName = "food_classifier_fp32 failed: \(error.localizedDescription)"
        }
    }

    func classify(pixelBuffer: CVPixelBuffer) -> FoodClassification? {
        guard let request else { return nil }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results as? [VNClassificationObservation] else {
            return nil
        }

        for observation in observations.prefix(8) {
            guard observation.confidence >= confidenceThreshold else { continue }
            guard foodLabels.contains(observation.identifier) else { continue }
            return FoodClassification(
                label: displayName(for: observation.identifier),
                confidence: observation.confidence
            )
        }

        return nil
    }

    private func displayName(for identifier: String) -> String {
        identifier
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .capitalized
    }

    private func modelURL(named name: String) -> URL? {
        let extensions = ["mlmodelc", "mlpackage", "mlmodel"]
        for ext in extensions {
            if let rootURL = Bundle.main.url(forResource: name, withExtension: ext) {
                return rootURL
            }
            if let nestedURL = Bundle.main.url(
                forResource: name,
                withExtension: ext,
                subdirectory: "models"
            ) {
                return nestedURL
            }
        }
        return nil
    }
}
