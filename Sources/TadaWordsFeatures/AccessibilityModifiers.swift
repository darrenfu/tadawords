import SwiftUI

#if os(iOS)
    import UIKit
#endif

extension View {
    /// Avoids applying `accessibilityHidden(false)` to a parent, which can
    /// override a deliberately hidden answer inside the view hierarchy.
    @ViewBuilder
    func hiddenFromAccessibility(when condition: Bool) -> some View {
        if condition {
            accessibilityHidden(true)
        } else {
            self
        }
    }
}

@MainActor
func announceForAccessibility(_ message: String) {
    #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: message)
    #endif
}
