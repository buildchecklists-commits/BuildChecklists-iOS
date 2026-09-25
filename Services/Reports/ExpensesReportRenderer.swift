import UIKit

/// Outcome of an expenses report. An empty operation list does not become a blank PDF.
nonisolated enum ExpensesReportResult: Equatable {
    case pdf(Data)
    case noContent
}

/// Draws «Отчёт по расходам» from operations already stored on the snapshot.
nonisolated enum ExpensesReportRenderer {
    static let documentTitle = "Отчёт по расходам"

    static func render(_ snapshot: ProjectReportSnapshot, includeCharts: Bool = false) -> ExpensesReportResult {
        guard !snapshot.expenses.isEmpty else { return .noContent }
        let bounds = CGRect(origin: .zero, size: ReportPage.pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)
        let data = renderer.pdfData { context in
            let page = ReportPage(
                context: context,
                formedAt: snapshot.metadata.generatedAt,
                runningTitle: snapshot.metadata.name
            )
            draw(snapshot, on: page, includeCharts: includeCharts)
        }
        return .pdf(data)
    }

    private static func draw(_ snapshot: ProjectReportSnapshot, on page: ReportPage, includeCharts: Bool) {
        let expenses = snapshot.expenses
        drawHeader(snapshot, expenses: expenses, on: page)
        if includeCharts {
            ReportCharts.drawExpenseStructure(expenses, on: page)
        }
        var plain: [[String]] = []
        var sectionDrawn = false
        func openSectionIfNeeded() {
            guard !sectionDrawn else { return }
            page.drawSection("Операции", reserving: 64)
            sectionDrawn = true
        }
        for expense in expenses {
            if nonempty(expense.note) == nil {
                plain.append(operationCells(expense))
                continue
            }
            if !plain.isEmpty {
                openSectionIfNeeded()
                page.drawTable(columns: operationColumns, rows: plain)
                plain.removeAll()
            }
            openSectionIfNeeded()
            page.drawTable(columns: operationColumns, rows: [operationCells(expense)])
            if let note = nonempty(expense.note) {
                drawComment(expense, text: note, on: page)
            }
        }
        if !plain.isEmpty {
            openSectionIfNeeded()
            page.drawTable(columns: operationColumns, rows: plain)
        }
    }

    private static let operationColumns = [
        ReportColumn(title: "Дата", fraction: 0.28),
        ReportColumn(title: "Этап", fraction: 0.30),
        ReportColumn(title: "Тип", fraction: 0.20),
        ReportColumn(title: "Сумма", fraction: 0.22, trailing: true, monospacedDigits: true)
    ]

    private static func drawHeader(
        _ snapshot: ProjectReportSnapshot,
        expenses: [ProjectReportExpense],
        on page: ReportPage
    ) {
        let meta = snapshot.metadata
        page.drawText("BuildChecklists", style: .secondary, spacing: 2)
        page.drawText(documentTitle, style: .documentTitle, spacing: 4)
        page.drawText(meta.name, style: .projectName, spacing: 4)
        page.drawText("Сформирован: \(ReportFormat.formedAt(meta.generatedAt))", style: .body, spacing: 6)
        for line in filterLines(expenses) {
            page.drawText(line, style: .body, spacing: 2)
        }
        let total = expenses.reduce(Decimal(0)) { $0 + $1.amount }
        page.drawText("Операций: \(expenses.count)", style: .body, spacing: 2)
        page.drawText("Сумма: \(ReportFormat.money(total))", style: .body, spacing: 8)
    }

    private static func filterLines(_ expenses: [ProjectReportExpense]) -> [String] {
        let dates = expenses.map(\.date).sorted()
        var lines: [String] = []
        if let first = dates.first, let last = dates.last {
            let start = ReportFormat.day(first)
            let end = ReportFormat.day(last)
            if Calendar.current.isDate(first, inSameDayAs: last) {
                lines.append("Период: \(start)")
            } else {
                lines.append("Период: \(start) — \(end)")
            }
        }
        let stages = unique(expenses.map { $0.stage.title })
        let types = unique(expenses.map { $0.subCategory.title })
        if !stages.isEmpty {
            lines.append("Этапы: \(stages.joined(separator: ", "))")
        }
        if !types.isEmpty {
            lines.append("Типы: \(types.joined(separator: ", "))")
        }
        return lines
    }

    private static func operationCells(_ expense: ProjectReportExpense) -> [String] {
        [
            ReportFormat.day(expense.date),
            expense.stage.title,
            expense.subCategory.title,
            ReportFormat.money(expense.amount)
        ]
    }

    private static func drawComment(
        _ expense: ProjectReportExpense,
        text: String,
        on page: ReportPage
    ) {
        let label = "Комментарий"
        let body = "\(label): \(text)"
        let marker = "\(ReportFormat.day(expense.date)), \(expense.stage.title) — комментарий, продолжение"
        let width = page.contentWidth
        let line = ReportTypography.lineHeight(for: .body)
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

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func trimLeadingWhitespace(_ text: String) -> String {
        String(text.drop(while: { $0.isWhitespace }))
    }

    private static func nonempty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
