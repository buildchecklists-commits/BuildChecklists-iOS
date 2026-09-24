import SwiftUI

/// Compact dashboard actions. Destinations and handlers stay with the caller.
struct ProjectQuickActions<PlanDestination: View, ExpensesDestination: View, IssuesDestination: View>: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let openFiles: () -> Void
    let openContacts: () -> Void
    let exportProjectPDF: () -> Void
    let openChecklistReport: () -> Void
    @ViewBuilder var planDestination: () -> PlanDestination
    @ViewBuilder var expensesDestination: () -> ExpensesDestination
    @ViewBuilder var issuesDestination: () -> IssuesDestination

    private let actionSlots = Array(QuickActionSlot.allCases)
    @State private var gridHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрые действия")
                .font(.headline)
                .foregroundStyle(ProjectUXColors.primaryText)
                .accessibilityAddTraits(.isHeader)

            // Ordinary rows, not a custom Layout. Layout children were visited
            // after the timeline. Row order here is the VoiceOver order.
            GeometryReader { proxy in
                actionRows(width: proxy.size.width)
                    .fixedSize(horizontal: false, vertical: true)
                    .background {
                        GeometryReader { grid in
                            Color.clear.preference(key: QuickActionHeightKey.self, value: grid.size.height)
                        }
                    }
            }
            .frame(height: gridHeight)
        }
        .onPreferenceChange(QuickActionHeightKey.self) { gridHeight = max($0, 44) }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        }
    }

    private func actionRows(width: CGFloat) -> some View {
        let metrics = ProjectQuickActionMetrics(dynamicTypeSize: dynamicTypeSize)
        let spacing: CGFloat = 8
        let columns = max(metrics.columns(for: max(width, 1)), 1)
        let itemWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let rowCount = (actionSlots.count + columns - 1) / columns
        return VStack(spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                let start = row * columns
                let count = min(columns, actionSlots.count - start)
                HStack(spacing: spacing) {
                    if count < columns { Spacer(minLength: 0) }
                    ForEach(0..<count, id: \.self) { offset in
                        actionSlot(actionSlots[start + offset])
                            .frame(width: max(itemWidth, 44), alignment: .top)
                    }
                    if count < columns { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func actionSlot(_ slot: QuickActionSlot) -> some View {
        switch slot {
        case .plan:
            actionLink(
                title: "План",
                accessibilityLabel: "План. Сроки текущего проекта",
                systemImage: "calendar",
                identifier: "project.quickAction.plan",
                destination: planDestination
            )
        case .expenses:
            actionLink(
                title: "Расходы",
                accessibilityLabel: "Расходы. Экран расходов текущего проекта",
                systemImage: "creditcard",
                identifier: "project.quickAction.expenses",
                destination: expensesDestination
            )
        case .files:
            actionButton(
                title: "Файлы",
                accessibilityLabel: "Файлы. Фото, документы и PDF проекта",
                systemImage: "folder.fill",
                identifier: "project.quickAction.files",
                action: openFiles
            )
        case .contacts:
            actionButton(
                title: "Контакты",
                accessibilityLabel: "Контакты. Список контактов проекта",
                systemImage: "person.2.fill",
                identifier: "project.quickAction.contacts",
                action: openContacts
            )
        case .issues:
            actionLink(
                title: "Замечания",
                accessibilityLabel: "Замечания. Список замечаний проекта",
                systemImage: "exclamationmark.triangle",
                identifier: "project.quickAction.issues",
                destination: issuesDestination
            )
        case .projectPDF:
            actionButton(
                title: "PDF проекта",
                accessibilityLabel: "PDF проекта. Сводка по объекту, расходам и чек-листам",
                systemImage: "doc.richtext",
                identifier: "project.quickAction.projectPDF",
                action: exportProjectPDF
            )
        case .checklistPDF:
            actionButton(
                title: "PDF чек-листов",
                accessibilityLabel: "PDF чек-листов. Настройки отчёта по рабочим чек-листам",
                systemImage: "checklist",
                identifier: "project.quickAction.checklistPDF",
                action: openChecklistReport
            )
        }
    }

    private func actionLink<Destination: View>(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String,
        destination: () -> Destination
    ) -> some View {
        ZStack {
            NavigationLink(destination: destination) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ProjectQuickActionButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)

            actionFace(title: title, systemImage: systemImage)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func actionButton(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        ZStack {
            Button(action: action) {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ProjectQuickActionButtonStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(identifier)

            actionFace(title: title, systemImage: systemImage)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }

    private func actionFace(title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(ProjectUXColors.accentAction)
                .accessibilityHidden(true)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(ProjectUXColors.primaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private enum QuickActionSlot: Int, CaseIterable {
    case plan, expenses, files, contacts, issues, projectPDF, checklistPDF
}

private struct QuickActionHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 44
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ProjectQuickActionMetrics {
    var dynamicTypeSize: DynamicTypeSize

    func columns(for width: CGFloat) -> Int {
        if dynamicTypeSize.isAccessibilitySize {
            if width >= 640 { return 3 }
            if width >= 420 { return 2 }
            return 1
        }
        if dynamicTypeSize >= .xxxLarge {
            if width >= 680 { return 4 }
            if width >= 300 { return 2 }
            return 1
        }
        // Seven across once the grid itself is wide enough to keep captions readable.
        // A 640 pt column leaves about 580 pt here. Narrower widths keep the phone grid.
        if width >= 520 { return 7 }
        if width >= 324 { return 4 }
        return 3
    }
}

private struct ProjectQuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? ProjectUXColors.secondarySurface
                            : ProjectUXColors.secondarySurface.opacity(0.55)
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
