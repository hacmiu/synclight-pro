import SwiftUI

/// A horizontal gradient slider used for the colour controls. Dragging across
/// the bar produces a value in 0..1. The track is filled with `colors` (left →
/// right) and the thumb is drawn with `thumbColor` (evaluated at the current
/// value, so callers can show the exact selected colour).
///
/// This mirrors the original app's `<AlphaPicker color width="100%">` bar for
/// hue, and is reused for saturation.
struct GradientSlider: View {
    @Binding var value: Double        // 0..1
    let colors: [Color]
    let thumbColor: Color
    var onChange: (() -> Void)? = nil

    private let thumbSize: CGFloat = 26

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let travel = max(width - thumbSize, 1)
            let x = CGFloat(min(max(value, 0), 1)) * travel

            ZStack(alignment: .leading) {
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 16)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(maxHeight: .infinity, alignment: .center)

                Circle()
                    .fill(thumbColor)
                    .overlay(Circle().stroke(.white, lineWidth: 3).shadow(radius: 2))
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: x)
            }
            .frame(height: thumbSize)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let clamped = min(max((v.location.x - thumbSize / 2) / travel, 0), 1)
                        value = Double(clamped)
                        onChange?()
                    }
            )
        }
        .frame(height: thumbSize)
    }
}

/// Convenience: full-hue rainbow slider.
struct HueSlider: View {
    @Binding var hue: Double          // 0..1
    var onChange: (() -> Void)? = nil

    private var rainbow: [Color] {
        stride(from: 0.0, through: 1.0, by: 1.0 / 6.0)
            .map { Color(hue: $0, saturation: 1, brightness: 1) }
    }

    var body: some View {
        GradientSlider(
            value: $hue,
            colors: rainbow,
            thumbColor: Color(hue: hue, saturation: 1, brightness: 1),
            onChange: onChange
        )
    }
}
