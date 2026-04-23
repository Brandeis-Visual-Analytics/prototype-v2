import SwiftUI
import CoreHaptics

struct ContinuousBubbleHapticView: View {

    struct Bubble: Identifiable {
        let id = UUID()
        let label: String
        let x: CGFloat   // 0...1
        let y: CGFloat   // 0...1
        let r: CGFloat   // 0...1 (relative radius)
    }

    // More than one bubble, and radii big enough to see.
    private let bubbles: [Bubble] = [
        .init(label: "A", x: 0.20, y: 0.75, r: 0.16),
        .init(label: "B", x: 0.55, y: 0.60, r: 0.22),
        .init(label: "C", x: 0.78, y: 0.28, r: 0.14),
        .init(label: "D", x: 0.33, y: 0.28, r: 0.18)
    ]

    // Which bubble edge is currently being touched (nil means none)
    @State private var activeID: UUID? = nil

    // Core Haptics engine (created once)
    @State private var engine: CHHapticEngine? = nil
    @State private var continuousPlayer: CHHapticAdvancedPatternPlayer? = nil

    // User-controlled parameters (0...1)
    @State private var intensity: Float = 0.8
    @State private var sharpness: Float = 0.8

    // Edge-only haptics: thickness of the “ring” around the circle edge (in points)
    @State private var edgeThickness: CGFloat = 18

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 16) {

                Text(activeLabel() ?? "Touch the edge of a bubble")
                    .font(.headline)
                    .foregroundColor(.black)

                // Sliders
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Haptic Intensity (strength)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)

                        Slider(value: $intensity, in: 0...1, step: 0.05)
                            .onChange(of: intensity) { _ in
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
                                updateContinuousHapticParameters()
                            }

                        Text(String(format: "Current value: %.2f", sharpness))
                            .font(.caption)
                            .foregroundColor(.black)
                    }

                    // Optional slider for the edge thickness
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Edge Thickness (ring width)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)

                        Slider(
                            value: Binding(
                                get: { Double(edgeThickness) },
                                set: { edgeThickness = CGFloat($0) }
                            ),
                            in: 6...40,
                            step: 2
                        )

                        Text("Current value: \(Int(edgeThickness)) pt")
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 24)

                // Chart-only geometry reader: drawing + hit testing share the same space
                GeometryReader { geo in
                    let padding: CGFloat = 16
                    let plot = CGRect(
                        x: padding,
                        y: padding,
                        width: geo.size.width - 2 * padding,
                        height: geo.size.height - 2 * padding
                    )

                    let minDim = min(plot.width, plot.height)

                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.black.opacity(0.25), lineWidth: 1)
                            .frame(width: plot.width, height: plot.height)
                            .position(x: plot.midX, y: plot.midY)

                        ForEach(bubbles) { b in
                            let center = bubbleCenter(b, in: plot)
                            let radius = bubbleRadius(b, minDim: minDim)

                            Circle()
                                .fill(Color.black.opacity(0.15))
                                .overlay(
                                    Circle()
                                        .stroke(Color.black, lineWidth: (activeID == b.id ? 3 : 1))
                                )
                                .frame(width: radius * 2, height: radius * 2)
                                .position(center)
                        }
                    }
                    .contentShape(Rectangle()) // make the whole plot draggable
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let id = hitTestBubbleEdge(
                                    point: g.location,
                                    plot: plot,
                                    minDim: minDim,
                                    edgeThickness: edgeThickness
                                )

                                if id != activeID {
                                    // entering a bubble edge from none
                                    if activeID == nil && id != nil {
                                        startContinuousHaptic()
                                    }

                                    // leaving bubble edges to none
                                    if activeID != nil && id == nil {
                                        stopContinuousHaptic()
                                    }

                                    activeID = id
                                }
                            }
                            .onEnded { _ in
                                stopContinuousHaptic()
                                activeID = nil
                            }
                    )
                }
                .frame(height: 320)
                .padding(.horizontal, 16)
            }
        }
        .onAppear { prepareHaptics() }
        .onDisappear {
            stopContinuousHaptic()
            engine?.stop(completionHandler: nil)
        }
    }

    // MARK: - Bubble geometry

    private func bubbleCenter(_ b: Bubble, in plot: CGRect) -> CGPoint {
        CGPoint(
            x: plot.minX + b.x * plot.width,
            y: plot.minY + (1 - b.y) * plot.height
        )
    }

    // Radius scales with plot size
    private func bubbleRadius(_ b: Bubble, minDim: CGFloat) -> CGFloat {
        return b.r * (minDim * 0.62)
    }

    private func activeLabel() -> String? {
        guard let id = activeID, let b = bubbles.first(where: { $0.id == id }) else { return nil }
        return "Touching edge of bubble \(b.label)"
    }

    // MARK: - Hit testing (EDGE ONLY)

    private func hitTestBubbleEdge(point: CGPoint,
                                   plot: CGRect,
                                   minDim: CGFloat,
                                   edgeThickness: CGFloat) -> UUID? {
        guard plot.contains(point) else { return nil }

        let halfBand = max(1, edgeThickness / 2)

        // If bubbles overlap, choose the edge you’re closest to
        var best: (id: UUID, edgeDelta: CGFloat)? = nil

        for b in bubbles {
            let c = bubbleCenter(b, in: plot)
            let r = bubbleRadius(b, minDim: minDim)
            let d = hypot(point.x - c.x, point.y - c.y)

            let delta = abs(d - r) // distance from circumference

            guard delta <= halfBand else { continue }

            if best == nil || delta < best!.edgeDelta {
                best = (b.id, delta)
            }
        }

        return best?.id
    }

    // MARK: - Haptics Setup

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()

            engine?.stoppedHandler = { _ in }
            engine?.resetHandler = {
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

        if continuousPlayer != nil { return }

        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))

        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: iVal)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sVal)

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
        do { try player.stop(atTime: 0) } catch { }
        continuousPlayer = nil
    }

    private func updateContinuousHapticParameters() {
        guard let player = continuousPlayer else { return }

        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))

        let dynamicParams = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: iVal, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sVal, relativeTime: 0)
        ]

        do { try player.sendParameters(dynamicParams, atTime: 0) } catch { }
    }
}
