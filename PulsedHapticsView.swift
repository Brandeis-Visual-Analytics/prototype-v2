import SwiftUI
import CoreHaptics
// A simple SwiftUI screen that draws a bar chart.
// When the user drags their finger over a bar, we detect which bar is under the finger,
// and we play a short haptic "tap" whenever the active bar changes.
struct PulsedHapticsView: View {
    // --- Data for the bar chart ---
    // Each value is between 0 and 1 and maps to a bar height.
    private let values: [CGFloat] = [0.2, 0.65, 0.4, 0.85, 0.55]
    // Tracks which bar index is currently being touched (nil = touching nothing).
    @State private var activeIndex: Int? = nil
    // --- Core Haptics engine ---
    // Core Haptics requires an engine object that we create once and keep around.
    @State private var engine: CHHapticEngine? = nil
    // --- User-adjustable haptic parameters ---
    // Core Haptics expects these values in the range 0...1.
    // Intensity: "how strong" the vibration feels.
    // Sharpness: "how crisp / clicky" the vibration feels.
    @State private var intensity: Float = 0.8
    @State private var sharpness: Float = 0.8
    var body: some View {
        GeometryReader { geo in
            // Layout constants for drawing the bars inside the screen.
            let padding: CGFloat = 24
            let innerW = geo.size.width - padding * 2
            let innerH = geo.size.height - padding * 2
            let gap: CGFloat = 12
            // Width of each bar so they fit evenly across the available width.
            let barW = (innerW - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 16) {
                    // Status text: shows which bar is currently active.
                    Text(activeIndex.map { "Touching bar \($0)" } ?? "Touch a bar")
                        .font(.headline)
                    // --- Haptic tuning UI ---
                    // Sliders allow the user to adjust haptic feel at runtime.
                    // Intensity = how strong the vibration feels.
                    // Sharpness = how crisp / click-like the vibration feels.
                    VStack(spacing: 16) {
                        // INTENSITY CONTROL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Haptic Intensity (strength)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black) // High contrast
                            Slider(value: $intensity, in: 0...1, step: 0.05)
                            Text(String(format: "Current value: %.2f", intensity))
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                        // SHARPNESS CONTROL
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Haptic Sharpness (crispness)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black) // High contrast
                            Slider(value: $sharpness, in: 0...1, step: 0.05)
                            Text(String(format: "Current value: %.2f", sharpness))
                                .font(.caption)
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.horizontal, padding)
                    // --- Bar chart drawing ---
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(values.indices, id: \.self) { i in
                            Rectangle()
                                .fill(Color.black)
                                .frame(width: barW, height: values[i] * innerH)
                        }
                    }
                    .frame(width: innerW, height: innerH, alignment: .bottom)
                    .padding(padding)
                    // contentShape(Rectangle()) makes the whole padded area “touchable,”
                    // not just the visible bars.
                    .contentShape(Rectangle())
                    // --- Gesture handling ---
                    // We use a DragGesture with minimumDistance = 0 so it behaves like
                    // a continuous touch/drag and updates as the finger moves.
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let p = g.location
                                // Find which bar (if any) is under the finger.
                                let idx = hitTest(
                                    point: p,
                                    size: geo.size,
                                    padding: padding,
                                    gap: gap,
                                    values: values
                                )
                                // Only trigger a haptic when the user enters a *new* bar.
                                // This prevents repeated vibrations while staying on the same bar.
                                if idx != activeIndex {
                                    activeIndex = idx
                                    if idx != nil { hapticTap() }
                                }
                            }
                            .onEnded { _ in
                                // User lifted their finger.
                                activeIndex = nil
                            }
                    )
                }
            }
            // Create and start the haptics engine once the view appears.
            .onAppear { prepareHaptics() }
        }
    }
    // Sets up the Core Haptics engine (only works on devices that support haptics).
    private func prepareHaptics() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            engine = nil
        }
    }
    // Plays a short transient haptic "tap" using the current slider settings.
    private func hapticTap() {
        guard let engine, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        // Clamp values just in case (ensures they're valid 0...1).
        let iVal = max(0, min(1, intensity))
        let sVal = max(0, min(1, sharpness))
        // These parameters define the feel of the haptic tap.
        let i = CHHapticEventParameter(parameterID: .hapticIntensity, value: iVal)
        let s = CHHapticEventParameter(parameterID: .hapticSharpness, value: sVal)
        // A transient event = a short single pulse (like a tap).
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [i, s],
            relativeTime: 0
        )
        do {
            // A pattern can contain multiple events; here we only use one.
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
        } catch {
            // If anything fails, we silently ignore for now.
        }
    }
    // Given a finger location, returns which bar index is being touched, or nil if none.
    // This is basically: compute each bar's rectangle and check if the touch point is inside it.
    private func hitTest(point: CGPoint,
                         size: CGSize,
                         padding: CGFloat,
                         gap: CGFloat,
                         values: [CGFloat]) -> Int? {
        let innerW = size.width - padding * 2
        let innerH = size.height - padding * 2
        guard innerW > 0, innerH > 0 else { return nil }
        // Convert global touch coordinates into the bar chart's internal coordinate system.
        let x = point.x - padding
        let y = point.y - padding
        // If outside the chart area, return nil.
        if x < 0 || y < 0 || x > innerW || y > innerH { return nil }
        let barW = (innerW - gap * CGFloat(values.count - 1)) / CGFloat(values.count)
        for i in values.indices {
            // Each bar starts at barX and extends upward based on barH.
            let barX = CGFloat(i) * (barW + gap)
            let barH = values[i] * innerH
            let barY = innerH - barH
            let rect = CGRect(x: barX, y: barY, width: barW, height: barH)
            if rect.contains(CGPoint(x: x, y: y)) {
                return i
            }
        }
        return nil
    }
}
