import SwiftUI
import CoreHaptics

// Continuous-haptics version of the bar-chart prototype.
// Behavior:
// - When the user touches ANY bar: start a continuous haptic.
// - While the finger stays on bars (even moving between bars): keep it playing.
// - When the finger leaves bars OR lifts up: stop the haptic.
// - Intensity & Sharpness are user-adjustable via sliders while the app runs.
//
// Notes for testing:
// - Use a *real iPhone* (continuous haptics often won't work in the simulator).
// - Intensity & Sharpness are Core Haptics "event parameters" in range 0...1.
struct ContinuousBarHapticView: View {

    // Bar heights (0...1)
    private let values: [CGFloat] = [0.2, 0.65, 0.4, 0.85, 0.55]

    // Which bar is currently being touched (nil means none)
    @State private var activeIndex: Int? = nil

    // Core Haptics engine (created once)
    @State private var engine: CHHapticEngine? = nil

    // A player we keep around so we can start/stop continuous haptics
    @State private var continuousPlayer: CHHapticAdvancedPatternPlayer? = nil

    // User-controlled parameters (0...1)
    @State private var intensity: Float = 0.8
    @State private var sharpness: Float = 0.8

    var body: some View {
        GeometryReader { geo in
            let padding: CGFloat = 24
            let innerW = geo.size.width - padding * 2
            let innerH = geo.size.height - padding * 2
            let gap: CGFloat = 12
            let barW = (innerW - gap * CGFloat(values.count - 1)) / CGFloat(values.count)

            ZStack {
                Color.white.ignoresSafeArea()

                VStack(spacing: 16) {

                    Text(activeIndex.map { "Touching bar \($0)" } ?? "Touch a bar")
                        .font(.headline)
                        .foregroundColor(.black)

                    // --- High-contrast slider UI (labels above sliders) ---
                    VStack(spacing: 16) {

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Haptic Intensity (strength)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)

                            Slider(value: $intensity, in: 0...1, step: 0.05)
                                .onChange(of: intensity) { _ in
                                    // If continuous haptic is currently playing, update it live.
                                    updateContinuousHapticParameters()
                                }

                            Text(String(format: "Current value: %.2f", intensity))
                                .font(.caption)
                                .foregroundColor(.black)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Haptic Sharpness (crispness)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)

                            Slider(value: $sharpness, in: 0...1, step: 0.05)
                                .onChange(of: sharpness) { _ in
                                    // If continuous haptic is currently playing, update it live.
                                    updateContinuousHapticParameters()
                                }

                            Text(String(format: "Current value: %.2f", sharpness))
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, padding)

                    // --- Bars ---
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(values.indices, id: \.self) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: barW, height: values[i] * innerH)
                        }
                    }
                    .frame(width: innerW, height: innerH, alignment: .bottom)
                    .padding(padding)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let p = g.location
                                let idx = hitTest(point: p,
                                                  size: geo.size,
                                                  padding: padding,
                                                  gap: gap,
                                                  values: values)

                                if idx != activeIndex {
                                    // If we are entering bars from "none", start continuous haptic.
                                    if activeIndex == nil && idx != nil {
                                        startContinuousHaptic()
                                    }

                                    // If we are leaving bars to "none", stop continuous haptic.
                                    if activeIndex != nil && idx == nil {
                                        stopContinuousHaptic()
                                    }

                                    activeIndex = idx
                                }
                            }
                            .onEnded { _ in
                                // Finger lifted: stop and reset.
                                stopContinuousHaptic()
                                activeIndex = nil
                            }
                    )
                }
            }
            .onAppear { prepareHaptics() }
            .onDisappear {
                // Clean stop when leaving the view
                stopContinuousHaptic()
                engine?.stop(completionHandler: nil)
            }
        }
    }

    // MARK: - Haptics Setup

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()

            // If the engine stops (e.g., app background), attempt restart later if needed.
            engine?.stoppedHandler = { _ in }
            engine?.resetHandler = {
                // On reset, try to restart the engine.
                do { try engine?.start() } catch { }
            }
        } catch {
            engine = nil
        }
    }

    // MARK: - Continuous Haptics Control

    private func startContinuousHaptic() {
        guard let engine,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        // Avoid starting multiple continuous players.
        if continuousPlayer != nil { return }

        // Clamp parameters to 0...1
        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))

        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: iVal)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sVal)

        // Continuous event must have a duration. We set it long and stop manually.
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [i, s],
            relativeTime: 0,
            duration: 60.0
        )

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            continuousPlayer = player
            try player.start(atTime: 0)
        } catch {
            continuousPlayer = nil
        }
    }

    private func stopContinuousHaptic() {
        guard let player = continuousPlayer else { return }
        do {
            try player.stop(atTime: 0)
        } catch { }
        continuousPlayer = nil
    }

    // Update intensity/sharpness while the continuous haptic is playing.
    // This uses dynamic parameters so we don't need to restart the haptic.
    private func updateContinuousHapticParameters() {
        guard let player = continuousPlayer else { return }

        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))

        let dynamicParams = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: iVal, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sVal, relativeTime: 0)
        ]

        do {
            try player.sendParameters(dynamicParams, atTime: 0)
        } catch { }
    }

    // MARK: - Hit Testing

    // Returns which bar index is under the finger (nil if none).
    private func hitTest(point: CGPoint,
                         size: CGSize,
                         padding: CGFloat,
                         gap: CGFloat,
                         values: [CGFloat]) -> Int? {
        let innerW = size.width - padding * 2
        let innerH = size.height - padding * 2
        guard innerW > 0, innerH > 0 else { return nil }

        // Convert touch to chart-local coordinates
        let x = point.x - padding
        let y = point.y - padding
        if x < 0 || y < 0 || x > innerW || y > innerH { return nil }

        let barW = (innerW - gap * CGFloat(values.count - 1)) / CGFloat(values.count)

        for i in values.indices {
            let barX = CGFloat(i) * (barW + gap)
            let barH = values[i] * innerH
            let barY = innerH - barH

            let rect = CGRect(x: barX, y: barY, width: barW, height: barH)
            if rect.contains(CGPoint(x: x, y: y)) { return i }
        }
        return nil
    }
}
