import SwiftUI
import CoreHaptics

struct ContinuousPieHapticView: View {

    // Data
    private let values: [CGFloat] = [30, 20, 25, 25]
    private let labels: [String] = ["A", "B", "C", "D"]

    // UI toggles
    @State private var isDonut: Bool = true

    //  Gap between slices (VISUAL + HIT-TEST) in degrees
    @State private var gapDegrees: Double = 6.0

    // NEW: radial separation (pushes slices outward) WITHOUT cutting off the tip
    @State private var separation: CGFloat = 8.0

    // State
    @State private var activeIndex: Int? = nil
    @State private var engine: CHHapticEngine? = nil
    @State private var continuousPlayer: CHHapticAdvancedPatternPlayer? = nil

    // Sliders
    @State private var intensity: Float = 0.8
    @State private var sharpness: Float = 0.8

    // Cached slice angles (computed from values)
    private var segs: [(start: CGFloat, end: CGFloat)] { sliceAngles() }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 16) {

                Text(activeIndex.map { "Touching slice \(labels[$0])" } ?? "Touch a slice")
                    .font(.headline)
                    .foregroundColor(.black)

                // toggles
                VStack(spacing: 12) {
                    Toggle("Donut (hollow)", isOn: $isDonut)
                        .foregroundColor(.black)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Slice gap (degrees)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)

                        Slider(value: $gapDegrees, in: 0...14, step: 1)

                        Text("Current value: \(Int(gapDegrees))°")
                            .font(.caption)
                            .foregroundColor(.black)
                    }

                    // NEW: separation slider
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Slice separation (pixels)")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.black)

                        Slider(value: $separation, in: 0...18, step: 1)

                        Text("Current value: \(Int(separation))")
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 24)

                // intensity/sharpness
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Haptic Intensity (strength)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.black)
                        Slider(value: $intensity, in: 0...1, step: 0.05)
                            .onChange(of: intensity) { _ in updateContinuousHapticParameters() }
                        Text(String(format: "Current value: %.2f", intensity))
                            .font(.caption)
                            .foregroundColor(.black)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Haptic Sharpness (crispness)")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.black)
                        Slider(value: $sharpness, in: 0...1, step: 0.05)
                            .onChange(of: sharpness) { _ in updateContinuousHapticParameters() }
                        Text(String(format: "Current value: %.2f", sharpness))
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }
                .padding(.horizontal, 24)

                GeometryReader { geo in
                    let size = min(geo.size.width, geo.size.height)
                    let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

                    // ✅ IMPORTANT FIX:
                    // When we "separate" slices by moving them outward, we must reduce the drawable radius
                    // so the tip stays inside the chart bounds (no clipping / no cut-off).
                    let baseOuterR = size * 0.38
                    let outerR = max(0, baseOuterR - separation)   // <-- key line
                    let innerR = isDonut ? outerR * 0.55 : 0

                    ZStack {
                        ForEach(segs.indices, id: \.self) { i in
                            let seg = segs[i]

                            // Mid-angle for this slice (use un-gapped angles so offset remains stable)
                            let mid = normalizeAngle((seg.start + seg.end) / 2)

                            // Offset outward along the bisector to create separation
                            let dx = cos(mid) * separation
                            let dy = sin(mid) * separation

                            PieWedgeShape(
                                start: seg.start,
                                end: seg.end,
                                innerRadius: innerR,
                                outerRadius: outerR,
                                gapRadians: CGFloat(gapDegrees) * .pi / 180.0
                            )
                            .fill(Color.black.opacity(0.15))
                            .overlay(
                                PieWedgeShape(
                                    start: seg.start,
                                    end: seg.end,
                                    innerRadius: innerR,
                                    outerRadius: outerR,
                                    gapRadians: CGFloat(gapDegrees) * .pi / 180.0
                                )
                                .stroke(Color.black, lineWidth: (activeIndex == i ? 3 : 1))
                            )
                            // Apply the separation offset per-slice
                            .offset(x: dx, y: dy)
                        }
                    }
                    .frame(width: size, height: size)
                    // Ensure touch locations are in the same coordinate space as the chart
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .local)
                            .onChanged { g in
                                let idx = hitTestPie(
                                    point: g.location,
                                    center: CGPoint(x: size / 2, y: size / 2),
                                    innerR: innerR,
                                    outerR: outerR,
                                    segs: segs,
                                    gapRadians: CGFloat(gapDegrees) * .pi / 180.0,
                                    separation: separation
                                )

                                if idx != activeIndex {
                                    if activeIndex == nil && idx != nil { startContinuousHaptic() }
                                    if activeIndex != nil && idx == nil { stopContinuousHaptic() }
                                    activeIndex = idx
                                }
                            }
                            .onEnded { _ in
                                stopContinuousHaptic()
                                activeIndex = nil
                            }
                    )
                    .position(x: center.x, y: center.y)
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

    // MARK: - Slice math

    private func sliceAngles() -> [(start: CGFloat, end: CGFloat)] {
        let total = values.reduce(0, +)
        var acc: CGFloat = 0
        var out: [(CGFloat, CGFloat)] = []
        for v in values {
            let frac = v / total
            let s = acc * 2 * .pi
            acc += frac
            let e = acc * 2 * .pi
            out.append((s, e))
        }
        return out
    }

    // MARK: - Hit testing

    private func normalizeAngle(_ a: CGFloat) -> CGFloat {
        var x = a
        while x < 0 { x += 2 * .pi }
        while x >= 2 * .pi { x -= 2 * .pi }
        return x
    }

    /// Angle test matches draw: each slice is shrunk by gap/2 on both sides.
    /// Note: This keeps YOUR hit-testing model unchanged (touch anywhere in the ring)
    /// even though slices are visually offset. If you ever want “per-slice offset hit testing”
    /// we can add that, but this matches your current structure.
    /// Hit-test that matches draw:
    /// - slices are shrunk by gap/2
    /// - slices are offset outward by `separation` along their mid-angle
    private func hitTestPie(point: CGPoint,
                            center: CGPoint,
                            innerR: CGFloat,
                            outerR: CGFloat,
                            segs: [(start: CGFloat, end: CGFloat)],
                            gapRadians: CGFloat,
                            separation: CGFloat) -> Int? {

        // Normalize once helper
        func inAngleRange(_ a: CGFloat, _ start: CGFloat, _ end: CGFloat) -> Bool {
            // assumes both are normalized to [0, 2pi)
            if start <= end { return a >= start && a < end }
            // wrap-around case
            return a >= start || a < end
        }

        for i in segs.indices {
            // Apply the same gap shrink used for drawing
            let a0Raw = segs[i].start + gapRadians / 2
            let a1Raw = segs[i].end   - gapRadians / 2
            guard a1Raw > a0Raw else { continue }

            // Mid-angle (use original segment bounds so offset direction is stable)
            let mid = normalizeAngle((segs[i].start + segs[i].end) / 2)

            // This slice is drawn offset outward by (dx, dy)
            let dxOff = cos(mid) * separation
            let dyOff = sin(mid) * separation

            // So for hit-testing, shift the center the same way
            let sliceCenter = CGPoint(x: center.x + dxOff, y: center.y + dyOff)

            // Radial test relative to the shifted center
            let dx = point.x - sliceCenter.x
            let dy = point.y - sliceCenter.y
            let r = hypot(dx, dy)
            guard r <= outerR, r >= innerR else { continue }

            // Angular test relative to the shifted center
            let a = normalizeAngle(atan2(dy, dx))
            let a0 = normalizeAngle(a0Raw)
            let a1 = normalizeAngle(a1Raw)

            if inAngleRange(a, a0, a1) { return i }
        }

        return nil
    }

    // MARK: - Haptics setup & control

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

        let params = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: iVal, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sVal, relativeTime: 0)
        ]
        do { try player.sendParameters(params, atTime: 0) } catch { }
    }
}

// MARK: - Pie wedge shape (same file)
private struct PieWedgeShape: Shape {
    let start: CGFloat
    let end: CGFloat
    let innerRadius: CGFloat
    let outerRadius: CGFloat
    let gapRadians: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)

        let a0 = start + gapRadians / 2
        let a1 = end - gapRadians / 2
        guard a1 > a0 else { return Path() }

        var p = Path()

        if innerRadius <= 0.001 {
            // filled slice (sharp tip at center ✅)
            p.move(to: c)
            p.addArc(
                center: c,
                radius: outerRadius,
                startAngle: .radians(a0),
                endAngle: .radians(a1),
                clockwise: false
            )
            p.closeSubpath()
        } else {
            // donut slice
            p.addArc(
                center: c,
                radius: outerRadius,
                startAngle: .radians(a0),
                endAngle: .radians(a1),
                clockwise: false
            )
            p.addArc(
                center: c,
                radius: innerRadius,
                startAngle: .radians(a1),
                endAngle: .radians(a0),
                clockwise: true
            )
            p.closeSubpath()
        }

        return p
    }
}
