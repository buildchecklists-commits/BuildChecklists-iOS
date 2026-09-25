import UIKit

/// Draws «Сводный отчёт» from an already built snapshot.
nonisolated enum SummaryReportRenderer {
    static let documentTitle = "Сводный отчёт"

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
        drawIssues(snapshot, on: page)
        drawExpenses(snapshot, on: page)
        drawTasks(snapshot, on: page)
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
        page.drawText("Сформирован: \(ReportFormat.formedAt(meta.generatedAt))", style: .body, spacing: 2)
        page.drawText("Состояние на момент формирования.", style: .secondary, spacing: 8)
    }

    private static func drawSummary(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let lines = summaryLines(snapshot)
        let width = page.contentWidth
        let height = lines.reduce(CGFloat(0)) { partial, line in
            partial + ReportTypography.height(of: line, style: .body, width: width) + 2
        } + 6
        page.drawSection("Сводка", reserving: height)
        for (index, line) in lines.enumerated() {
            let last = index == lines.count - 1
            page.drawText(line, style: .body, spacing: last ? 8 : 2)
        }
    }

    private static func drawProgress(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.packs.map { pack -> [String] in
            let percent = pack.readState == .ready
                ? "\(ChecklistReportProgress.roundedDisplayPercent(pack.progress))%"
                : "Не прочитано"
            return [
                pack.title,
                "\(pack.doneCount) из \(pack.itemCount)",
                percent,
                "\(pack.issueCount)"
            ]
        }
        drawTable(
            "Ход строительства",
            columns: [
                ReportColumn(title: "Этап", fraction: 0.46),
                ReportColumn(title: "Выполнено", fraction: 0.22),
                ReportColumn(title: "Процент", fraction: 0.16, trailing: true, monospacedDigits: true),
                ReportColumn(title: "Замечания", fraction: 0.16, trailing: true, monospacedDigits: true)
            ],
            rows: rows,
            on: page
        )
    }

    private static func drawSchedule(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.schedule.filter(scheduleRowHasContent)
        guard !rows.isEmpty else { return }
        let columns = scheduleColumns
        page.drawSection(
            "Сроки",
            reserving: tableLeadReserve(
                columns: columns,
                firstRow: scheduleCells(rows[0]),
                contentWidth: page.contentWidth
            )
        )
        var index = 0
        while index < rows.count {
            if !scheduleHasDetail(rows[index]) {
                var batch: [[String]] = []
                while index < rows.count, !scheduleHasDetail(rows[index]) {
                    batch.append(scheduleCells(rows[index]))
                    index += 1
                }
                page.drawTable(columns: columns, rows: batch)
                continue
            }
            let row = rows[index]
            page.drawTable(columns: columns, rows: [scheduleCells(row)])
            if let reason = row.delayReason {
                drawScheduleDetail(stage: row.title, label: "Причина", text: reason.title, on: page)
            }
            if let comment = nonempty(row.delayComment) {
                drawScheduleDetail(stage: row.title, label: "Комментарий", text: comment, on: page)
            }
            index += 1
        }
    }

    private static let scheduleColumns = [
        ReportColumn(title: "Этап", fraction: 0.30),
        ReportColumn(title: "План", fraction: 0.26),
        ReportColumn(title: "Факт", fraction: 0.22),
        ReportColumn(title: "Состояние", fraction: 0.22)
    ]

    private static func scheduleCells(_ row: ProjectReportScheduleRow) -> [String] {
        [
            row.title,
            dateSpan(row.plannedStart, row.plannedEnd),
            dateSpan(row.actualStart, row.actualEnd),
            scheduleStatus(row)
        ]
    }

    private static func scheduleHasDetail(_ row: ProjectReportScheduleRow) -> Bool {
        row.delayReason != nil || nonempty(row.delayComment) != nil
    }

    /// Full-width reason or comment under one schedule row. A short row stays in the table.
    private static func drawScheduleDetail(
        stage: String,
        label: String,
        text: String,
        on page: ReportPage
    ) {
        let body = "\(label): \(text)"
        let width = page.contentWidth
        let line = ReportTypography.lineHeight(for: .body)
        let marker = "\(stage) — \(label.lowercased()), продолжение"
        var rest = body
        var placeMarker = false
        var steps = 0
        while !rest.isEmpty, steps < 200 {
            steps += 1
            let markerHeight = placeMarker
                ? ReportTypography.height(of: marker, style: .note, width: width) + 2
                : 0
            let before = page.pageCount
            page.ensure(markerHeight + line * 2)
            if page.pageCount != before {
                placeMarker = true
            }
            let reservedMarker = placeMarker
                ? ReportTypography.height(of: marker, style: .note, width: width) + 2
                : 0
            let available = page.remainingContentHeight - reservedMarker - line
            if available < line {
                let again = page.pageCount
                page.ensure(line * 4)
                if page.pageCount == again { break }
                placeMarker = true
                continue
            }
            let chunk = fittingPrefix(rest, style: .body, width: width, maxHeight: available)
            let tooShort = chunk.isEmpty || (rest == body && chunk.count < min(body.count, label.count + 2))
            if tooShort {
                let again = page.pageCount
                page.ensure(line * 4)
                if page.pageCount == again { break }
                placeMarker = true
                continue
            }
            if placeMarker {
                page.drawText(marker, style: .note, spacing: 2)
                placeMarker = false
            }
            let finished = chunk.count >= rest.count
            page.drawText(chunk, style: .body, spacing: finished ? 6 : 0)
            if finished { break }
            rest = trimLeadingWhitespace(String(rest.dropFirst(chunk.count)))
            if page.remainingContentHeight < line * 2 {
                placeMarker = true
            }
        }
    }

    private static func fittingPrefix(
        _ text: String,
        style: ReportTextStyle,
        width: CGFloat,
        maxHeight: CGFloat
    ) -> String {
        guard maxHeight > 1, !text.isEmpty else { return "" }
        if ReportTypography.height(of: text, style: style, width: width) <= maxHeight + 0.5 {
            return text
        }
        let source = text as NSString
        var low = 1
        var high = source.length
        var best = 0
        while low <= high {
            let mid = (low + high) / 2
            let prefix = source.substring(to: mid)
            if ReportTypography.height(of: prefix, style: style, width: width) <= maxHeight + 0.5 {
                best = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard best > 0 else { return "" }
        let raw = source.substring(to: best) as NSString
        var cut = best
        if best < source.length {
            var found = false
            var index = raw.length - 1
            while index > 0 {
                if let scalar = UnicodeScalar(raw.character(at: index)),
                   CharacterSet.whitespacesAndNewlines.contains(scalar) {
                    cut = index
                    found = true
                    break
                }
                index -= 1
            }
            if !found { cut = best }
        }
        guard cut > 0 else { return "" }
        return source.substring(to: cut)
    }

    private static func trimLeadingWhitespace(_ text: String) -> String {
        String(text.drop(while: { $0.isWhitespace }))
    }

    private static func drawIssues(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        guard !snapshot.issues.isEmpty else { return }
        let showNotes = snapshot.issues.contains { nonempty($0.noteText) != nil }
        let rows = snapshot.issues.map { issue -> [String] in
            var row = [issue.packTitle, issue.stageTitle, issue.itemTitle]
            if showNotes {
                row.append(nonempty(issue.noteText) ?? "—")
            }
            return row
        }
        var columns = [
            ReportColumn(title: "Пакет", fraction: showNotes ? 0.22 : 0.28),
            ReportColumn(title: "Этап", fraction: showNotes ? 0.24 : 0.32),
            ReportColumn(title: "Пункт", fraction: showNotes ? 0.26 : 0.40)
        ]
        if showNotes {
            columns.append(ReportColumn(title: "Заметка", fraction: 0.28))
        }
        drawTable("Замечания", columns: columns, rows: rows, on: page)
    }

    private static func drawExpenses(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.moneyRows
            .filter { $0.fact > 0 }
            .map { [ $0.stage.title, ReportFormat.money($0.fact) ] }
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

    private static func drawTasks(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let rows = snapshot.tasks.map { task in
            [
                task.title,
                task.dueDate.map(ReportFormat.day) ?? "Без срока",
                task.isCompleted ? "Выполнена" : "Не выполнена"
            ]
        }
        drawTable(
            "Задачи",
            columns: [
                ReportColumn(title: "Задача", fraction: 0.50),
                ReportColumn(title: "Срок", fraction: 0.28),
                ReportColumn(title: "Состояние", fraction: 0.22)
            ],
            rows: rows,
            on: page
        )
    }

    private static func drawContacts(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        guard !snapshot.contacts.isEmpty else { return }
        let showPhones = snapshot.contacts.contains { nonempty($0.phone) != nil }
        let rows = snapshot.contacts.map { contact -> [String] in
            var row = [contact.name, contact.role]
            if showPhones {
                row.append(nonempty(contact.phone) ?? "—")
            }
            if let note = nonempty(contact.note) {
                row[0] = "\(contact.name)\n\(note)"
            }
            return row
        }
        var columns = [
            ReportColumn(title: "Имя", fraction: showPhones ? 0.40 : 0.55),
            ReportColumn(title: "Роль", fraction: showPhones ? 0.30 : 0.45)
        ]
        if showPhones {
            columns.append(ReportColumn(title: "Телефон", fraction: 0.30))
        }
        drawTable("Контакты", columns: columns, rows: rows, on: page)
    }

    private static func drawTable(
        _ title: String,
        columns: [ReportColumn],
        rows: [[String]],
        on page: ReportPage
    ) {
        guard !rows.isEmpty else { return }
        page.drawSection(title, reserving: tableLeadReserve(columns: columns, firstRow: rows[0], contentWidth: page.contentWidth))
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

    private static func summaryLines(_ snapshot: ProjectReportSnapshot) -> [String] {
        let plan = snapshot.moneyRows.reduce(Decimal(0)) { $0 + $1.plan }
        let fact = snapshot.moneyRows.reduce(Decimal(0)) { $0 + $1.fact }
        let displayedPlan = plan > 0 ? plan : (snapshot.metadata.budget ?? 0)
        let issueCount = snapshot.packs.reduce(0) { $0 + $1.issueCount }
        var lines = [
            "Общий прогресс: \(ChecklistReportProgress.roundedDisplayPercent(snapshot.overallProgress))%",
            "Состояние срока: \(scheduleSummary(snapshot.schedule))",
            "Активные замечания: \(issueCount)",
            "Плановый бюджет: \(ReportFormat.money(displayedPlan))",
            "Фактические расходы: \(ReportFormat.money(fact))"
        ]
        if plan > 0, fact > 0, let deviation = deviationLine(plan: plan, fact: fact) {
            lines.append(deviation)
        }
        return lines
    }

    private static func deviationLine(plan: Decimal, fact: Decimal) -> String? {
        let difference = fact - plan
        if difference > 0 {
            return "Отклонение: Перерасход \(ReportFormat.money(difference))"
        }
        if difference < 0 {
            return "Отклонение: Экономия \(ReportFormat.money(-difference))"
        }
        return "Отклонение: Без отклонения \(ReportFormat.money(0))"
    }

    private static func scheduleSummary(_ rows: [ProjectReportScheduleRow]) -> String {
        let meaningful = rows.filter(scheduleRowHasContent)
        if meaningful.contains(where: \.isOverdue) {
            return "Есть просрочка"
        }
        if meaningful.contains(where: \.hasAnyDate) {
            return "Без просрочки"
        }
        return "Сроки не заданы"
    }

    private static func scheduleRowHasContent(_ row: ProjectReportScheduleRow) -> Bool {
        if row.hasAnyDate || row.isOverdue || row.delayReason != nil {
            return true
        }
        return nonempty(row.delayComment) != nil
    }

    private static func scheduleStatus(_ row: ProjectReportScheduleRow) -> String {
        if row.isOverdue {
            return "Просрочено"
        }
        if row.actualEnd != nil {
            return "Завершено"
        }
        if row.actualStart != nil {
            return "В работе"
        }
        if row.hasAnyDate {
            return "Запланировано"
        }
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

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
