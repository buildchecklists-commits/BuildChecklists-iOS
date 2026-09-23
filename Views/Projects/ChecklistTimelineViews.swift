import SwiftUI

/// Read-only summary of one checklist pack.
/// `fraction` matches the dashboard rule: `ok / all saved items`, empty pack is 0.
struct ChecklistPackMeasurement: Equatable {
    var fraction: Double
    var done: Int
    var total: Int
    var issueCount: Int

    static func measure(_ stages: [Stage]?) -> ChecklistPackMeasurement {
        guard let stages, !stages.isEmpty else {
            return ChecklistPackMeasurement(fraction: 0, done: 0, total: 0, issueCount: 0)
        }

        let items = stages.flatMap(\.items)
        guard !items.isEmpty else {
            return ChecklistPackMeasurement(fraction: 0, done: 0, total: 0, issueCount: 0)
        }

        let done = items.filter { $0.status == .ok }.count
        let issueCount = items.filter { $0.status == .issue }.count
        return ChecklistPackMeasurement(
            fraction: Double(done) / Double(items.count),
            done: done,
            total: items.count,
            issueCount: issueCount
        )
    }

    var clampedFraction: Double { min(max(fraction, 0), 1) }

    var percent: Int { Int((clampedFraction * 100).rounded()) }

    var tone: ChecklistProgressTone {
        ChecklistProgressTone(completedCount: done, totalCount: total)
    }

    var countText: String {
        total == 0 ? "Ещё не начато" : "\(done) из \(total)"
    }

    /// Same Russian plural as the issues list. Count is shown only when it is greater than zero.
    static func remarksPhrase(_ count: Int) -> String {
        let mod100 = count % 100
        let mod10 = count % 10
        let word: String
        if (11...14).contains(mod100) {
            word = "замечаний"
        } else if mod10 == 1 {
            word = "замечание"
        } else if (2...4).contains(mod10) {
            word = "замечания"
        } else {
            word = "замечаний"
        }
        return "\(count) \(word)"
    }

    func accessibilityLabel(title: String) -> String {
        var parts = ["\(title), \(percent) процентов"]
        if total == 0 {
            parts.append("ещё не начато")
        } else {
            parts.append("\(done) из \(total) выполнено")
        }
        if issueCount > 0 {
            parts.append(Self.remarksPhrase(issueCount))
        }
        return parts.joined(separator: ", ")
    }
}

enum ChecklistProgressTone: Equatable {
    case notStarted
    case active
    case complete

    /// Green only when every item is done. An empty pack is never complete.
    init(completedCount: Int, totalCount: Int) {
        if totalCount > 0, completedCount == totalCount {
            self = .complete
        } else if totalCount > 0, completedCount > 0 {
            self = .active
        } else {
            self = .notStarted
        }
    }

    /// Fallback for a view that has a normalized fraction and no item counts.
    /// Complete only at exactly 1, so 0.999 stays active.
    init(fraction: Double) {
        let clamped = min(max(fraction, 0), 1)
        if clamped == 1 {
            self = .complete
        } else if clamped > 0 {
            self = .active
        } else {
            self = .notStarted
        }
    }

    var color: Color {
        switch self {
        case .notStarted:
            return ProjectUXColors.progressTrack
        case .active:
            return ProjectUXColors.progressActive
        case .complete:
            return ProjectUXColors.progressComplete
        }
    }
}

/// One pack in the project timeline. The whole row opens the existing pack screen.
struct ChecklistPackTimelineRow<Destination: View>: View {
    let title: String
    let subtitle: String
    let measurement: ChecklistPackMeasurement
    var showsConnector: Bool
    var accessibilityIdentifier: String
    let destination: () -> Destination

    private let railWidth: CGFloat = 22
    private let connectorGap: CGFloat = 18

    var body: some View {
        NavigationLink(destination: destination()) {
            ChecklistPackTimelineLabel(
                title: title,
                subtitle: subtitle,
                measurement: measurement,
                showsConnector: showsConnector,
                railWidth: railWidth,
                connectorGap: connectorGap
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(measurement.accessibilityLabel(title: title))
        .accessibilityHint("Открывает чек-лист пакета")
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }
}

/// Visual row. The rail is a background of this view, so its height is the laid-out card plus the gap to the next card.
private struct ChecklistPackTimelineLabel: View {
    let title: String
    let subtitle: String
    let measurement: ChecklistPackMeasurement
    let showsConnector: Bool
    let railWidth: CGFloat
    let connectorGap: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Color.clear
                .frame(width: railWidth)
                .accessibilityHidden(true)

            ChecklistPackCard(
                title: title,
                subtitle: subtitle,
                measurement: measurement
            )
        }
        .padding(.bottom, showsConnector ? connectorGap : 0)
        .background(alignment: .topLeading) {
            ChecklistTimelineRail(
                fraction: measurement.clampedFraction,
                tone: measurement.tone
            )
                .frame(width: railWidth)
                .accessibilityHidden(true)
        }
    }
}

/// Gray track for the full measured height. Color fill is the pack percent, from the marker downward.
private struct ChecklistTimelineRail: View {
    var fraction: Double
    var tone: ChecklistProgressTone

    private let markerSize: CGFloat = 16
    private let trackWidth: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = max(0, proxy.size.height - markerSize)
            let fillHeight = tone == .notStarted ? 0 : trackHeight * min(max(fraction, 0), 1)

            VStack(spacing: 0) {
                marker(tone)
                    .frame(width: markerSize, height: markerSize)

                ZStack(alignment: .top) {
                    Capsule()
                        .fill(ProjectUXColors.progressTrack)
                        .frame(width: trackWidth, height: trackHeight)
                    if fillHeight > 0 {
                        Capsule()
                            .fill(tone.color)
                            .frame(width: trackWidth, height: fillHeight)
                    }
                }
                .frame(width: markerSize, height: trackHeight, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func marker(_ tone: ChecklistProgressTone) -> some View {
        switch tone {
        case .complete:
            Circle()
                .fill(ProjectUXColors.progressComplete)
                .overlay {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
        case .active:
            Circle()
                .fill(ProjectUXColors.progressActive)
        case .notStarted:
            Circle()
                .strokeBorder(ProjectUXColors.secondaryText.opacity(0.55), lineWidth: 2)
                .background(Circle().fill(ProjectUXColors.cardSurface))
        }
    }
}

private struct ChecklistPackCard: View {
    let title: String
    let subtitle: String
    let measurement: ChecklistPackMeasurement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChecklistTitleRow(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .multilineTextAlignment(.leading)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .accessibilityHidden(true)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ProjectUXColors.secondaryText)
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(measurement.countText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ProjectUXColors.primaryText)
                Text("·")
                    .font(.caption)
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .accessibilityHidden(true)
                Text("\(measurement.percent)%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .monospacedDigit()
            }

            if measurement.issueCount > 0 {
                Text(ChecklistPackMeasurement.remarksPhrase(measurement.issueCount))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.issue)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ChecklistPackProgressBar(
                fraction: measurement.clampedFraction,
                tone: measurement.tone
            )
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(ProjectUXColors.cardSurface)
        }
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// Gives the title the width that remains beside the disclosure icon, so a long name wraps instead of truncating.
private struct ChecklistTitleRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let available = proposal.width ?? (subviews[0].sizeThatFits(.unspecified).width + spacing + trailing.width)
        let leadingWidth = max(0, available - spacing - trailing.width)
        let leading = subviews[0].sizeThatFits(ProposedViewSize(width: leadingWidth, height: nil))
        return CGSize(width: available, height: max(leading.height, trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let leadingWidth = max(0, bounds.width - spacing - trailing.width)
        let leading = subviews[0].sizeThatFits(ProposedViewSize(width: leadingWidth, height: nil))
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            proposal: ProposedViewSize(width: leadingWidth, height: leading.height)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.maxX - trailing.width, y: bounds.minY + 2),
            proposal: ProposedViewSize(width: trailing.width, height: trailing.height)
        )
    }
}

private struct ChecklistPackProgressBar: View {
    var fraction: Double
    var tone: ChecklistProgressTone

    var body: some View {
        let clamped = min(max(fraction, 0), 1)

        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ProjectUXColors.progressTrack)
                if clamped > 0 {
                    Capsule()
                        .fill(tone.color)
                        .frame(width: proxy.size.width * clamped)
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
