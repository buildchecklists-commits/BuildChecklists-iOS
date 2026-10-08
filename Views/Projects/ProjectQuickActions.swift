import SwiftUI

/// Compact dashboard actions. Destinations and handlers stay with the caller.
struct ProjectQuickActions<PlanDestination: View, ExpensesDestination: View, IssuesDestination: View>: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let openFiles: () -> Void
    let openContacts: () -> Void
    let exportProjectPDF: () -> Void
    let openChecklistReport: () -> Void
    let openReports: () -> Void
    @ViewBuilder var planDestination: () -> PlanDestination
    @ViewBuilder var expensesDestination: () -> ExpensesDestination
    @ViewBuilder var issuesDestination: () -> IssuesDestination

    private let actionSlots = Array(QuickActionSlot.allCases)
    @State private var gridWidth: CGFloat = 0
    @State private var cellsInsideGrid = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Быстрые действия")
                .font(.headline)
                .foregroundStyle(ProjectUXColors.primaryText)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            // Width is the grid's own geometry after the card padding,
            // not the window and not the text's ideal width.
            // Height comes only from content — never from a measured preference loop.
            // Row order is the VoiceOver order.
            actionRows(width: gridWidth)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { grid in
                        Color.clear.preference(key: QuickActionWidthKey.self, value: grid.size.width)
                    }
                }
                .coordinateSpace(name: "quickActionGrid")
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("project.quickActions.grid")
                .accessibilityValue(gridAccessibilityValue)
        }
        .onPreferenceChange(QuickActionWidthKey.self) { gridWidth = max($0, 0) }
        .onPreferenceChange(QuickActionFramesKey.self) { frames in
            guard gridWidth > 1, frames.count == actionSlots.count else { return }
            cellsInsideGrid = frames.allSatisfy { span in
                span.minX >= -0.5 && span.maxX <= gridWidth + 0.5
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        }
    }

    private var gridAccessibilityValue: String {
        let metrics = ProjectQuickActionMetrics(dynamicTypeSize: dynamicTypeSize)
        let layout = metrics.layout(for: gridWidth, itemCount: actionSlots.count)
        return "columns=\(layout.columns);width=\(Int(gridWidth.rounded()));inside=\(cellsInsideGrid ? 1 : 0)"
    }

    private func actionRows(width: CGFloat) -> some View {
        let metrics = ProjectQuickActionMetrics(dynamicTypeSize: dynamicTypeSize)
        let spacing: CGFloat = 8
        let layout = metrics.layout(for: width, itemCount: actionSlots.count, spacing: spacing)
        let columns = layout.columns
        let itemWidth = layout.itemWidth
        let rowCount = columns > 0 ? (actionSlots.count + columns - 1) / columns : 0
        return VStack(spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                let start = row * columns
                let count = min(columns, actionSlots.count - start)
                HStack(alignment: .top, spacing: spacing) {
                    if count < columns { Spacer(minLength: 0) }
                    ForEach(0..<count, id: \.self) { offset in
                        actionSlot(actionSlots[start + offset])
                            .frame(width: itemWidth, alignment: .top)
                            .frame(minWidth: 44, minHeight: 44)
                            .fixedSize(horizontal: false, vertical: true)
                            .background {
                                GeometryReader { cell in
                                    let frame = cell.frame(in: .named("quickActionGrid"))
                                    Color.clear.preference(
                                        key: QuickActionFramesKey.self,
                                        value: [QuickActionSpan(minX: frame.minX, maxX: frame.maxX)]
                                    )
                                }
                            }
                    }
                    if count < columns { Spacer(minLength: 0) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
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
        case .reports:
            actionButton(
                title: "Отчёты",
                accessibilityLabel: "Отчёты. Настройка сводки, заказчика, расходов и плана",
                systemImage: "doc.text.magnifyingglass",
                identifier: "project.quickAction.reports",
                action: openReports
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
            UnbrokenText(
                text: title,
                textStyle: .caption1,
                weight: .medium,
                color: ProjectUXColors.primaryText,
                alignment: .center,
                maxLines: 3
            )
                .accessibilityHidden(true)
        }
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private enum QuickActionSlot: Int, CaseIterable {
    case plan, expenses, files, contacts, issues, projectPDF, checklistPDF, reports
}

private struct QuickActionWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct QuickActionSpan: Equatable {
    var minX: CGFloat
    var maxX: CGFloat
}

private struct QuickActionFramesKey: PreferenceKey {
    static var defaultValue: [QuickActionSpan] = []
    static func reduce(value: inout [QuickActionSpan], nextValue: () -> [QuickActionSpan]) {
        value.append(contentsOf: nextValue())
    }
}

struct ProjectQuickActionMetrics {
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
        // The eighth action wraps to the next row and stays centered.
        // A 640 pt column leaves about 580 pt here. Narrower widths keep the phone grid.
        if width >= 520 { return 7 }
        if width >= 324 { return 4 }
        return 3
    }

    /// Preferred column count, then fewer columns until every cell is at least 44 pt
    /// and the row stays inside `width`. Every cell in the mode uses the same width.
    func layout(for width: CGFloat, itemCount: Int, spacing: CGFloat = 8, minimumItem: CGFloat = 44) -> (columns: Int, itemWidth: CGFloat) {
        let safeWidth = max(width, 0)
        guard safeWidth > 1, itemCount > 0 else { return (1, safeWidth) }
        var columns = min(max(columns(for: safeWidth), 1), itemCount)
        while columns > 1 {
            let item = (safeWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            if item >= minimumItem - 0.5 { break }
            columns -= 1
        }
        let itemWidth = columns <= 1
            ? safeWidth
            : (safeWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return (columns, max(itemWidth, 0))
    }

    func cellsStayInside(width: CGFloat, itemCount: Int, spacing: CGFloat = 8) -> Bool {
        let fitted = layout(for: width, itemCount: itemCount, spacing: spacing)
        guard fitted.itemWidth > 0 else { return false }
        let intervals = cellIntervals(
            width: width,
            columns: fitted.columns,
            itemWidth: fitted.itemWidth,
            count: itemCount,
            spacing: spacing
        )
        return intervals.count == itemCount && intervals.allSatisfy { span in
            span.minX >= -0.5 && span.maxX <= width + 0.5
        }
    }

    func cellIntervals(
        width: CGFloat,
        columns: Int,
        itemWidth: CGFloat,
        count: Int,
        spacing: CGFloat = 8
    ) -> [(minX: CGFloat, maxX: CGFloat)] {
        guard columns > 0, count > 0 else { return [] }
        var result: [(minX: CGFloat, maxX: CGFloat)] = []
        let rowCount = (count + columns - 1) / columns
        for row in 0..<rowCount {
            let start = row * columns
            let rowCountItems = min(columns, count - start)
            let rowWidth = itemWidth * CGFloat(rowCountItems) + spacing * CGFloat(max(rowCountItems - 1, 0))
            let origin = rowCountItems < columns ? max((width - rowWidth) / 2, 0) : 0
            for index in 0..<rowCountItems {
                let minX = origin + CGFloat(index) * (itemWidth + spacing)
                result.append((minX: minX, maxX: minX + itemWidth))
            }
        }
        return result
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
