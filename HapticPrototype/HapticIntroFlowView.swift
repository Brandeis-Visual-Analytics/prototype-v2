import SwiftUI
import CoreHaptics
import Combine

// MARK: - Main Flow View

struct HapticIntroFlowView: View {
    @State private var currentScreen: IntroScreen = .intensityExamples
    @StateObject private var haptics = IntroHapticManager()

    @State private var intensityValue: Double = 0.5
    @State private var sharpnessValue: Double = 0.5

    var body: some View {
        VStack(spacing: 0) {
            header

            Spacer()

            contentView
                .padding(.horizontal, 24)

            Spacer()

            navigationBar
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
        .onDisappear {
            haptics.stop()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(currentScreen.title)
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text(currentScreen.subtitle)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding(.top, 32)
    }

    @ViewBuilder
    private var contentView: some View {
        switch currentScreen {
        case .intensityExamples:
            comparisonScreen(
                leftTitle: "Low Intensity",
                rightTitle: "High Intensity",
                leftIntensity: 0.2,
                leftSharpness: 0.5,
                rightIntensity: 1.0,
                rightSharpness: 0.5
            )

        case .intensitySlider:
            singleBoxWithOneSlider(
                intensity: $intensityValue,
                sharpness: .constant(0.5),
                sliderTitle: "Intensity",
                showSharpnessLabels: false
            )

        case .sharpnessExamples:
            comparisonScreen(
                leftTitle: "Smooth",
                rightTitle: "Sharp",
                leftIntensity: 0.7,
                leftSharpness: 0.1,
                rightIntensity: 0.7,
                rightSharpness: 1.0
            )

        case .sharpnessSlider:
            singleBoxWithOneSlider(
                intensity: .constant(0.7),
                sharpness: $sharpnessValue,
                sliderTitle: "Sharpness",
                showSharpnessLabels: true
            )

        case .combinations:
            combinationsGrid

        case .bothSliders:
            bothSlidersScreen
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 16) {
            Button(action: previousScreen) {
                Text("Back")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(14)
            }
            .disabled(currentScreen == .intensityExamples)
            .opacity(currentScreen == .intensityExamples ? 0.5 : 1.0)

            Button(action: nextScreen) {
                Text(currentScreen == .bothSliders ? "Done" : "Next")
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Screen Builders

    private func comparisonScreen(
        leftTitle: String,
        rightTitle: String,
        leftIntensity: Double,
        leftSharpness: Double,
        rightIntensity: Double,
        rightSharpness: Double
    ) -> some View {
        HStack(spacing: 20) {
            VStack(spacing: 12) {
                HapticTouchBox(
                    title: "",
                    intensity: leftIntensity,
                    sharpness: leftSharpness,
                    haptics: haptics
                )
                Text(leftTitle)
                    .font(.headline)
            }

            VStack(spacing: 12) {
                HapticTouchBox(
                    title: "",
                    intensity: rightIntensity,
                    sharpness: rightSharpness,
                    haptics: haptics
                )
                Text(rightTitle)
                    .font(.headline)
            }
        }
    }

    private func singleBoxWithOneSlider(
        intensity: Binding<Double>,
        sharpness: Binding<Double>,
        sliderTitle: String,
        showSharpnessLabels: Bool
    ) -> some View {
        VStack(spacing: 28) {
            HapticTouchBox(
                title: "",
                intensity: intensity.wrappedValue,
                sharpness: sharpness.wrappedValue,
                haptics: haptics
            )

            VStack(spacing: 10) {
                Text(sliderTitle)
                    .font(.headline)

                Slider(
                    value: sliderTitle == "Intensity" ? intensity : sharpness,
                    in: 0...1
                )
                .onChange(of: intensity.wrappedValue) { _, newValue in
                    haptics.updateContinuous(intensity: Float(newValue),
                                             sharpness: Float(sharpness.wrappedValue))
                }
                .onChange(of: sharpness.wrappedValue) { _, newValue in
                    haptics.updateContinuous(intensity: Float(intensity.wrappedValue),
                                             sharpness: Float(newValue))
                }

                if sliderTitle == "Intensity" {
                    Text("Current: \(intensityLabel(for: intensity.wrappedValue))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if showSharpnessLabels {
                    HStack {
                        Text("Smooth")
                        Spacer()
                        Text("Sharp")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    private var combinationsGrid: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                CombinationCard(
                    title: "High Intensity\n+ High Sharpness",
                    intensity: 1.0,
                    sharpness: 1.0,
                    haptics: haptics
                )

                CombinationCard(
                    title: "High Intensity\n+ Low Sharpness",
                    intensity: 1.0,
                    sharpness: 0.1,
                    haptics: haptics
                )

                CombinationCard(
                    title: "Low Intensity\n+ High Sharpness",
                    intensity: 0.2,
                    sharpness: 1.0,
                    haptics: haptics
                )

                CombinationCard(
                    title: "Low Intensity\n+ Low Sharpness",
                    intensity: 0.2,
                    sharpness: 0.1,
                    haptics: haptics
                )
            }
        }
    }

    private var bothSlidersScreen: some View {
        VStack(spacing: 28) {
            HapticTouchBox(
                title: "",
                intensity: intensityValue,
                sharpness: sharpnessValue,
                haptics: haptics
            )

            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Intensity")
                        .font(.headline)
                    Slider(value: $intensityValue, in: 0...1)
                        .onChange(of: intensityValue) { _, newValue in
                            haptics.updateContinuous(
                                intensity: Float(newValue),
                                sharpness: Float(sharpnessValue)
                            )
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sharpness")
                        .font(.headline)
                    Slider(value: $sharpnessValue, in: 0...1)
                        .onChange(of: sharpnessValue) { _, newValue in
                            haptics.updateContinuous(
                                intensity: Float(intensityValue),
                                sharpness: Float(newValue)
                            )
                        }

                    HStack {
                        Text("Smooth")
                        Spacer()
                        Text("Sharp")
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Navigation

    private func nextScreen() {
        if let next = currentScreen.next {
            haptics.stop()
            currentScreen = next
        } else {
            haptics.stop()
            // Later you can route to your bar chart flow here
        }
    }

    private func previousScreen() {
        if let previous = currentScreen.previous {
            haptics.stop()
            currentScreen = previous
        }
    }

    private func intensityLabel(for value: Double) -> String {
        switch value {
        case 0..<0.33: return "Low"
        case 0.33..<0.66: return "Medium"
        default: return "High"
        }
    }
}

// MARK: - Screen Enum

enum IntroScreen: Int, CaseIterable {
    case intensityExamples
    case intensitySlider
    case sharpnessExamples
    case sharpnessSlider
    case combinations
    case bothSliders

    var title: String {
        switch self {
        case .intensityExamples:
            return "Feel the difference in vibration strength"
        case .intensitySlider:
            return "Adjust vibration strength"
        case .sharpnessExamples:
            return "Feel the difference in sharpness"
        case .sharpnessSlider:
            return "Adjust vibration sharpness"
        case .combinations:
            return "Explore combinations"
        case .bothSliders:
            return "Explore both controls"
        }
    }

    var subtitle: String {
        switch self {
        case .intensityExamples, .sharpnessExamples:
            return "Touch and hold each box to feel them."
        case .intensitySlider, .sharpnessSlider:
            return "Touch and hold the box, then move the slider."
        case .combinations:
            return "Compare how intensity and sharpness feel together."
        case .bothSliders:
            return "Touch and hold the box, then explore both sliders."
        }
    }

    var next: IntroScreen? {
        IntroScreen(rawValue: rawValue + 1)
    }

    var previous: IntroScreen? {
        IntroScreen(rawValue: rawValue - 1)
    }
}

// MARK: - Reusable Box

struct HapticTouchBox: View {
    let title: String
    let intensity: Double
    let sharpness: Double
    @ObservedObject var haptics: IntroHapticManager

    @State private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(Color(.systemGray6))
            .frame(width: 140, height: 140)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(pressing ? Color.blue : Color.gray.opacity(0.3), lineWidth: 2)
            )
            .scaleEffect(pressing ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: pressing)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !pressing {
                            pressing = true
                            haptics.startContinuous(
                                intensity: Float(intensity),
                                sharpness: Float(sharpness)
                            )
                        } else {
                            haptics.updateContinuous(
                                intensity: Float(intensity),
                                sharpness: Float(sharpness)
                            )
                        }
                    }
                    .onEnded { _ in
                        pressing = false
                        haptics.stop()
                    }
            )
            .accessibilityLabel("Haptic box")
            .accessibilityHint("Touch and hold to feel the vibration")
    }
}

// MARK: - Combination Card

struct CombinationCard: View {
    let title: String
    let intensity: Double
    let sharpness: Double
    @ObservedObject var haptics: IntroHapticManager

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.subheadline)
                .multilineTextAlignment(.center)

            HapticTouchBox(
                title: "",
                intensity: intensity,
                sharpness: sharpness,
                haptics: haptics
            )
            .frame(height: 110)
            .scaleEffect(0.72)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(16)
    }
}

// MARK: - Haptic Manager

final class IntroHapticManager: ObservableObject {
    private var engine: CHHapticEngine?
    private var player: CHHapticAdvancedPatternPlayer?

    init() {
        prepareHaptics()
    }

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            print("Failed to start haptic engine: \(error.localizedDescription)")
        }
    }

    func startContinuous(intensity: Float, sharpness: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        stop()

        let intensityParam = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: intensity
        )

        let sharpnessParam = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: sharpness
        )

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [intensityParam, sharpnessParam],
            relativeTime: 0,
            duration: 10
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            player = try engine?.makeAdvancedPlayer(with: pattern)
            try engine?.start()
            try player?.start(atTime: 0)
        } catch {
            print("Failed to play continuous haptic: \(error.localizedDescription)")
        }
    }

    func updateContinuous(intensity: Float, sharpness: Float) {
        guard let player else { return }

        let intensityDynamic = CHHapticDynamicParameter(
            parameterID: .hapticIntensityControl,
            value: intensity,
            relativeTime: 0
        )

        let sharpnessDynamic = CHHapticDynamicParameter(
            parameterID: .hapticSharpnessControl,
            value: sharpness,
            relativeTime: 0
        )

        do {
            try player.sendParameters([intensityDynamic, sharpnessDynamic], atTime: 0)
        } catch {
            print("Failed to update haptic parameters: \(error.localizedDescription)")
        }
    }

    func stop() {
        do {
            try player?.stop(atTime: 0)
            player = nil
        } catch {
            print("Failed to stop haptics: \(error.localizedDescription)")
        }
    }
}
