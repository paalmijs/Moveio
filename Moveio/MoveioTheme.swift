// iPhone target only
import SwiftUI
import UIKit

extension Color {
    /// A color that switches automatically between light and dark mode.
    init(light: Color, dark: Color) {
        self.init(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }
}

// MARK: - Fitness Clean design system
enum Theme {
    /// Profile > Appearance > High contrast
    static var highContrast: Bool { UserDefaults.standard.bool(forKey: "highContrast") }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    // Ring colors: a bit deeper in light mode so they stay readable on white
    static var move: Color {
        highContrast ? Color(light: rgb(0.78, 0.00, 0.20), dark: rgb(1.00, 0.30, 0.48))
                     : Color(light: rgb(0.90, 0.05, 0.27), dark: rgb(0.98, 0.07, 0.31))
    }
    static var exercise: Color {
        highContrast ? Color(light: rgb(0.20, 0.50, 0.00), dark: rgb(0.70, 1.00, 0.20))
                     : Color(light: rgb(0.35, 0.68, 0.00), dark: rgb(0.57, 0.89, 0.00))
    }
    static var stand: Color {
        highContrast ? Color(light: rgb(0.00, 0.42, 0.62), dark: rgb(0.20, 0.88, 1.00))
                     : Color(light: rgb(0.00, 0.60, 0.80), dark: rgb(0.00, 0.78, 0.95))
    }

    // Surfaces
    static var bg: Color {
        highContrast ? Color(light: Color(white: 0.86), dark: .black)
                     : Color(light: Color(white: 0.94), dark: .black)
    }
    static var card: Color {
        highContrast ? Color(light: .white, dark: Color(white: 0.15))
                     : Color(light: .white, dark: Color(white: 0.11))
    }
    static var border: Color { Color.primary.opacity(highContrast ? 0.40 : 0.06) }
}

// Rounded card that works in light and dark mode
func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c().padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Theme.border, lineWidth: Theme.highContrast ? 1.2 : 0.5))
        .fadeIn()
}

// Three concentric Apple Fitness style rings
struct TripleRing: View {
    let outer: Double, middle: Double, inner: Double
    var body: some View {
        ZStack {
            AnimatedRing(progress: outer, color: Theme.move, lineWidth: 16)
            AnimatedRing(progress: middle, color: Theme.exercise, lineWidth: 16).padding(19)
            AnimatedRing(progress: inner, color: Theme.stand, lineWidth: 16).padding(38)
        }
        .padding(8)
    }
}

// MARK: - Moveio logo (same shape as the app icon): a lowercase "m" in Inter Display Black with a dot above the last stem
struct MoveioLogo: View {
    var size: CGFloat = 96

    private var bg: Color { Color(light: .white, dark: Color(white: 0.055)) }
    private var fg: Color { Color(light: Color(white: 0.05), dark: .white) }

    private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * size, y: y * size) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(bg)
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)

            Path { p in
                p.move(to: pt(0.2295, 0.76))
                p.addLine(to: pt(0.3542, 0.76))
                p.addLine(to: pt(0.3542, 0.5711))
                p.addCurve(to: pt(0.3956, 0.5224), control1: pt(0.3542, 0.5412), control2: pt(0.3704, 0.5224))
                p.addCurve(to: pt(0.4377, 0.5711), control1: pt(0.4215, 0.5224), control2: pt(0.4377, 0.5412))
                p.addLine(to: pt(0.4377, 0.76))
                p.addLine(to: pt(0.5562, 0.76))
                p.addLine(to: pt(0.5562, 0.5711))
                p.addCurve(to: pt(0.5973, 0.5224), control1: pt(0.5562, 0.5412), control2: pt(0.5724, 0.5224))
                p.addCurve(to: pt(0.6397, 0.5711), control1: pt(0.6232, 0.5224), control2: pt(0.6397, 0.5412))
                p.addLine(to: pt(0.6397, 0.76))
                p.addLine(to: pt(0.7644, 0.76))
                p.addLine(to: pt(0.7644, 0.5399))
                p.addCurve(to: pt(0.6528, 0.4233), control1: pt(0.7644, 0.4691), control2: pt(0.7189, 0.4233))
                p.addCurve(to: pt(0.5462, 0.4919), control1: pt(0.6064, 0.4233), control2: pt(0.5627, 0.4461))
                p.addCurve(to: pt(0.4508, 0.4233), control1: pt(0.5331, 0.4458), control2: pt(0.4942, 0.4233))
                p.addCurve(to: pt(0.3492, 0.4953), control1: pt(0.4072, 0.4233), control2: pt(0.3676, 0.4458))
                p.addLine(to: pt(0.3492, 0.4308))
                p.addLine(to: pt(0.2295, 0.4308))
                p.closeSubpath()
            }
            .fill(fg)

            Circle().fill(fg)
                .frame(width: 0.1372 * size, height: 0.1372 * size)
                .position(pt(0.7019, 0.3086))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.06, y: size * 0.03)
    }
}
