import SwiftUI
import UIKit

/// Semantic colors for the upcoming project screens.
/// Nothing here is applied to the current UI, and reading a color does not write settings or project data.
enum ProjectUXColors {
    /// Grouped screen background. Follows the system appearance.
    static var screenBackground: Color { Color(.systemGroupedBackground) }

    /// Card surface above the screen background.
    static var cardSurface: Color { Color(.secondarySystemGroupedBackground) }

    /// Nested fill: badges, secondary chips, quiet blocks.
    static var secondarySurface: Color { Color(.tertiarySystemFill) }

    static var primaryText: Color { Color.primary }

    static var secondaryText: Color { Color.secondary }

    /// Hairline between rows.
    static var separator: Color { Color(.separator) }

    /// Quieter edge than `separator`. Still semantic, not a fixed gray.
    static var subtleBorder: Color { Color(.quaternarySystemFill) }

    /// Project accent for the new screens. Light matches the brand yellow.
    /// Dark stays system gold, so it does not turn white like `AccentYellow`.
    static var accentAction: Color { Color(uiColor: projectAccent) }

    /// Unfilled progress track. Gray in both appearances. Not used for a low percent.
    static var progressTrack: Color { Color(.quaternarySystemFill) }

    /// Work in progress. Same project accent, not red and not white in dark mode.
    static var progressActive: Color { Color(uiColor: projectAccent) }

    /// Finished work. System green, distinct from the accent.
    static var progressComplete: Color { Color.green }

    /// An issue note. Orange, not a recolor of the progress bar.
    static var issue: Color { Color.orange }

    /// A real overdue date or a critical failure. Not a low progress percent.
    static var overdue: Color { Color.red }

    /// Top photo fade so white title text stays readable. Independent of the app theme.
    static var coverScrimTop: Color { Color.black.opacity(0.45) }

    /// Stronger bottom fade behind the progress row and the cover actions.
    static var coverScrimBottom: Color { Color.black.opacity(0.72) }

    static var neutralBadgeBackground: Color { Color(.tertiarySystemFill) }

    static var neutralBadgeText: Color { Color.secondary }

    /// Resolved when the color is used. The closure receives the current traits and does not store them.
    private static let projectAccent = UIColor { traits in
        guard traits.userInterfaceStyle == .dark else {
            return UIColor(red: 1, green: 196.0 / 255.0, blue: 0, alpha: 1)
        }
        return .systemYellow
    }
}
