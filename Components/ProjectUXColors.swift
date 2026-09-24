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

    /// Card edge. Strengthens when Increase Contrast is on, and stays a separator otherwise.
    static var readableBorder: Color { Color(uiColor: projectReadableBorder) }

    /// Project accent for the new screens. Light matches the brand yellow.
    /// Dark stays system gold, so it does not turn white like `AccentYellow`.
    static var accentAction: Color { Color(uiColor: projectAccent) }

    /// Label on a filled accent. Stays near-black in both appearances, unlike `BrandBlack`.
    static var onAccent: Color {
        Color(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0)
    }

    /// Unfilled progress track. Quiet in the normal appearance, stronger when Increase Contrast is on.
    static var progressTrack: Color { Color(uiColor: projectProgressTrack) }

    /// Work in progress. Same project accent, not red and not white in dark mode.
    static var progressActive: Color { Color(uiColor: projectAccent) }

    /// Finished work. System green, distinct from the accent.
    static var progressComplete: Color { Color.green }

    /// An issue note. Orange, not a recolor of the progress bar.
    static var issue: Color { Color.orange }

    /// A real overdue date or a critical failure. Not a low progress percent.
    static var overdue: Color { Color.red }

    /// Top photo fade so white title text stays readable. Independent of the app theme.
    static var coverScrimTop: Color { Color.black.opacity(0.80) }

    /// Stronger bottom fade behind the progress row and the cover actions.
    static var coverScrimBottom: Color { Color.black.opacity(0.88) }

    static var neutralBadgeBackground: Color { Color(.tertiarySystemFill) }

    static var neutralBadgeText: Color { Color.secondary }

    /// Resolved when the color is used. The closure receives the current traits and does not store them.
    private static let projectAccent = UIColor { traits in
        guard traits.userInterfaceStyle == .dark else {
            return UIColor(red: 1, green: 196.0 / 255.0, blue: 0, alpha: 1)
        }
        return .systemYellow
    }

    /// Resolved when drawn. Increase Contrast uses the full separator; the normal edge stays quieter.
    private static let projectReadableBorder = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return .separator
        }
        return UIColor.separator.withAlphaComponent(0.35)
    }

    /// Empty track and timeline line. Separator in Increase Contrast, otherwise the quiet system fill.
    private static let projectProgressTrack = UIColor { traits in
        if traits.accessibilityContrast == .high {
            return .separator
        }
        return .quaternarySystemFill
    }
}

/// Short fill motion for the new progress bars. Markers, labels, and theme changes are not animated here.
enum ProjectProgressMotion {
    static let duration: TimeInterval = 0.25

    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

/// Russian phrases shared by the new project card, dashboard, and timeline.
enum ProjectUXCopy {
    static func remarksPhrase(_ count: Int) -> String {
        "\(count) \(plural(count, one: "замечание", few: "замечания", many: "замечаний"))"
    }

    static func dayWord(_ count: Int) -> String {
        plural(count, one: "день", few: "дня", many: "дней")
    }

    static func remainingDays(_ count: Int) -> String {
        "Осталось \(count) \(dayWord(count))"
    }

    static func overdueDays(_ count: Int) -> String {
        "Просрочено на \(count) \(dayWord(count))"
    }

    /// Short form used only when the full phrase does not fit. The period is intentional.
    static func compactRemainingDays(_ count: Int) -> String {
        "Осталось \(count) дн."
    }

    static func compactOverdueDays(_ count: Int) -> String {
        "Просрочено на \(count) дн."
    }

    private static func plural(_ count: Int, one: String, few: String, many: String) -> String {
        let value = abs(count)
        let mod100 = value % 100
        let mod10 = value % 10
        if (11...14).contains(mod100) { return many }
        if mod10 == 1 { return one }
        if (2...4).contains(mod10) { return few }
        return many
    }
}

/// Horizontal progress scale used by the new project screens. Only the filled width animates.
struct ProjectProgressBar: View {
    var fraction: Double
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(fraction, 0), 1) }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ProjectUXColors.progressTrack)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * clamped))
                    .animation(ProjectProgressMotion.animation(reduceMotion: reduceMotion), value: clamped)
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
