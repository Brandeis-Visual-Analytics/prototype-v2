import SwiftUI
import CoreHaptics

struct ContinuousStackedBarHapticView: View {

    private let segments: [CGFloat] = [3, 2, 1]
    private let segLabels: [String] = ["A", "B", "C"]

    @State private var activeSeg: Int? = nil

    @State private var engine: CHHapticEngine? = nil
    @State private var continuousPlayer: CHHapticAdvancedPatternPlayer? = nil

    @State private var intensity: Float = 0.8
    @State private var sharpness: Float = 0.8

    // NEW: spacing between stacked segments
    @State private var segSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 16) {
            Text(activeSeg.map { "Touching segment \(segLabels[$0])" } ?? "Touch a segment")
                .font(.headline)
                .foregroundColor(.black)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Haptic Intensity (strength)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.black)
                    Slider(value: $intensity, in: 0...1, step: 0.05)
                        .onChange(of: intensity) { _, _ in updateContinuousHapticParameters() }
                    Text(String(format: "Current value: %.2f", intensity))
                        .font(.caption)
                        .foregroundColor(.black)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Haptic Sharpness (crispness)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.black)
                    Slider(value: $sharpness, in: 0...1, step: 0.05)
                        .onChange(of: sharpness) { _, _ in updateContinuousHapticParameters() }
                    Text(String(format: "Current value: %.2f", sharpness))
                        .font(.caption)
                        .foregroundColor(.black)
                }

                // NEW: spacing slider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Segment spacing (pixels)")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.black)
                    Slider(value: $segSpacing, in: 0...24, step: 1)
                    Text("Current value: \(Int(segSpacing))")
                        .font(.caption)
                        .foregroundColor(.black)
                }
            }
            .padding(.horizontal, 24)

            GeometryReader { geo in
                let padding: CGFloat = 16
                let plot = CGRect(
                    x: padding, y: padding,
                    width: geo.size.width - 2*padding,
                    height: geo.size.height - 2*padding
                )

                let total: CGFloat = max(segments.reduce(0, +), 0.0001)

                let barW = min(plot.width * 0.35, 120)
                let x0 = plot.midX - barW / 2

                // ✅ Single source of truth: rects used for BOTH draw & hit-test
                let rects: [(idx: Int, rect: CGRect)] = stackedRects(
                    segments: segments,
                    total: total,
                    plot: plot,
                    x0: x0,
                    barW: barW,
                    spacing: segSpacing
                )

                ZStack {
                    Color.white

                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black.opacity(0.25), lineWidth: 1)
                        .frame(width: plot.width, height: plot.height)
                        .position(x: plot.midX, y: plot.midY)

                    ForEach(rects, id: \.idx) { item in
                        let s = item.idx
                        let rect = item.rect

                        Rectangle()
                            .fill(Color.black.opacity(0.15))
                            .overlay(
                                Rectangle().stroke(
                                    Color.black,
                                    lineWidth: (activeSeg == s) ? 3 : 1
                                )
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { g in
                            let hit = hitTest(point: g.location, rects: rects)
                            if hit != activeSeg {
                                if activeSeg == nil && hit != nil { startContinuousHaptic() }
                                if activeSeg != nil && hit == nil { stopContinuousHaptic() }
                                activeSeg = hit
                            }
                        }
                        .onEnded { _ in
                            stopContinuousHaptic()
                            activeSeg = nil
                        }
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 16)
        }
        .background(Color.white.ignoresSafeArea())
        .onAppear { prepareHaptics() }
        .onDisappear {
            stopContinuousHaptic()
            engine?.stop(completionHandler: nil)
        }
    }

    // MARK: - Geometry helpers

    /// Builds stacked segment rects that:
    /// - fill the plot height
    /// - only put spacing BETWEEN segments (no extra top/bottom shrink)
    private func stackedRects(segments: [CGFloat],
                              total: CGFloat,
                              plot: CGRect,
                              x0: CGFloat,
                              barW: CGFloat,
                              spacing: CGFloat) -> [(idx: Int, rect: CGRect)] {

        let n = segments.count
        let totalGaps = max(0, CGFloat(n - 1)) * spacing
        let usableH = max(0, plot.height - totalGaps)

        var out: [(Int, CGRect)] = []
        var yCursor = plot.maxY

        for s in segments.indices {
            let frac = max(segments[s], 0) / total
            let h = frac * usableH

            let rect = CGRect(
                x: x0,
                y: yCursor - h,
                width: barW,
                height: h
            )

            out.append((s, rect))

            // move up by this segment + one inter-segment gap (except after last)
            yCursor -= h
            if s != segments.indices.last {
                yCursor -= spacing
            }
        }

        return out
    }

    // MARK: - Hit testing

    private func hitTest(point: CGPoint, rects: [(idx: Int, rect: CGRect)]) -> Int? {
        for item in rects {
            if item.rect.contains(point) { return item.idx }
        }
        return nil
    }

    // MARK: - Haptics

    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
            engine?.stoppedHandler = { _ in }
            engine?.resetHandler = { do { try engine?.start() } catch { } }
        } catch { engine = nil }
    }

    private func startContinuousHaptic() {
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        if continuousPlayer != nil { return }

        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))

        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: iVal)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sVal)

        let event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [i, s],
                                  relativeTime: 0,
                                  duration: 60.0)
        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makeAdvancedPlayer(with: pattern)
            continuousPlayer = player
            try player.start(atTime: 0)
        } catch { continuousPlayer = nil }
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

        let params = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: iVal, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sVal, relativeTime: 0)
        ]
        do { try player.sendParameters(params, atTime: 0) } catch { }
    }
}
