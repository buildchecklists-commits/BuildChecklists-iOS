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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрые действия")
                .font(.headline)
                .foregroundStyle(ProjectUXColors.primaryText)
                .accessibilityAddTraits(.isHeader)

            ProjectQuickActionGrid(metrics: ProjectQuickActionMetrics(dynamicTypeSize: dynamicTypeSize)) {
                actionLink(
                    title: "План",
                    accessibilityLabel: "План. Сроки текущего проекта",
                    systemImage: "calendar",
                    identifier: "project.quickAction.plan",
                    destination: planDestination
                )
                actionLink(
                    title: "Расходы",
                    accessibilityLabel: "Расходы. Экран расходов текущего проекта",
                    systemImage: "creditcard",
                    identifier: "project.quickAction.expenses",
                    destination: expensesDestination
                )
                actionButton(
                    title: "Файлы",
                    accessibilityLabel: "Файлы. Фото, документы и PDF проекта",
                    systemImage: "folder.fill",
                    identifier: "project.quickAction.files",
                    action: openFiles
                )
                actionButton(
                    title: "Контакты",
                    accessibilityLabel: "Контакты. Список контактов проекта",
                    systemImage: "person.2.fill",
                    identifier: "project.quickAction.contacts",
                    action: openContacts
                )
                actionLink(
                    title: "Замечания",
                    accessibilityLabel: "Замечания. Список замечаний проекта",
                    systemImage: "exclamationmark.triangle",
                    identifier: "project.quickAction.issues",
                    destination: issuesDestination
                )
                actionButton(
                    title: "PDF проекта",
                    accessibilityLabel: "PDF проекта. Сводка по объекту, расходам и чек-листам",
                    systemImage: "doc.richtext",
                    identifier: "project.quickAction.projectPDF",
                    action: exportProjectPDF
                )
                actionButton(
                    title: "PDF чек-листов",
                    accessibilityLabel: "PDF чек-листов. Настройки отчёта по рабочим чек-листам",
                    systemImage: "checklist",
                    identifier: "project.quickAction.checklistPDF",
                    action: openChecklistReport
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func actionLink<Destination: View>(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String,
        destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            actionFace(title: title, systemImage: systemImage)
        }
        .buttonStyle(ProjectQuickActionButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func actionButton(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionFace(title: title, systemImage: systemImage)
        }
        .buttonStyle(ProjectQuickActionButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
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
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
        if width >= 700 { return 7 }
        if width >= 324 { return 4 }
        return 3
    }
}

/// Equal columns from the container width. A short last row stays the same item width and is centered.
private struct ProjectQuickActionGrid: Layout {
    var metrics: ProjectQuickActionMetrics
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard width > 0, !subviews.isEmpty else { return CGSize(width: max(width, 0), height: 0) }
        let frames = frames(for: subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() where index < frames.count {
            let frame = frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        let columns = max(metrics.columns(for: width), 1)
        let itemWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var frames: [CGRect] = []
        var y: CGFloat = 0
        var index = 0
        while index < subviews.count {
            let end = min(index + columns, subviews.count)
            var rowHeight: CGFloat = 44
            var sizes: [CGSize] = []
            for item in subviews[index..<end] {
                let size = item.sizeThatFits(ProposedViewSize(width: itemWidth, height: nil))
                let height = max(size.height, 44)
                sizes.append(CGSize(width: itemWidth, height: height))
                rowHeight = max(rowHeight, height)
            }
            let count = sizes.count
            let rowWidth = CGFloat(count) * itemWidth + CGFloat(max(count - 1, 0)) * spacing
            let originX = count < columns ? (width - rowWidth) / 2 : 0
            for column in sizes.indices {
                let x = originX + CGFloat(column) * (itemWidth + spacing)
                frames.append(CGRect(x: x, y: y, width: itemWidth, height: rowHeight))
            }
            y += rowHeight + spacing
            index = end
        }
        return frames
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
