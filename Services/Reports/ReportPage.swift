import CoreText
import UIKit

/// Print styles for the new reports. Sizes are fixed; they do not follow Dynamic Type.
nonisolated enum ReportTextStyle: Equatable {
    case documentTitle
    case projectName
    case section
    case body
    case secondary
    case table
    case note
}

/// Light print palette. These colors are not dynamic and stay the same in either app theme.
nonisolated enum ReportPrintColor {
    static let background = UIColor(white: 1, alpha: 1)
    static let ink = UIColor(white: 0.12, alpha: 1)
    static let secondary = UIColor(white: 0.38, alpha: 1)
    static let rule = UIColor(white: 0.82, alpha: 1)
    static let positive = UIColor(red: 0.13, green: 0.36, blue: 0.22, alpha: 1)
    static let attention = UIColor(red: 0.45, green: 0.28, blue: 0.06, alpha: 1)
    static let negative = UIColor(red: 0.50, green: 0.12, blue: 0.10, alpha: 1)

    fileprivate static let lightTraits = UITraitCollection(userInterfaceStyle: .light)

    static func printResolved(_ color: UIColor) -> UIColor {
        color.resolvedColor(with: lightTraits)
    }
}

/// Dates and money for new reports. Locale follows the system preferred language.
nonisolated enum ReportFormat {
    static var locale: Locale {
        Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
    }

    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func formedAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Locale.preferredLanguages.first ?? Locale.current.identifier)
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func money(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        let body = formatter.string(from: amount as NSDecimalNumber) ?? "0.00"
        return body + " ₽"
    }
}

nonisolated enum ReportTypography {
    static let lineHeightMultiple: CGFloat = 1.25

    static func font(for style: ReportTextStyle) -> UIFont {
        switch style {
        case .documentTitle:
            return .systemFont(ofSize: 18, weight: .semibold)
        case .projectName:
            return .systemFont(ofSize: 14, weight: .semibold)
        case .section:
            return .systemFont(ofSize: 13, weight: .semibold)
        case .body:
            return .systemFont(ofSize: 10.5, weight: .regular)
        case .secondary:
            return .systemFont(ofSize: 10.5, weight: .regular)
        case .table:
            return .systemFont(ofSize: 9.5, weight: .regular)
        case .note:
            return .systemFont(ofSize: 9, weight: .regular)
        }
    }

    static func color(for style: ReportTextStyle) -> UIColor {
        switch style {
        case .secondary, .note:
            return ReportPrintColor.secondary
        case .documentTitle, .projectName, .section, .body, .table:
            return ReportPrintColor.ink
        }
    }

    static func lineHeight(for style: ReportTextStyle) -> CGFloat {
        ceil(font(for: style).lineHeight * lineHeightMultiple)
    }

    static func height(of text: String, style: ReportTextStyle, width: CGFloat) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(for: style),
            context: nil
        )
        return ceil(bounds.height)
    }

    fileprivate static func attributes(
        for style: ReportTextStyle,
        color: UIColor? = nil,
        alignment: NSTextAlignment = .natural,
        monospacedDigits: Bool = false,
        semibold: Bool = false
    ) -> [NSAttributedString.Key: Any] {
        let base = font(for: style)
        let weight: UIFont.Weight = semibold ? .semibold : .regular
        let font: UIFont
        if monospacedDigits {
            font = .monospacedDigitSystemFont(ofSize: base.pointSize, weight: semibold ? .semibold : .regular)
        } else if semibold, style == .table {
            font = .systemFont(ofSize: base.pointSize, weight: .semibold)
        } else if semibold {
            font = .systemFont(ofSize: base.pointSize, weight: weight)
        } else {
            font = base
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineHeightMultiple = lineHeightMultiple
        paragraph.alignment = alignment
        let paint = ReportPrintColor.printResolved(color ?? self.color(for: style))
        return [
            .font: font,
            .foregroundColor: paint,
            .paragraphStyle: paragraph
        ]
    }
}

/// One table column. `fraction` values are normalized so a row always fills the content width.
nonisolated struct ReportColumn: Equatable {
    var title: String
    var fraction: CGFloat
    var trailing: Bool
    var monospacedDigits: Bool

    init(title: String, fraction: CGFloat, trailing: Bool = false, monospacedDigits: Bool = false) {
        self.title = title
        self.fraction = fraction
        self.trailing = trailing
        self.monospacedDigits = monospacedDigits
    }
}

/// A4 drawing surface for later report renderers. Callers own the destination file.
nonisolated final class ReportPage {
    static let pageSize = CGSize(width: 595.2, height: 841.8)
    static let margin: CGFloat = 40
    static let footerReserve: CGFloat = 36
    static let laterPageTop: CGFloat = 48

    static var contentBottom: CGFloat {
        pageSize.height - margin - footerReserve
    }

    private let context: UIGraphicsPDFRendererContext
    private let formedAt: Date
    private let runningTitle: String

    private(set) var pageCount = 0
    private(set) var cursor: CGFloat = 0

    private let footerFont = UIFont.systemFont(ofSize: 8.5, weight: .regular)
    private let rowPadding: CGFloat = 3
    private let ruleThickness: CGFloat = 0.6
    private let cellPadding: CGFloat = 4

    init(context: UIGraphicsPDFRendererContext, formedAt: Date, runningTitle: String) {
        self.context = context
        self.formedAt = formedAt
        self.runningTitle = runningTitle
    }

    var contentWidth: CGFloat {
        Self.pageSize.width - Self.margin * 2
    }

    var contentTop: CGFloat {
        pageCount <= 1 ? Self.margin : Self.laterPageTop
    }

    var remainingContentHeight: CGFloat {
        max(0, Self.contentBottom - cursor)
    }

    /// Starts a new page when `height` does not fit in the room above the footer.
    func ensure(_ height: CGFloat) {
        beginPageIfNeeded()
        let needed = max(0, height)
        let pageRoom = Self.contentBottom - contentTop
        if needed <= pageRoom, remainingContentHeight + 0.5 < needed {
            beginPage()
        }
    }

    func drawText(
        _ text: String,
        style: ReportTextStyle,
        color: UIColor? = nil,
        spacing: CGFloat = 0
    ) {
        beginPageIfNeeded()
        let attributes = ReportTypography.attributes(for: style, color: color)
        let source = text as NSString
        var location = 0
        if source.length == 0 {
            advance(spacing)
            return
        }
        var stalled = 0
        while location < source.length {
            let available = remainingContentHeight
            let line = ReportTypography.lineHeight(for: style)
            if available < line {
                beginPage()
                stalled += 1
                if stalled > 4 { break }
                continue
            }
            let rest = source.substring(from: location) as NSString
            var fit = fittedLength(rest, attributes: attributes, width: contentWidth, height: available)
            if fit <= 0 {
                beginPage()
                stalled += 1
                if stalled > 4 { break }
                continue
            }
            stalled = 0
            if fit > rest.length { fit = rest.length }
            let chunk = rest.substring(to: fit)
            let height = measuredHeight(chunk, attributes: attributes, width: contentWidth)
            drawAttributed(
                chunk,
                attributes: attributes,
                in: CGRect(x: Self.margin, y: cursor, width: contentWidth, height: height)
            )
            cursor += height
            location += fit
        }
        advance(spacing)
    }

    /// Keeps a section title with the following block. The title is not drawn if it would sit alone.
    func drawSection(_ title: String, reserving following: CGFloat) {
        let titleHeight = ReportTypography.height(of: title, style: .section, width: contentWidth)
        ensure(titleHeight + max(0, following))
        drawText(title, style: .section)
    }

    /// Draws a table. The column header is repeated after a page break, including a split row.
    func drawTable(columns: [ReportColumn], rows: [[String]]) {
        guard !columns.isEmpty, !rows.isEmpty else { return }
        beginPageIfNeeded()
        let widths = columnWidths(for: columns)
        let headerLines = columns.enumerated().map { index, column in
            wrap(
                column.title,
                width: max(1, widths[index] - cellPadding * 2),
                semibold: true,
                monospaced: false
            )
        }
        let headerHeight = fragmentHeight(lineCount: maxLineCount(headerLines))
        let noteHeight = ReportTypography.lineHeight(for: .note)
        let tableLine = ReportTypography.lineHeight(for: .table)
        var rowIndex = 0
        var lineOffset = 0
        var headerOnPage = false
        var steps = 0
        let stepLimit = max(8, rows.count * 8)

        while rowIndex < rows.count, steps < stepLimit {
            steps += 1
            let wrapped = wrapRow(rows[rowIndex], columns: columns, widths: widths)
            let totalLines = max(1, maxLineCount(wrapped))
            let continuing = lineOffset > 0
            if !headerOnPage {
                let noteBlock: CGFloat = continuing ? noteHeight : 0
                let rowBlock = fragmentHeight(lineCount: totalLines - lineOffset)
                let together = headerHeight + noteBlock + rowBlock
                let pageRoom = Self.contentBottom - contentTop
                if !continuing, together > remainingContentHeight, together <= pageRoom {
                    beginPage()
                }
                ensure(headerHeight + noteBlock + tableLine)
                drawFragment(headerLines, columns: columns, widths: widths, semibold: true, monospaced: false)
                if continuing {
                    drawSingleLine("продолжение", style: .note)
                }
                headerOnPage = true
            } else if lineOffset == 0 {
                let rowBlock = fragmentHeight(lineCount: totalLines)
                let freshRoom = Self.contentBottom - Self.laterPageTop - headerHeight
                if rowBlock > remainingContentHeight, rowBlock <= freshRoom {
                    beginPage()
                    headerOnPage = false
                    continue
                }
            }

            let capacity = lineCapacity(remaining: remainingContentHeight)
            if capacity < 1 {
                beginPage()
                headerOnPage = false
                continue
            }
            let left = totalLines - lineOffset
            let take = min(left, capacity)
            let slice = wrapped.map { Array($0.dropFirst(lineOffset).prefix(take)) }
            drawFragment(slice, columns: columns, widths: widths, semibold: false, monospaced: true)
            lineOffset += take
            if lineOffset >= totalLines {
                lineOffset = 0
                rowIndex += 1
            } else {
                beginPage()
                headerOnPage = false
            }
        }
        advance(8)
    }

    private func drawSingleLine(_ text: String, style: ReportTextStyle) {
        let height = ReportTypography.lineHeight(for: style)
        guard remainingContentHeight + 0.5 >= height else { return }
        let attributes = ReportTypography.attributes(for: style)
        drawAttributed(
            text,
            attributes: attributes,
            in: CGRect(x: Self.margin, y: cursor, width: contentWidth, height: height)
        )
        cursor += height
    }

    private func beginPageIfNeeded() {
        if pageCount == 0 {
            beginPage()
        }
    }

    private func beginPage() {
        context.beginPage()
        pageCount += 1
        let box = CGRect(origin: .zero, size: Self.pageSize)
        context.cgContext.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.cgContext.fill(box)
        drawFooter()
        if pageCount > 1 {
            drawRunningHeader()
        }
        cursor = contentTop
    }

    private func drawFooter() {
        let bandTop = Self.contentBottom
        let line = ceil(footerFont.lineHeight)
        let textY = bandTop + max(0, (Self.footerReserve - line) / 2)
        let color = ReportPrintColor.printResolved(ReportPrintColor.secondary)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: footerFont,
            .foregroundColor: color
        ]
        let date = ReportFormat.formedAt(formedAt)
        let pageText = "Стр. \(pageCount)"
        let pageWidth = ceil((pageText as NSString).size(withAttributes: attributes).width)
        let dateWidth = max(0, contentWidth - pageWidth - 8)
        (date as NSString).draw(
            with: CGRect(x: Self.margin, y: textY, width: dateWidth, height: line),
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        (pageText as NSString).draw(
            with: CGRect(x: Self.pageSize.width - Self.margin - pageWidth, y: textY, width: pageWidth, height: line),
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        strokeRule(at: bandTop)
    }

    private func drawRunningHeader() {
        let font = footerFont
        let color = ReportPrintColor.printResolved(ReportPrintColor.secondary)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]
        let title = truncated(runningTitle, font: font, width: contentWidth)
        let line = ceil(font.lineHeight)
        (title as NSString).draw(
            with: CGRect(x: Self.margin, y: 16, width: contentWidth, height: line),
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        strokeRule(at: 36)
    }

    private func advance(_ spacing: CGFloat) {
        guard spacing > 0 else { return }
        if cursor + spacing <= Self.contentBottom {
            cursor += spacing
        } else {
            cursor = Self.contentBottom
        }
    }

    private func drawAttributed(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        in rect: CGRect
    ) {
        let canvas = context.cgContext
        canvas.saveGState()
        canvas.clip(to: CGRect(x: Self.margin, y: 0, width: contentWidth, height: Self.contentBottom))
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin],
            attributes: attributes,
            context: nil
        )
        canvas.restoreGState()
    }

    private func measuredHeight(
        _ text: String,
        attributes: [NSAttributedString.Key: Any],
        width: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, width > 1 else { return 0 }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
        return ceil(bounds.height)
    }

    private func fittedLength(
        _ text: NSString,
        attributes: [NSAttributedString.Key: Any],
        width: CGFloat,
        height: CGFloat
    ) -> Int {
        if text.length == 0 || width <= 1 || height <= 1 { return 0 }
        let full = measuredHeight(text as String, attributes: attributes, width: width)
        if full <= height + 0.5 { return text.length }
        let attributed = NSAttributedString(string: text as String, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        var range = CFRange()
        _ = CTFramesetterSuggestFrameSizeWithConstraints(
            setter,
            CFRange(location: 0, length: text.length),
            nil,
            CGSize(width: width, height: max(1, height - 1)),
            &range
        )
        return min(text.length, max(0, range.length))
    }

    private func columnWidths(for columns: [ReportColumn]) -> [CGFloat] {
        let fractions = columns.map { max(0, $0.fraction) }
        let sum = fractions.reduce(0, +)
        if sum <= 0 {
            let each = contentWidth / CGFloat(columns.count)
            return Array(repeating: each, count: columns.count)
        }
        return fractions.map { contentWidth * ($0 / sum) }
    }

    private func wrapRow(_ row: [String], columns: [ReportColumn], widths: [CGFloat]) -> [[String]] {
        columns.enumerated().map { index, column in
            let value = index < row.count ? row[index] : ""
            return wrap(
                value,
                width: max(1, widths[index] - cellPadding * 2),
                semibold: false,
                monospaced: column.monospacedDigits
            )
        }
    }

    private func wrap(_ text: String, width: CGFloat, semibold: Bool, monospaced: Bool) -> [String] {
        let cleaned = text.replacingOccurrences(of: "\r\n", with: "\n")
        if cleaned.isEmpty { return [""] }
        let paragraphs = cleaned.components(separatedBy: "\n")
        var lines: [String] = []
        for paragraph in paragraphs {
            lines.append(contentsOf: wrapParagraph(paragraph, width: width, semibold: semibold, monospaced: monospaced))
        }
        return lines.isEmpty ? [""] : lines
    }

    private func wrapParagraph(_ text: String, width: CGFloat, semibold: Bool, monospaced: Bool) -> [String] {
        if text.isEmpty { return [""] }
        let attributes = ReportTypography.attributes(
            for: .table,
            alignment: .natural,
            monospacedDigits: monospaced,
            semibold: semibold
        )
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let setter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 20000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        let rawLines = CTFrameGetLines(frame) as NSArray
        let source = text as NSString
        var result: [String] = []
        for case let line as CTLine in rawLines {
            let range = CTLineGetStringRange(line)
            guard range.location >= 0, range.length > 0, range.location < source.length else { continue }
            let length = min(range.length, source.length - range.location)
            let piece = source.substring(with: NSRange(location: range.location, length: length))
                .trimmingCharacters(in: .newlines)
            result.append(contentsOf: splitIfTooWide(piece, width: width, attributes: attributes))
        }
        return result.isEmpty ? [""] : result
    }

    private func splitIfTooWide(
        _ text: String,
        width: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) -> [String] {
        if text.isEmpty { return [""] }
        if (text as NSString).size(withAttributes: attributes).width <= width + 0.5 {
            return [text]
        }
        var lines: [String] = []
        var current = ""
        for character in text {
            let next = current + String(character)
            if current.isEmpty || (next as NSString).size(withAttributes: attributes).width <= width {
                current = next
            } else {
                lines.append(current)
                current = String(character)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [text] : lines
    }

    private func maxLineCount(_ lines: [[String]]) -> Int {
        lines.map(\.count).max() ?? 1
    }

    private func fragmentHeight(lineCount: Int) -> CGFloat {
        let lines = max(1, lineCount)
        let advance = ReportTypography.lineHeight(for: .table)
        return rowPadding * 2 + CGFloat(lines) * advance + ruleThickness
    }

    private func lineCapacity(remaining: CGFloat) -> Int {
        let inner = remaining - rowPadding * 2 - ruleThickness
        if inner < 1 { return 0 }
        return Int(floor(inner / ReportTypography.lineHeight(for: .table)))
    }

    private func drawFragment(
        _ lines: [[String]],
        columns: [ReportColumn],
        widths: [CGFloat],
        semibold: Bool,
        monospaced: Bool
    ) {
        let count = max(1, maxLineCount(lines))
        let advance = ReportTypography.lineHeight(for: .table)
        let top = cursor + rowPadding
        var x = Self.margin
        for (index, column) in columns.enumerated() {
            let width = widths.indices.contains(index) ? widths[index] : 0
            let cellLines = index < lines.count ? lines[index] : [""]
            let useMono = monospaced && column.monospacedDigits
            let attributes = ReportTypography.attributes(
                for: .table,
                alignment: column.trailing ? .right : .natural,
                monospacedDigits: useMono,
                semibold: semibold
            )
            let textWidth = max(1, width - cellPadding * 2)
            let text = cellLines.joined(separator: "\n")
            let rect = CGRect(x: x + cellPadding, y: top, width: textWidth, height: CGFloat(count) * advance)
            drawAttributed(text, attributes: attributes, in: rect)
            x += width
        }
        cursor = top + CGFloat(count) * advance + rowPadding
        strokeRule(at: cursor)
        cursor += ruleThickness
    }

    private func strokeRule(at y: CGFloat) {
        let canvas = context.cgContext
        canvas.saveGState()
        canvas.setStrokeColor(ReportPrintColor.printResolved(ReportPrintColor.rule).cgColor)
        canvas.setLineWidth(ruleThickness)
        canvas.move(to: CGPoint(x: Self.margin, y: y))
        canvas.addLine(to: CGPoint(x: Self.pageSize.width - Self.margin, y: y))
        canvas.strokePath()
        canvas.restoreGState()
    }

    private func truncated(_ text: String, font: UIFont, width: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        if (text as NSString).size(withAttributes: attributes).width <= width {
            return text
        }
        let ellipsis = "…"
        let words = text.split(separator: " ", omittingEmptySubsequences: false)
        var kept: [Substring] = []
        for word in words {
            let candidate = (kept + [word]).joined(separator: " ") + ellipsis
            if (candidate as NSString).size(withAttributes: attributes).width <= width {
                kept.append(word)
            } else {
                break
            }
        }
        if !kept.isEmpty {
            return kept.joined(separator: " ") + ellipsis
        }
        var current = ""
        for character in text {
            let next = current + String(character) + ellipsis
            if (next as NSString).size(withAttributes: attributes).width > width { break }
            current.append(character)
        }
        return current + ellipsis
    }
}
