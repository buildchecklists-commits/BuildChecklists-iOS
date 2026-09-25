import UIKit

/// Outcome of a plan/fact report. No money and no dates does not become a blank PDF.
nonisolated enum PlanFactReportResult: Equatable {
    case pdf(Data)
    case noContent
}

/// Draws «План/факт» from money rows and schedule rows already stored on the snapshot.
/// The two tables stay independent: money follows `GlobalStageCategory`, dates follow timeline stages.
nonisolated enum PlanFactReportRenderer {
    static let documentTitle = "План/факт"

    static func render(_ snapshot: ProjectReportSnapshot, includeCharts: Bool = false) -> PlanFactReportResult {
        let money = visibleMoney(snapshot.moneyRows)
        let schedule = snapshot.schedule.filter(\.hasAnyDate)
        guard !money.isEmpty || !schedule.isEmpty else { return .noContent }
        let bounds = CGRect(origin: .zero, size: ReportPage.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            let page = ReportPage(
                context: context,
                formedAt: snapshot.metadata.generatedAt,
                runningTitle: snapshot.metadata.name
            )
            draw(snapshot, money: money, schedule: schedule, on: page, includeCharts: includeCharts)
        }
        return .pdf(data)
    }

    private static func draw(
        _ snapshot: ProjectReportSnapshot,
        money: [ProjectReportMoneyRow],
        schedule: [ProjectReportScheduleRow],
        on page: ReportPage,
        includeCharts: Bool
    ) {
        drawHeader(snapshot, on: page)
        drawMoneySummary(snapshot.moneyRows, on: page)
        if includeCharts {
            ReportCharts.drawPlanFact(snapshot.moneyRows, on: page)
            ReportCharts.drawExpenseStructure(
                snapshot.moneyRows.map { ($0.stage.title, $0.fact) },
                on: page
            )
        }
        drawMoneyTable(money, on: page)
        if includeCharts, !schedule.isEmpty {
            ReportCharts.drawScheduleDeviation(snapshot, on: page)
        }
        drawScheduleTable(schedule, on: page)
    }

    private static func drawHeader(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let meta = snapshot.metadata
        page.drawText("BuildChecklists", style: .secondary, spacing: 2)
        page.drawText(documentTitle, style: .documentTitle, spacing: 4)
        page.drawText(meta.name, style: .projectName, spacing: 4)
        if let address = nonempty(meta.address) {
            page.drawText("Адрес: \(address)", style: .body, spacing: 2)
        }
        if let manager = nonempty(meta.manager) {
            page.drawText("Ответственный: \(manager)", style: .body, spacing: 2)
        }
        if let dates = projectDates(meta) {
            page.drawText(dates, style: .body, spacing: 2)
        }
        page.drawText("Сформирован: \(ReportFormat.formedAt(meta.generatedAt))", style: .body, spacing: 8)
    }

    private static func drawMoneySummary(_ rows: [ProjectReportMoneyRow], on page: ReportPage) {
        let lines = summaryLines(rows)
        guard !lines.isEmpty else { return }
        let width = page.contentWidth
        let height = lines.reduce(CGFloat(0)) { partial, line in
            partial + ReportTypography.height(of: line, style: .body, width: width) + 2
        } + 6
        page.drawSection("Финансовая сводка", reserving: height)
        for (index, line) in lines.enumerated() {
            page.drawText(line, style: .body, spacing: index == lines.count - 1 ? 8 : 2)
        }
    }

    private static func drawMoneyTable(_ rows: [ProjectReportMoneyRow], on page: ReportPage) {
        let tableRows = rows.map { row in
            [
                row.stage.title,
                ReportFormat.money(row.plan),
                ReportFormat.money(row.fact),
                deviationText(plan: row.plan, fact: row.fact),
                moneyStatus(plan: row.plan, fact: row.fact)
            ]
        }
        drawTable(
            "Бюджет по этапам",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.24),
                ReportColumn(title: "План", fraction: 0.17, trailing: true, monospacedDigits: true),
                ReportColumn(title: "Факт", fraction: 0.17, trailing: true, monospacedDigits: true),
                ReportColumn(title: "Отклонение", fraction: 0.24),
                ReportColumn(title: "Состояние", fraction: 0.18)
            ],
            rows: tableRows,
            on: page
        )
    }

    private static func drawScheduleTable(_ rows: [ProjectReportScheduleRow], on page: ReportPage) {
        let tableRows = rows.map { row in
            [
                row.title,
                dateSpan(row.plannedStart, row.plannedEnd),
                dateSpan(row.actualStart, row.actualEnd),
                scheduleStatus(row)
            ]
        }
        drawTable(
            "Сроки по этапам",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.32),
                ReportColumn(title: "План", fraction: 0.28),
                ReportColumn(title: "Факт", fraction: 0.22),
                ReportColumn(title: "Состояние", fraction: 0.18)
            ],
            rows: tableRows,
            on: page
        )
    }

    private static func summaryLines(_ rows: [ProjectReportMoneyRow]) -> [String] {
        let hasPlan = rows.contains { $0.plan != 0 }
        let hasFact = rows.contains { $0.fact != 0 }
        guard hasPlan || hasFact else { return [] }
        let plan = rows.reduce(Decimal(0)) { $0 + $1.plan }
        let fact = rows.reduce(Decimal(0)) { $0 + $1.fact }
        var lines: [String] = []
        if hasPlan {
            lines.append("Общий план: \(ReportFormat.money(plan))")
        }
        if hasFact {
            lines.append("Общий факт: \(ReportFormat.money(fact))")
        }
        if hasPlan, hasFact {
            lines.append("Отклонение: \(namedDifference(plan: plan, fact: fact))")
        } else if hasPlan {
            lines.append("Фактические расходы отсутствуют")
        } else {
            lines.append("План не задан")
        }
        return lines
    }

    /// Names a difference only when both sides of one row exist. The visible amount is absolute.
    private static func deviationText(plan: Decimal, fact: Decimal) -> String {
        guard plan != 0, fact != 0 else { return "—" }
        return namedDifference(plan: plan, fact: fact)
    }

    private static func namedDifference(plan: Decimal, fact: Decimal) -> String {
        let difference = fact - plan
        if difference > 0 {
            return "Перерасход \(ReportFormat.money(difference))"
        }
        if difference < 0 {
            return "Экономия \(ReportFormat.money(-difference))"
        }
        return "Без отклонения \(ReportFormat.money(0))"
    }

    private static func moneyStatus(plan: Decimal, fact: Decimal) -> String {
        if plan == 0, fact != 0 { return "План не задан" }
        if fact == 0, plan != 0 { return "Расходов нет" }
        if fact == plan { return "Без отклонения" }
        if fact > plan { return "Перерасход" }
        return "В пределах плана"
    }

    private static func visibleMoney(_ rows: [ProjectReportMoneyRow]) -> [ProjectReportMoneyRow] {
        rows.filter { $0.plan != 0 || $0.fact != 0 }
    }

    private static func scheduleStatus(_ row: ProjectReportScheduleRow) -> String {
        if row.isOverdue { return "Просрочено" }
        if row.actualEnd != nil { return "Завершено" }
        if row.actualStart != nil { return "В работе" }
        if row.hasAnyDate { return "Запланировано" }
        return "—"
    }

    private static func dateSpan(_ start: Date?, _ end: Date?) -> String {
        switch (start, end) {
        case let (start?, end?):
            return "\(ReportFormat.day(start)) — \(ReportFormat.day(end))"
        case let (start?, nil):
            return ReportFormat.day(start)
        case let (nil, end?):
            return ReportFormat.day(end)
        default:
            return "—"
        }
    }

    private static func projectDates(_ meta: ProjectReportMetadata) -> String? {
        switch (meta.dateStart, meta.dateEnd) {
        case let (start?, end?):
            return "Срок проекта: \(ReportFormat.day(start)) — \(ReportFormat.day(end))"
        case let (start?, nil):
            return "Начало: \(ReportFormat.day(start))"
        case let (nil, end?):
            return "Окончание: \(ReportFormat.day(end))"
        default:
            return nil
        }
    }

    private static func drawTable(
        _ title: String,
        columns: [ReportColumn],
        rows: [[String]],
        on page: ReportPage
    ) {
        guard !rows.isEmpty else { return }
        page.drawSection(
            title,
            reserving: tableLeadReserve(columns: columns, firstRow: rows[0], contentWidth: page.contentWidth)
        )
        page.drawTable(columns: columns, rows: rows)
    }

    /// Keeps the section title with the table header and the first row when that block fits on one page.
    private static func tableLeadReserve(
        columns: [ReportColumn],
        firstRow: [String],
        contentWidth: CGFloat
    ) -> CGFloat {
        let fractions = columns.map { max(CGFloat(0), $0.fraction) }
        let sum = fractions.reduce(0, +)
        let widths: [CGFloat]
        if sum <= 0 || columns.isEmpty {
            let each = contentWidth / CGFloat(max(columns.count, 1))
            widths = Array(repeating: each, count: columns.count)
        } else {
            widths = fractions.map { contentWidth * ($0 / sum) }
        }
        let cellPadding: CGFloat = 4
        var tallest = ReportTypography.lineHeight(for: .table)
        for (index, _) in columns.enumerated() {
            let text = index < firstRow.count ? firstRow[index] : ""
            let width = max(1, (index < widths.count ? widths[index] : contentWidth) - cellPadding * 2)
            tallest = max(tallest, ReportTypography.height(of: text, style: .table, width: width))
        }
        let header = ReportTypography.lineHeight(for: .table) + 16
        let pageRoom = ReportPage.pageSize.height - ReportPage.margin - ReportPage.footerReserve - ReportPage.laterPageTop
        return min(header + tallest + 12, max(64, pageRoom - 24))
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
