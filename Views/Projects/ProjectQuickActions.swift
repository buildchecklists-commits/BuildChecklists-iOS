import SwiftUI

/// Active-task badge for the dashboard «Задачи» quick action (calendar-day rules).
struct ProjectTasksBadgeSummary: Equatable {
    var activeCount: Int
    var overdueCount: Int
    var todayCount: Int

    static let empty = ProjectTasksBadgeSummary(activeCount: 0, overdueCount: 0, todayCount: 0)

    /// Counts incomplete tasks of one project. Day boundaries match `TasksCenterView`.
    static func make(
        tasks: [TaskItem],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ProjectTasksBadgeSummary {
        let todayStart = calendar.startOfDay(for: now)
        let active = tasks.filter { !$0.isCompleted }
        var overdue = 0
        var today = 0
        for task in active {
            guard let due = task.dueDate else { continue }
            let dueDay = calendar.startOfDay(for: due)
            if dueDay < todayStart {
                overdue += 1
            } else if calendar.isDate(dueDay, inSameDayAs: todayStart) {
                today += 1
            }
        }
        return ProjectTasksBadgeSummary(
            activeCount: active.count,
            overdueCount: overdue,
            todayCount: today
        )
    }

    enum Kind {
        case none
        case overdue
        case today
        case active
    }

    var kind: Kind {
        if activeCount <= 0 { return .none }
        if overdueCount > 0 { return .overdue }
        if todayCount > 0 { return .today }
        return .active
    }

    var displayCount: String {
        activeCount > 99 ? "99+" : "\(activeCount)"
    }

    var accessibilityLabel: String {
        guard activeCount > 0 else {
            return "Задачи. Нет активных задач объекта"
        }
        var parts = ["Задачи. Активных задач объекта: \(activeCount)"]
        if overdueCount > 0 {
            parts.append("просроченных: \(overdueCount)")
        }
        if todayCount > 0 {
            parts.append("на сегодня: \(todayCount)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Compact dashboard actions. Destinations and handlers stay with the caller.
struct ProjectQuickActions<PlanDestination: View, ExpensesDestination: View, IssuesDestination: View>: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

    let openFiles: () -> Void
    let openContacts: () -> Void
    let openTasks: () -> Void
    let openChecklistReport: () -> Void
    let openReports: () -> Void
    var tasksBadge: ProjectTasksBadgeSummary = .empty
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

            // Width from the grid's own geometry (after card padding).
            // Tile height is computed from metrics + width — never from a measured-height loop.
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

    private var decorativeIconColor: Color {
        // Muted yellow: present in both appearances, soft enough for the title on top.
        ProjectUXColors.accentAction.opacity(colorScheme == .dark ? 0.34 : 0.26)
    }

    private func actionRows(width: CGFloat) -> some View {
        let metrics = ProjectQuickActionMetrics(dynamicTypeSize: dynamicTypeSize)
        let spacing: CGFloat = 8
        let layout = metrics.layout(for: width, itemCount: actionSlots.count, spacing: spacing)
        let columns = layout.columns
        let itemWidth = layout.itemWidth
        let itemHeight = metrics.itemHeight(for: itemWidth)
        let rowCount = columns > 0 ? (actionSlots.count + columns - 1) / columns : 0
        return VStack(spacing: spacing) {
            ForEach(0..<rowCount, id: \.self) { row in
                let start = row * columns
                let count = min(columns, actionSlots.count - start)
                HStack(alignment: .top, spacing: spacing) {
                    if count < columns { Spacer(minLength: 0) }
                    ForEach(0..<count, id: \.self) { offset in
                        actionSlot(
                            actionSlots[start + offset],
                            tileSize: CGSize(width: itemWidth, height: itemHeight)
                        )
                        .frame(width: itemWidth, height: itemHeight)
                        .frame(minWidth: 44, minHeight: 44)
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
    private func actionSlot(_ slot: QuickActionSlot, tileSize: CGSize) -> some View {
        switch slot {
        case .plan:
            actionLink(
                title: "План",
                accessibilityLabel: "План. Сроки текущего проекта",
                systemImage: "calendar",
                identifier: "project.quickAction.plan",
                tileSize: tileSize,
                destination: planDestination
            )
        case .expenses:
            actionLink(
                title: "Расходы",
                accessibilityLabel: "Расходы. Экран расходов текущего проекта",
                systemImage: "creditcard",
                identifier: "project.quickAction.expenses",
                tileSize: tileSize,
                destination: expensesDestination
            )
        case .files:
            actionButton(
                title: "Файлы",
                accessibilityLabel: "Файлы. Фото, документы и PDF проекта",
                systemImage: "folder.fill",
                identifier: "project.quickAction.files",
                tileSize: tileSize,
                action: openFiles
            )
        case .contacts:
            actionButton(
                title: "Контакты",
                accessibilityLabel: "Контакты. Список контактов проекта",
                systemImage: "person.2.fill",
                identifier: "project.quickAction.contacts",
                tileSize: tileSize,
                action: openContacts
            )
        case .issues:
            actionLink(
                title: "Замечания",
                accessibilityLabel: "Замечания. Список замечаний проекта",
                systemImage: "exclamationmark.triangle",
                identifier: "project.quickAction.issues",
                tileSize: tileSize,
                destination: issuesDestination
            )
        case .tasks:
            actionButton(
                title: "Задачи",
                accessibilityLabel: tasksBadge.accessibilityLabel,
                systemImage: "calendar.badge.clock",
                identifier: "project.quickAction.tasks",
                tileSize: tileSize,
                badge: tasksBadge,
                action: openTasks
            )
        case .checklistPDF:
            actionButton(
                title: "Чек-листы",
                accessibilityLabel: "Чек-листы. Настройки PDF-отчёта по рабочим чек-листам",
                systemImage: "checklist",
                identifier: "project.quickAction.checklistPDF",
                tileSize: tileSize,
                action: openChecklistReport
            )
        case .reports:
            actionButton(
                title: "Отчёты",
                accessibilityLabel: "Отчёты. Настройка сводки, заказчика, расходов и плана",
                systemImage: "doc.text.magnifyingglass",
                identifier: "project.quickAction.reports",
                tileSize: tileSize,
                action: openReports
            )
        }
    }

    private func actionLink<Destination: View>(
        title: String,
        accessibilityLabel: String,
        systemImage: String,
        identifier: String,
        tileSize: CGSize,
        destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            actionFace(title: title, systemImage: systemImage, tileSize: tileSize)
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
        tileSize: CGSize,
        badge: ProjectTasksBadgeSummary? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            actionFace(title: title, systemImage: systemImage, tileSize: tileSize, badge: badge)
        }
        .buttonStyle(ProjectQuickActionButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func actionFace(
        title: String,
        systemImage: String,
        tileSize: CGSize,
        badge: ProjectTasksBadgeSummary? = nil
    ) -> some View {
        let iconSide = min(tileSize.width, tileSize.height) * 0.76
        let showsBadge = badge.map { $0.kind != .none } ?? false
        return ZStack {
            Image(systemName: systemImage)
                .font(.system(size: max(iconSide * 0.72, 22), weight: .semibold))
                .foregroundStyle(decorativeIconColor)
                .frame(width: iconSide, height: iconSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .offset(y: -4)
                .accessibilityHidden(true)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .multilineTextAlignment(.center)
                    // Single line; column count already guarantees the full title fits.
                    .lineLimit(1)
                    .minimumScaleFactor(1)
                    .padding(.horizontal, ProjectQuickActionMetrics.titleHorizontalPadding)
                    .padding(.bottom, 7)
                    .frame(maxWidth: .infinity, alignment: .bottom)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsBadge, let badge {
                tasksBadgeView(badge)
                    .padding(.top, 5)
                    .padding(.trailing, 5)
            }
        }
        .accessibilityHidden(true)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func tasksBadgeView(_ badge: ProjectTasksBadgeSummary) -> some View {
        let colors = tasksBadgeColors(for: badge.kind)
        HStack(spacing: 2) {
            Text(badge.displayCount)
                .monospacedDigit()
            switch badge.kind {
            case .overdue:
                Text("!")
                    .fontWeight(.heavy)
            case .today:
                Image(systemName: "clock.fill")
                    .imageScale(.small)
            case .active, .none:
                EmptyView()
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(colors.background))
        .overlay {
            Capsule()
                .strokeBorder(colors.border, lineWidth: 0.5)
        }
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func tasksBadgeColors(for kind: ProjectTasksBadgeSummary.Kind) -> (background: Color, foreground: Color, border: Color) {
        switch kind {
        case .overdue:
            return (ProjectUXColors.overdue, Color.white, ProjectUXColors.overdue.opacity(0.35))
        case .today:
            // Dark label on bright orange — white fails contrast on this fill.
            return (ProjectUXColors.issue, ProjectUXColors.onAccent, ProjectUXColors.issue.opacity(0.35))
        case .active:
            return (
                Color(.tertiarySystemFill),
                ProjectUXColors.primaryText,
                ProjectUXColors.readableBorder
            )
        case .none:
            return (.clear, .clear, .clear)
        }
    }
}

private enum QuickActionSlot: Int, CaseIterable {
    case plan, expenses, files, contacts, issues, tasks, checklistPDF, reports
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

    /// Labels used for column fitting. Must stay in sync with `actionSlot` titles.
    static let actionTitles = [
        "План", "Расходы", "Файлы", "Контакты",
        "Замечания", "Задачи", "Чек-листы", "Отчёты"
    ]

    static let titleHorizontalPadding: CGFloat = 4

    func columns(for width: CGFloat) -> Int {
        if dynamicTypeSize.isAccessibilitySize {
            if width >= 640 { return 3 }
            if width >= 360 { return 2 }
            return 1
        }
        if dynamicTypeSize >= .xxxLarge {
            if width >= 500 { return 4 }
            if width >= 280 { return 2 }
            return 1
        }
        // Preferred phone / regular layout: 2×4. `layout` drops to 2×4 rows when titles need width.
        return 4
    }

    /// Caption semibold matching the tile label font at the current Dynamic Type.
    func titleFont() -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory)
        let base = UIFont.preferredFont(forTextStyle: .caption1, compatibleWith: traits)
        let descriptor = base.fontDescriptor.addingAttributes([
            .traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]
        ])
        return UIFont(descriptor: descriptor, size: base.pointSize)
    }

    /// Widest single-line title plus the label’s horizontal padding.
    func minimumItemWidthForTitles() -> CGFloat {
        let font = titleFont()
        let widest = Self.actionTitles
            .map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }
            .max() ?? 0
        return widest + Self.titleHorizontalPadding * 2
    }

    /// Preferred column count, then fewer until every cell fits the hit target **and**
    /// every title in one line. Regular sizes jump 4 → 2 (skip 3) so SE becomes 4×2.
    func layout(for width: CGFloat, itemCount: Int, spacing: CGFloat = 8, minimumItem: CGFloat = 44) -> (columns: Int, itemWidth: CGFloat) {
        let safeWidth = max(width, 0)
        guard safeWidth > 1, itemCount > 0 else { return (1, safeWidth) }
        let titleFloor = minimumItemWidthForTitles()
        let floor = max(minimumItem, titleFloor)
        var columns = min(max(columns(for: safeWidth), 1), itemCount)
        while columns > 1 {
            let item = (safeWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
            if item >= floor - 0.5 { break }
            if !dynamicTypeSize.isAccessibilitySize && columns > 2 {
                columns = 2
            } else {
                columns -= 1
            }
        }
        let itemWidth = columns <= 1
            ? safeWidth
            : (safeWidth - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        return (columns, max(itemWidth, 0))
    }

    /// Shared tile height from width + Dynamic Type. Not measured from rendered cells.
    func itemHeight(for itemWidth: CGFloat) -> CGFloat {
        let font = titleFont()
        // Titles stay on one line; column count absorbs width pressure.
        let titleBand = ceil(font.lineHeight) + 12
        let squareish = itemWidth * 0.90
        // Wide single-column tiles stay compact instead of becoming tall squares.
        let capped = min(squareish, titleBand + 76)
        return max(44, max(capped, titleBand + 32))
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
