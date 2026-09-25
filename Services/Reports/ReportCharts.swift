import UIKit

/// Print charts for the new reports. Drawing uses Core Graphics on the PDF context.
/// Renderers pass `includeCharts`; when it is false they do not call this type.
nonisolated enum ReportCharts {
    static let planFactTitle = "План/факт бюджета"
    static let structureTitle = "Структура расходов"
    static let progressTitle = "Прогресс по пакетам"
    static let scheduleTitle = "Отклонение сроков"

    /// At most one third of the A4 page, and never taller than one content page.
    private static var blockLimit: CGFloat {
        let pageRoom = ReportPage.pageSize.height - ReportPage.margin - ReportPage.footerReserve - ReportPage.laterPageTop
        return min(ReportPage.pageSize.height / 3, pageRoom)
    }

    static func drawPlanFact(_ rows: [ProjectReportMoneyRow], on page: ReportPage) {
        let hasPlan = rows.contains { $0.plan > 0 }
        let hasPositiveFact = rows.contains { $0.fact > 0 }
        guard hasPlan, hasPositiveFact else { return }
        let visible = rows.filter { $0.plan > 0 || $0.fact > 0 }
        guard !visible.isEmpty else { return }
        let maxValue = visible.reduce(Decimal(0)) { partial, row in
            max(partial, max(row.plan, max(row.fact, 0)))
        }
        guard maxValue > 0 else { return }
        let items = visible.map { row in
            ChartItem(
                title: row.stage.title,
                caption: "План \(ReportFormat.money(row.plan))\nФакт \(ReportFormat.money(row.fact))",
                primary: fraction(row.plan, of: maxValue),
                secondary: fraction(max(row.fact, 0), of: maxValue),
                diverging: nil
            )
        }
        draw(
            planFactTitle,
            items: items,
            legend: "Штриховка — план. Заливка — факт.",
            on: page
        )
    }

    static func drawExpenseStructure(_ expenses: [ProjectReportExpense], on page: ReportPage) {
        var order: [String] = []
        var sums: [String: Decimal] = [:]
        for expense in expenses {
            let title = expense.stage.title
            if sums[title] == nil {
                order.append(title)
            }
            sums[title, default: 0] += expense.amount
        }
        let amounts = order.compactMap { title -> (title: String, amount: Decimal)? in
            guard let amount = sums[title], amount != 0 else { return nil }
            return (title, amount)
        }
        drawExpenseStructure(amounts, on: page)
    }

    static func drawExpenseStructure(_ amounts: [(title: String, amount: Decimal)], on page: ReportPage) {
        let net = amounts.reduce(Decimal(0)) { $0 + $1.amount }
        let positive = amounts.filter { $0.amount > 0 }
        guard net > 0, positive.count >= 2 else { return }
        let base = positive.reduce(Decimal(0)) { $0 + $1.amount }
        guard base > 0 else { return }
        let shares = sharePercents(positive.map(\.amount), of: base)
        let items = zip(positive, shares).map { item, share in
            ChartItem(
                title: item.title,
                caption: "\(ReportFormat.money(item.amount)) · доля \(share)%",
                primary: fraction(item.amount, of: base),
                secondary: nil,
                diverging: nil
            )
        }
        var legend = "Полоса — доля положительного факта."
        if amounts.contains(where: { $0.amount < 0 }) {
            legend += " Отрицательные корректировки не включены в структуру."
        }
        draw(structureTitle, items: items, legend: legend, on: page)
    }

    static func drawProgress(_ packs: [ProjectReportPack], on page: ReportPage) {
        let readable = packs.filter { $0.readState == .ready && $0.itemCount > 0 }
        guard readable.count >= 2 else { return }
        let items = readable.map { pack -> ChartItem in
            let percent = ChecklistReportProgress.roundedDisplayPercent(pack.progress)
            var caption = "\(pack.doneCount) из \(pack.itemCount) · \(percent)%"
            if percent >= 100 {
                caption += " · Завершено"
            }
            return ChartItem(
                title: pack.title,
                caption: caption,
                primary: min(CGFloat(1), max(CGFloat(0), CGFloat(pack.progress))),
                secondary: nil,
                diverging: nil
            )
        }
        draw(
            progressTitle,
            items: items,
            legend: "Полоса — выполнение от 0 до 100%.",
            on: page
        )
    }

    static func drawScheduleDeviation(_ snapshot: ProjectReportSnapshot, on page: ReportPage) {
        let marks = scheduleMarks(snapshot)
        guard marks.count >= 2 else { return }
        let items = marks.map { mark in
            ChartItem(
                title: mark.title,
                caption: mark.caption,
                primary: 0,
                secondary: nil,
                diverging: CGFloat(mark.days)
            )
        }
        draw(
            scheduleTitle,
            items: items,
            legend: "Заливка — позже плана. Штриховка — раньше плана.",
            on: page
        )
    }

    private struct ChartItem {
        var title: String
        var caption: String
        var primary: CGFloat
        var secondary: CGFloat?
        var diverging: CGFloat?
    }

    private struct ScheduleMark {
        var title: String
        var days: Int
        var caption: String
    }

    /// Completed stages compare actual and planned ends. An open overdue stage compares the report date.
    private static func scheduleMarks(_ snapshot: ProjectReportSnapshot) -> [ScheduleMark] {
        snapshot.schedule.compactMap { row in
            guard let plannedEnd = row.plannedEnd else { return nil }
            let compared: Date
            if let actualEnd = row.actualEnd {
                compared = actualEnd
            } else if row.isOverdue {
                compared = snapshot.metadata.generatedAt
            } else {
                return nil
            }
            let days = dayShift(from: plannedEnd, to: compared)
            return ScheduleMark(title: row.title, days: days, caption: dayCaption(days))
        }
    }

    private static func dayCaption(_ days: Int) -> String {
        if days > 0 { return "Позже на \(days) дн." }
        if days < 0 { return "Раньше на \(-days) дн." }
        return "В срок"
    }

    private static func dayShift(from start: Date, to end: Date) -> Int {
        let calendar = Calendar.current
        let lower = calendar.startOfDay(for: start)
        let upper = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: lower, to: upper).day ?? 0
    }

    private static func draw(
        _ title: String,
        items: [ChartItem],
        legend: String,
        on page: ReportPage
    ) {
        guard !items.isEmpty else { return }
        let width = page.contentWidth
        let titleHeight = ReportTypography.height(of: title, style: .section, width: width)
        let legendHeight = ReportTypography.height(of: legend, style: .note, width: width) + 4
        let limit = max(1, blockLimit - titleHeight)
        let measured = items.map { item -> (ChartItem, CGFloat) in
            (item, rowHeight(item, width: width))
        }
        var shown = measured
        var note: String?
        let full = measured.reduce(CGFloat(0)) { $0 + $1.1 } + legendHeight
        if full > limit {
            let noteLine = ReportTypography.lineHeight(for: .note) + 2
            var used = legendHeight + noteLine
            var count = 0
            for entry in measured {
                if count > 0, used + entry.1 > limit { break }
                used += entry.1
                count += 1
            }
            count = min(max(count, 1), measured.count)
            if count < measured.count {
                shown = Array(measured.prefix(count))
                note = "Показано \(count) из \(measured.count)"
            }
        }
        let noteHeight = note.map { ReportTypography.height(of: $0, style: .note, width: width) + 2 } ?? 0
        let body = shown.reduce(CGFloat(0)) { $0 + $1.1 } + legendHeight + noteHeight
        guard body > 1 else { return }
        page.drawSection(title, reserving: body)
        let rect = CGRect(x: ReportPage.margin, y: page.cursor, width: width, height: body)
        paint(shown.map(\.0), legend: legend, note: note, in: rect)
        page.drawText("", style: .note, spacing: body)
    }

    private static func rowHeight(_ item: ChartItem, width: CGFloat) -> CGFloat {
        let labelWidth = width * 0.34
        let valueWidth = width * 0.36
        let text = max(
            ReportTypography.height(of: item.title, style: .table, width: labelWidth),
            ReportTypography.height(of: item.caption, style: .table, width: valueWidth)
        )
        let bars: CGFloat = item.secondary == nil ? 10 : 20
        return max(text, bars) + 5
    }

    private static func paint(_ items: [ChartItem], legend: String, note: String?, in rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let labelWidth = rect.width * 0.34
        let valueWidth = rect.width * 0.36
        let gap: CGFloat = 6
        let barX = rect.minX + labelWidth + gap
        let barWidth = max(8, rect.width - labelWidth - valueWidth - gap * 2)
        var y = rect.minY
        let legendHeight = ReportTypography.height(of: legend, style: .note, width: rect.width)
        draw(legend, style: .note, in: CGRect(x: rect.minX, y: y, width: rect.width, height: legendHeight))
        y += legendHeight + 4
        let diverging = items.compactMap(\.diverging)
        let lower = min(0, diverging.min() ?? 0)
        let upper = max(0, diverging.max() ?? 0)
        for item in items {
            let height = rowHeight(item, width: rect.width) - 5
            let labelRect = CGRect(x: rect.minX, y: y, width: labelWidth, height: height)
            let valueRect = CGRect(x: rect.maxX - valueWidth, y: y, width: valueWidth, height: height)
            draw(item.title, style: .table, in: labelRect)
            draw(item.caption, style: .table, in: valueRect)
            let barRect = CGRect(
                x: barX,
                y: y + 1,
                width: barWidth,
                height: barThickness(item)
            )
            if let days = item.diverging {
                paintDiverging(days, lower: lower, upper: upper, in: barRect, context: context)
            } else if let secondary = item.secondary {
                let each = (barRect.height - 2) / 2
                paintBar(fraction: item.primary, filled: false, in: CGRect(x: barRect.minX, y: barRect.minY, width: barRect.width, height: each), context: context)
                paintBar(fraction: secondary, filled: true, in: CGRect(x: barRect.minX, y: barRect.minY + each + 2, width: barRect.width, height: each), context: context)
            } else {
                paintBar(fraction: item.primary, filled: true, in: barRect, context: context)
            }
            y += height + 5
        }
        if let note {
            let noteHeight = ReportTypography.height(of: note, style: .note, width: rect.width)
            draw(note, style: .note, in: CGRect(x: rect.minX, y: y, width: rect.width, height: noteHeight))
        }
    }

    private static func barThickness(_ item: ChartItem) -> CGFloat {
        item.secondary == nil ? 8 : 18
    }

    private static func paintBar(fraction: CGFloat, filled: Bool, in rect: CGRect, context: CGContext) {
        let ink = ReportPrintColor.printResolved(ReportPrintColor.ink).cgColor
        let rule = ReportPrintColor.printResolved(ReportPrintColor.rule).cgColor
        context.setStrokeColor(rule)
        context.setLineWidth(0.6)
        context.stroke(rect)
        let width = rect.width * min(CGFloat(1), max(CGFloat(0), fraction))
        guard width > 0.5 else { return }
        let bar = CGRect(x: rect.minX, y: rect.minY, width: width, height: rect.height)
        if filled {
            context.setFillColor(ink)
            context.fill(bar)
            return
        }
        context.saveGState()
        context.clip(to: bar)
        context.setStrokeColor(ink)
        context.setLineWidth(0.7)
        var x = bar.minX - bar.height
        while x < bar.maxX {
            context.move(to: CGPoint(x: x, y: bar.maxY))
            context.addLine(to: CGPoint(x: x + bar.height, y: bar.minY))
            x += 3
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func paintDiverging(_ days: CGFloat, lower: CGFloat, upper: CGFloat, in rect: CGRect, context: CGContext) {
        let span = max(upper - lower, 1)
        let zeroX = rect.minX + ((0 - lower) / span) * rect.width
        let rule = ReportPrintColor.printResolved(ReportPrintColor.rule).cgColor
        let ink = ReportPrintColor.printResolved(ReportPrintColor.ink).cgColor
        context.setStrokeColor(rule)
        context.setLineWidth(0.6)
        context.stroke(rect)
        context.setStrokeColor(ink)
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: zeroX, y: rect.minY))
        context.addLine(to: CGPoint(x: zeroX, y: rect.maxY))
        context.strokePath()
        guard days != 0 else { return }
        let endX = rect.minX + ((days - lower) / span) * rect.width
        let bar = CGRect(x: min(zeroX, endX), y: rect.minY, width: max(1, abs(endX - zeroX)), height: rect.height)
        paintBar(fraction: 1, filled: days > 0, in: bar, context: context)
    }

    private static func draw(_ text: String, style: ReportTextStyle, in rect: CGRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = ReportTypography.lineHeightMultiple
        let attributes: [NSAttributedString.Key: Any] = [
            .font: ReportTypography.font(for: style),
            .foregroundColor: ReportPrintColor.printResolved(ReportTypography.color(for: style)),
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }

    private static func fraction(_ value: Decimal, of total: Decimal) -> CGFloat {
        guard total > 0, value > 0 else { return 0 }
        let number = NSDecimalNumber(decimal: value / total).doubleValue
        return CGFloat(min(1, max(0, number)))
    }

    /// Rounded shares of the displayed positive amounts. The integers add up to 100.
    private static func sharePercents(_ amounts: [Decimal], of total: Decimal) -> [Int] {
        guard total > 0, !amounts.isEmpty else { return [] }
        let exact = amounts.map { amount -> Double in
            guard amount > 0 else { return 0 }
            return NSDecimalNumber(decimal: (amount / total) * 100).doubleValue
        }
        var floors = exact.map { Int($0.rounded(.down)) }
        var leftover = 100 - floors.reduce(0, +)
        let order = exact.indices.sorted { lhs, rhs in
            let leftPart = exact[lhs] - Double(floors[lhs])
            let rightPart = exact[rhs] - Double(floors[rhs])
            if leftPart == rightPart { return lhs < rhs }
            return leftPart > rightPart
        }
        var index = 0
        while leftover > 0, !order.isEmpty {
            floors[order[index % order.count]] += 1
            leftover -= 1
            index += 1
        }
        return floors
    }
}
