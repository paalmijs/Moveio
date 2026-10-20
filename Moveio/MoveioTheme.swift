// iPhone target only (new file)
import SwiftUI

// MARK: - Fitness Clean design system
enum Theme {
    static let move     = Color(red: 0.98, green: 0.07, blue: 0.31)   // red ring
    static let exercise = Color(red: 0.57, green: 0.89, blue: 0.00)   // green ring
    static let stand    = Color(red: 0.00, green: 0.78, blue: 0.95)   // cyan ring
    static let card = Color(.secondarySystemGroupedBackground)
    static let bg   = Color(.systemGroupedBackground)
}

// White (light mode) / dark gray (dark mode) rounded card
func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
    c().padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
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
