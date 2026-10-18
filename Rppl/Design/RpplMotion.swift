import SwiftUI
import UIKit

/// `withAnimation` that skips the animation when Reduce Motion is on, so state changes still apply.
@MainActor
func withRpplAnimation<Result>(
    _ animation: Animation? = .default,
    _ body: () throws -> Result
) rethrows -> Result {
    try withAnimation(UIAccessibility.isReduceMotionEnabled ? nil : animation, body)
}

private struct RpplAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` that is off under Reduce Motion.
    func rpplAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(RpplAnimation(animation: animation, value: value))
    }
}
