import SwiftUI

/// Compact DEMO training entry: yellow accent capsule + graduation cap.
/// Visible height matches a segmented filter; the hit target stays ≥44×44.
struct DemoTrainingCompactEntry: View {
    @ObservedObject private var training = DemoTrainingController.shared
    /// When false, only the cap icon is shown; VoiceOver still says «Обучение».
    var showsTitle: Bool = true

    var body: some View {
        Button {
            training.openMenu()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "graduationcap.fill")
                    .imageScale(.medium)
                if showsTitle {
                    Text("Обучение")
                        .lineLimit(1)
                        .minimumScaleFactor(1)
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(ProjectUXColors.onAccent)
            .padding(.horizontal, showsTitle ? 10 : 8)
            .padding(.vertical, 5)
            .background(ProjectUXColors.accentAction, in: Capsule())
            // Expand the tappable area without growing the visible capsule.
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Обучение")
        .accessibilityHint("Открывает меню туров обучения")
        .accessibilityIdentifier("demo.training.entry")
    }
}

private struct DemoTrainingFilterBarWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shared chrome: segmented filters + DEMO training on one compact row.
///
/// - Normal text: one horizontal row (title when width allows, else icon-only).
/// - Very large Dynamic Type on a narrow width: training may wrap to its own row.
/// - Outside DEMO: only the filter, full width — no empty training slot.
struct DemoTrainingFilterBar<FilterContent: View>: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Exact filter captions for the current tab — used only to decide wrap / icon-only.
    var filterTitles: [String] = ["Все", "Текущие", "Завершённые"]
    @ViewBuilder var filter: () -> FilterContent

    @State private var rowWidth: CGFloat = 0

    private var showsTraining: Bool {
        DemoTrainingPrototypeGate.isEnabled && store.isDemoMode
    }

    /// Width the segmented track needs so titles stay untruncated at the current Dynamic Type.
    private var minimumFilterTrackWidth: CGFloat {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        let font = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traits)
        let textWidth = filterTitles
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .reduce(CGFloat(0), +)
        // Segment chrome + inter-segment gaps (UISegmentedControl intrinsic padding).
        return textWidth + CGFloat(filterTitles.count) * 22 + 12
    }

    private let iconTrainingWidth: CGFloat = 44
    private let titledTrainingWidth: CGFloat = 108
    private let rowSpacing: CGFloat = 8

    /// Wrap training when keeping it in-row would force the system segmented control to truncate titles.
    private var wrapsTraining: Bool {
        guard showsTraining, rowWidth > 0 else { return false }
        if dynamicTypeSize.isAccessibilitySize { return true }
        return rowWidth - rowSpacing - iconTrainingWidth < minimumFilterTrackWidth
    }

    /// Full «Обучение» label only when the filter track still has room beside it.
    private var showsTrainingTitle: Bool {
        guard !wrapsTraining, rowWidth > 0 else { return true }
        return rowWidth - rowSpacing - titledTrainingWidth >= minimumFilterTrackWidth
    }

    var body: some View {
        Group {
            if showsTraining {
                if wrapsTraining {
                    VStack(alignment: .trailing, spacing: 6) {
                        filter()
                            .frame(maxWidth: .infinity, alignment: .leading)
                        DemoTrainingCompactEntry(showsTitle: true)
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        filter()
                            .frame(minWidth: 0, maxWidth: .infinity)
                        DemoTrainingCompactEntry(showsTitle: showsTrainingTitle)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            } else {
                filter()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: DemoTrainingFilterBarWidthKey.self, value: geo.size.width)
            }
        }
        .onPreferenceChange(DemoTrainingFilterBarWidthKey.self) { rowWidth = max($0, 0) }
    }
}

/// Profile (and any screen without filters): compact training only, DEMO-gated.
struct DemoTrainingStandaloneEntry: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        if DemoTrainingPrototypeGate.isEnabled && store.isDemoMode {
            HStack {
                Spacer(minLength: 0)
                DemoTrainingCompactEntry(showsTitle: true)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Legacy names (gallery / gradual call-site updates)

/// Gallery preview keeps the compact entry API under the old type name.
struct DemoTrainingEntryButton: View {
    var body: some View {
        DemoTrainingCompactEntry(showsTitle: true)
    }
}
