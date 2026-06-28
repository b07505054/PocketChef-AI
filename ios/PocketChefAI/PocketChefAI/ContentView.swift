import AVFoundation
import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @StateObject private var coordinator = PortfolioCoordinator()
    @State private var showsResultSheet = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if viewModel.authorizationStatus == .denied || viewModel.authorizationStatus == .restricted {
                    permissionView
                } else {
                    cameraSurface
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    viewModel.setTargetPrompt(normalizedPoint(
                                        from: value.location,
                                        in: proxy.size
                                    ))
                                }
                        )

                    DetectionOverlay(
                        detections: viewModel.detections,
                        promptPoint: viewModel.targetPrompt,
                        geometry: viewModel.capturedGeometry
                    )
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()

                    if viewModel.activeBackend == "No Core ML model loaded" {
                        missingModelBanner
                    }

                    VStack {
                        HStack {
                            MetricsPanel(viewModel: viewModel)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 14)

                        Spacer()

                        VStack(spacing: 14) {
                            Button {
                                showsResultSheet = true
                            } label: {
                                LiveRecipePreview(recipe: viewModel.currentRecipe)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Open Visual Intelligence snapshot")

                            Button {
                                if viewModel.isPhotoCaptured {
                                    viewModel.retakePhoto()
                                } else {
                                    viewModel.capturePhoto()
                                }
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(viewModel.isPhotoCaptured ? .green.opacity(0.28) : .white.opacity(0.22))
                                        .frame(width: 74, height: 74)
                                    Circle()
                                        .stroke(.white.opacity(0.45), lineWidth: 1)
                                        .frame(width: 74, height: 74)
                                    Image(systemName: viewModel.isPhotoCaptured ? "arrow.counterclockwise" : "camera.fill")
                                        .font(.system(size: 30, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                                .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                            }
                            .accessibilityLabel(viewModel.isPhotoCaptured ? "Retake photo" : "Capture photo")
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 22)
                    }
                }
            }
            .background(.black)
        }
        .task {
            viewModel.start()
            await coordinator.loadCompilerArtifacts()
        }
        .onDisappear {
            viewModel.stop()
        }
        .sheet(isPresented: $showsResultSheet) {
            ResultSheet(
                viewModel: viewModel,
                traceDomain: coordinator.trace,
                servingPlan: coordinator.compiler.servingPlan
            ) {
                showsResultSheet = false
            }
        }
    }

    @ViewBuilder
    private var cameraSurface: some View {
        if let image = viewModel.capturedImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    Text("Tap target")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(.green)
                        .clipShape(Capsule())
                        .padding(.top, 72)
                        .padding(.trailing, 16)
                }
        } else {
            CameraPreview(session: viewModel.session)
        }
    }

    private func normalizedPoint(from location: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }

        if let geometry = viewModel.capturedGeometry {
            return geometry.normalizedPoint(from: location, in: size)
        }

        return CGPoint(
            x: min(max(location.x / size.width, 0), 1),
            y: min(max(1 - location.y / size.height, 0), 1)
        )
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text("Camera access is required for real-time food detection.")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Text("Enable camera permission in Settings, then reopen PocketChef-AI.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
        }
        .padding(24)
    }

    private var missingModelBanner: some View {
        VStack {
            Spacer()
            Text("No Core ML detector loaded")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.red.opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.bottom, 104)
        }
        .allowsHitTesting(false)
    }
}

private struct LiveRecipePreview: View {
    let recipe: RecipePlan

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(recipe.title)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)

                    Text(recipe.subtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.66))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text(recipe.calories > 0 ? "\(recipe.calories)" : "--")
                        .font(.title3.weight(.black))
                        .foregroundStyle(.green)
                        .monospacedDigit()
                    Text("kcal")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.56))
                }
            }

            HStack(spacing: 8) {
                macro("P", value: recipe.protein, unit: "g")
                macro("C", value: recipe.carbs, unit: "g")
                macro("F", value: recipe.fat, unit: "g")
                macro("Fiber", value: recipe.fiber, unit: "g")
            }

            if !recipe.ingredients.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(recipe.ingredients) { ingredient in
                            Text("\(ingredient.name) \(Int(ingredient.confidence * 100))%")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(.white.opacity(0.14))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func macro(_ label: String, value: Int, unit: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.black))
                .foregroundStyle(.white.opacity(0.55))
            Text(value > 0 ? "\(value)\(unit)" : "--")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}
