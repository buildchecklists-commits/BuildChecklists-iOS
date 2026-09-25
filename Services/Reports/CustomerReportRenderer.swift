import UIKit

/// Draws «Отчёт для заказчика» from an already built snapshot.
/// Internal notes, photos, tasks, phones, and delay reasons are never printed.
nonisolated enum CustomerReportRenderer {
    static let documentTitle = "Отчёт для заказчика"

    static func pdfData(for snapshot: ProjectReportSnapshot) -> Data {
        let bounds = CGRect(origin: .zero, size: ReportPage.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        return renderer.pdfData { context in
            let page = ReportPage(
                context: context,
                formedAt: snapshot.metadata.generatedAt,
                runningTitle: snapshot.metadata.name
            )
            draw(snapshot, on: page)
        }
    }

    private static func draw(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        drawHeader(snapshot, on: page)
        drawSummary(snapshot, on: page)
        drawProgress(snapshot, on: page)
        drawSchedule(snapshot, on: page)
        drawExpenseSums(snapshot, on: page)
        drawContacts(snapshot, on: page)
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

    private static func drawSummary(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let lines = summaryLines(snapshot)
        guard !lines.isEmpty else { return }
        let width = page.contentWidth
        let height = lines.reduce(CGFloat(0)) { partial, line in
            partial + ReportTypography.height(of: line, style: .body, width: width) + 2
        } + 6
        page.drawSection("Сводка", reserving: height)
        for (index, line) in lines.enumerated() {
            page.drawText(line, style: .body, spacing: index == lines.count - 1 ? 8 : 2)
        }
    }

    private static func drawProgress(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.packs.map { pack -> [String] in
            let percent = pack.readState == .ready
                ? "\(ChecklistReportProgress.roundedDisplayPercent(pack.progress))%"
                : "Не прочитано"
            return [pack.title, "\(pack.doneCount) из \(pack.itemCount)", percent]
        }
        drawTable(
            "Ход строительства",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.50),
                ReportColumn(title: "Выполнено", fraction: 0.26),
                ReportColumn(title: "Процент", fraction: 0.24, trailing: true, monospacedDigits: true)
            ],
            rows: rows,
            on: page
        )
    }

    private static func drawSchedule(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.schedule.filter(scheduleRowHasContent).map { row in
            [
                row.title,
                dateSpan(row.plannedStart, row.plannedEnd),
                dateSpan(row.actualStart, row.actualEnd),
                scheduleStatus(row)
            ]
        }
        drawTable(
            "Сроки",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.30),
                ReportColumn(title: "План", fraction: 0.26),
                ReportColumn(title: "Факт", fraction: 0.22),
                ReportColumn(title: "Состояние", fraction: 0.22)
            ],
            rows: rows,
            on: page
        )
    }

    private static func drawExpenseSums(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.moneyRows
            .filter { $0.fact > 0 }
            .map { [$0.stage.title, ReportFormat.money($0.fact)] }
        drawTable(
            "Расходы",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.68),
                ReportColumn(title: "Сумма", fraction: 0.32, trailing: true, monospacedDigits: true)
            ],
            rows: rows,
            on: page
        )
    }

    private static func drawContacts(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.contacts.compactMap { contact -> [String]? in
            let name = nonempty(contact.name)
            let role = nonempty(contact.role)
            guard name != nil || role != nil else { return nil }
            return [name ?? "—", role ?? "—"]
        }
        drawTable(
            "Контакты",
            columns: [
                ReportColumn(title: "Имя", fraction: 0.55),
                ReportColumn(title: "Роль", fraction: 0.45)
            ],
            rows: rows,
            on: page
        )
    }

    private static func summaryLines(_ snapshot: ProjectReportSnapshot) -> [String] {
        var lines: [String] = []
        if !snapshot.packs.isEmpty {
            let percent = ChecklistReportProgress.roundedDisplayPercent(snapshot.overallProgress)
            lines.append("Общий прогресс: \(percent)%")
        }
        let schedule = snapshot.schedule.filter(scheduleRowHasContent)
        if !schedule.isEmpty {
            let state = schedule.contains(where: \.isOverdue) ? "Есть просрочка" : "Без просрочки"
            lines.append("Состояние срока: \(state)")
        }
        let plan = snapshot.moneyRows.reduce(Decimal(0)) { $0 + $1.plan }
        let fact = snapshot.moneyRows.reduce(Decimal(0)) { $0 + $1.fact }
        let displayedPlan = plan > 0 ? plan : snapshot.metadata.budget
        if let displayedPlan {
            lines.append("Плановый бюджет: \(ReportFormat.money(displayedPlan))")
        }
        if fact > 0 || displayedPlan != nil && snapshot.moneyRows.contains(where: { $0.fact > 0 || $0.plan > 0 }) {
            if fact > 0 || plan > 0 {
                lines.append("Фактические расходы: \(ReportFormat.money(fact))")
            }
        }
        if plan > 0, fact > 0 {
            lines.append(deviationLine(plan: plan, fact: fact))
        }
        return lines
    }

    private static func deviationLine(plan: Decimal, fact: Decimal) -> String {
        let difference = fact - plan
        if difference > 0 {
            return "Отклонение: Перерасход \(ReportFormat.money(difference))"
        }
        if difference < 0 {
            return "Отклонение: Экономия \(ReportFormat.money(-difference))"
        }
        return "Отклонение: Без отклонения \(ReportFormat.money(0))"
    }

    private static func scheduleRowHasContent(_ row: ProjectReportScheduleRow) -> Bool {
        row.hasAnyDate || row.isOverdue
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
        page.drawSection(title, reserving: 64)
        page.drawTable(columns: columns, rows: rows)
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
