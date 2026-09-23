import CoreText
import Foundation
import ImageIO
import UIKit

nonisolated enum ChecklistReportScope: String, Sendable, Equatable {
    case full
    case issuesOnly
}

nonisolated struct ChecklistReportRenderOptions: Sendable, Equatable {
    var scope: ChecklistReportScope
    var includePhotos: Bool

    static let fullWithPhotos = ChecklistReportRenderOptions(scope: .full, includePhotos: true)
    static let issuesOnlyWithPhotos = ChecklistReportRenderOptions(scope: .issuesOnly, includePhotos: true)
}

nonisolated enum ChecklistReportPDFError: LocalizedError, Equatable, Sendable {
    case destinationUnavailable
    case pdfStartFailed
    case writeFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .destinationUnavailable:
            return "Не удалось открыть место для PDF."
        case .pdfStartFailed:
            return "Не удалось начать PDF."
        case .writeFailed:
            return "Не удалось записать PDF."
        case .cancelled:
            return nil
        }
    }
}

/// Draws an immutable checklist snapshot. Does not read stores, notes, or UserDefaults.
nonisolated enum ChecklistReportPDFRenderer {
    static let maxPhotosPerIssue = 8

    static func render(
        _ snapshot: ChecklistReportSnapshot,
        options: ChecklistReportRenderOptions,
        to destination: URL,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws {
        if isCancelled() { throw ChecklistReportPDFError.cancelled }
        guard destination.isFileURL else { throw ChecklistReportPDFError.destinationUnavailable }
        let parent = destination.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw ChecklistReportPDFError.destinationUnavailable
        }

        let temp = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: snapshot.projectName,
            kCGPDFContextCreator as String: "BuildChecklists"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let outcome = RenderOutcome()
        do {
            try renderer.writePDF(to: temp, withActions: { context in
                let canvas = Canvas(
                    context: context,
                    pageRect: pageRect,
                    snapshot: snapshot,
                    options: options,
                    isCancelled: isCancelled
                )
                canvas.draw()
                if canvas.cancelled {
                    outcome.cancelled = true
                }
            })
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw ChecklistReportPDFError.pdfStartFailed
        }
        if outcome.cancelled {
            try? FileManager.default.removeItem(at: temp)
            throw ChecklistReportPDFError.cancelled
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw ChecklistReportPDFError.writeFailed
        }
    }
}

/// Same-thread flag. The PDF drawing closure cannot throw, so cancellation is stored here and applied as soon as `writePDF` returns.
private final class RenderOutcome: @unchecked Sendable {
    var cancelled = false
}

private nonisolated let reportInk = UIColor(white: 0.12, alpha: 1)
private nonisolated let reportSecondary = UIColor(white: 0.38, alpha: 1)
private nonisolated let reportRule = UIColor(white: 0.82, alpha: 1)
private nonisolated let reportDone = UIColor(red: 0.12, green: 0.42, blue: 0.24, alpha: 1)
private nonisolated let reportIssue = UIColor(red: 0.72, green: 0.30, blue: 0.05, alpha: 1)
private nonisolated let reportIdle = UIColor(white: 0.42, alpha: 1)

private nonisolated final class Canvas {
    let context: UIGraphicsPDFRendererContext
    let pageRect: CGRect
    let snapshot: ChecklistReportSnapshot
    let options: ChecklistReportRenderOptions
    let isCancelled: @Sendable () -> Bool

    let margin: CGFloat = 40
    let contentBottom: CGFloat
    var page = 0
    var cursor: CGFloat = 0
    var cancelled = false

    let titleFont = reportFont(size: 20, weight: .bold)
    let sectionFont = reportFont(size: 14, weight: .semibold)
    let bodyFont = reportFont(size: 11, weight: .regular)
    let strongFont = reportFont(size: 11, weight: .semibold)
    let captionFont = reportFont(size: 9, weight: .regular)

    init(
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        snapshot: ChecklistReportSnapshot,
        options: ChecklistReportRenderOptions,
        isCancelled: @escaping @Sendable () -> Bool
    ) {
        self.context = context
        self.pageRect = pageRect
        self.snapshot = snapshot
        self.options = options
        self.isCancelled = isCancelled
        self.contentBottom = pageRect.height - 40
    }

    func stop() -> Bool {
        if cancelled || isCancelled() {
            cancelled = true
            return true
        }
        return false
    }

    var contentWidth: CGFloat { pageRect.width - margin * 2 }

    func draw() {
        if stop() { return }
        newPage(isFirst: true)
        if cancelled { return }
        drawTitleBlock()
        if cancelled { return }
        drawSummary()
        if cancelled { return }
        if !hasWorkingChecklistData {
            if options.scope == .full {
                drawWrapped(
                    "Данные рабочих чек-листов пока отсутствуют.",
                    font: bodyFont,
                    color: reportInk,
                    spacing: 4
                )
            } else {
                drawIssues()
            }
            return
        }
        if options.scope == .full {
            drawPacks()
            if cancelled { return }
        }
        drawIssues()
    }

    var hasWorkingChecklistData: Bool {
        snapshot.packs.contains { pack in
            pack.readState == .unreadable || !pack.stages.isEmpty
        }
    }

    func newPage(isFirst: Bool = false) {
        if stop() { return }
        context.beginPage()
        page += 1
        UIColor.white.setFill()
        context.cgContext.fill(pageRect)
        drawChrome()
        cursor = isFirst ? 36 : 54
    }

    func drawChrome() {
        let footerY = pageRect.height - 26
        let date = reportDateText(snapshot.generatedAt)
        drawSingleLine(date, font: captionFont, color: reportSecondary, x: margin, y: footerY, width: 180)
        let pageText = "Стр. \(page)"
        let pageWidth = ceil((pageText as NSString).size(withAttributes: [.font: captionFont]).width)
        drawSingleLine(
            pageText,
            font: captionFont,
            color: reportSecondary,
            x: pageRect.width - margin - pageWidth,
            y: footerY,
            width: pageWidth + 2
        )
        reportRule.setStroke()
        context.cgContext.setLineWidth(0.4)
        context.cgContext.move(to: CGPoint(x: margin, y: footerY - 6))
        context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: footerY - 6))
        context.cgContext.strokePath()

        if page > 1 {
            drawSingleLine("BuildChecklists", font: captionFont, color: reportSecondary, x: margin, y: 28, width: 120)
            let nameWidth = contentWidth - 130
            drawSingleLine(
                snapshot.projectName,
                font: captionFont,
                color: reportSecondary,
                x: margin + 130,
                y: 28,
                width: nameWidth,
                alignment: .right,
                truncating: true
            )
            context.cgContext.move(to: CGPoint(x: margin, y: 44))
            context.cgContext.addLine(to: CGPoint(x: pageRect.width - margin, y: 44))
            context.cgContext.strokePath()
        }
    }

    func drawTitleBlock() {
        if cancelled { return }
        drawWrapped("BuildChecklists", font: captionFont, color: reportSecondary, spacing: 2)
        drawWrapped("Отчёт по рабочим чек-листам", font: titleFont, color: reportInk, spacing: 8)
        drawWrapped(snapshot.projectName, font: sectionFont, color: reportInk, spacing: 6)
        if let address = snapshot.address {
            drawWrapped("Адрес: \(address)", font: bodyFont, color: reportInk, spacing: 2)
        }
        if let manager = snapshot.manager {
            drawWrapped("Ответственный: \(manager)", font: bodyFont, color: reportInk, spacing: 2)
        }
        drawWrapped(
            "Дата формирования: \(reportDateText(snapshot.generatedAt))",
            font: bodyFont,
            color: reportInk,
            spacing: 6
        )
        let percent = ChecklistReportProgress.roundedDisplayPercent(snapshot.overallProgress)
        drawWrapped("Общий прогресс: \(percent)%", font: strongFont, color: reportInk, spacing: 2)
        drawWrapped(
            "Среднее по 10 пакетам карточки проекта, без дверей.",
            font: captionFont,
            color: reportSecondary,
            spacing: 6
        )
        drawWrapped(
            "Отчёт отражает состояние проекта на момент формирования.",
            font: bodyFont,
            color: reportInk,
            spacing: 12
        )
    }

    func drawSummary() {
        if stop() { return }
        ensure(72)
        drawWrapped("Сводка", font: sectionFont, color: reportInk, spacing: 6)
        let ready = snapshot.packs.filter { $0.readState == .ready }
        let stages = ready.reduce(0) { $0 + $1.stages.count }
        let items = ready.reduce(0) { $0 + $1.itemCount }
        let done = ready.reduce(0) { $0 + $1.doneCount }
        let issues = ready.reduce(0) { $0 + $1.issueCount }
        let notDone = ready.reduce(0) { $0 + $1.notDoneCount }
        let photos = ready.reduce(0) { $0 + $1.issuePhotoCount }
        let missing = ready
            .flatMap(\.stages)
            .flatMap(\.items)
            .reduce(0) { $0 + $1.missingPhotoCount }
        let unreadable = snapshot.packs.filter { $0.readState == .unreadable }.count
        let lines = [
            "Пакетов: \(snapshot.packs.count)",
            "Этапов: \(stages)",
            "Всего пунктов: \(items)",
            "Выполнено: \(done)",
            "Проблем: \(issues)",
            "Не выполнено: \(notDone)",
            "Фотографий замечаний: \(photos)",
            "Отсутствующих файлов фотографий: \(missing)",
            "Непрочитанных пакетов: \(unreadable)"
        ]
        for line in lines {
            drawWrapped(line, font: bodyFont, color: reportInk, spacing: 2)
        }
        if items == 0 && unreadable == 0 && options.scope == .issuesOnly {
            cursor += 4
            drawWrapped("Сохранённых пунктов пока нет.", font: bodyFont, color: reportInk, spacing: 4)
        }
        cursor += 8
    }

    func drawPacks() {
        if stop() { return }
        ensure(36)
        if cancelled { return }
        drawWrapped("Чек-листы", font: sectionFont, color: reportInk, spacing: 8)
        for pack in snapshot.packs {
            if stop() { return }
            ensure(52)
            if cancelled { return }
            drawWrapped(pack.title, font: strongFont, color: reportInk, spacing: 2)
            if pack.readState == .unreadable {
                drawWrapped(
                    pack.readError ?? ChecklistReportProgress.unreadablePackMessage,
                    font: bodyFont,
                    color: reportIssue,
                    spacing: 8
                )
                continue
            }
            let percent = ChecklistReportProgress.roundedDisplayPercent(pack.progress)
            drawWrapped(
                "\(percent)% · Выполнено \(pack.doneCount) · Проблем \(pack.issueCount) · Не выполнено \(pack.notDoneCount)",
                font: bodyFont,
                color: reportSecondary,
                spacing: 4
            )
            if pack.stages.isEmpty {
                drawWrapped("Нет сохранённых пунктов.", font: bodyFont, color: reportSecondary, spacing: 8)
                continue
            }
            for stage in pack.stages {
                if cancelled { return }
                drawStage(stage)
            }
            cursor += 6
        }
    }

    func drawStage(_ stage: ChecklistReportStage) {
        if stop() { return }
        ensure(40)
        if cancelled { return }
        drawWrapped(stage.title, font: strongFont, color: reportInk, indent: 8, spacing: 2)
        if let subtitle = stage.subtitle {
            drawWrapped(subtitle, font: captionFont, color: reportSecondary, indent: 8, spacing: 2)
        }
        let percent = ChecklistReportProgress.roundedDisplayPercent(stage.progress)
        drawWrapped(
            "\(percent)% · Выполнено \(stage.doneCount) · Проблем \(stage.issueCount) · Не выполнено \(stage.notDoneCount)",
            font: captionFont,
            color: reportSecondary,
            indent: 8,
            spacing: 3
        )
        if stage.items.isEmpty {
            drawWrapped("Нет пунктов.", font: bodyFont, color: reportSecondary, indent: 8, spacing: 4)
            return
        }
        for item in stage.items {
            if cancelled { return }
            drawItem(item)
        }
    }

    func drawItem(_ item: ChecklistReportItem) {
        let color = statusColor(item.status)
        let status = item.statusTitle
        let statusFont = reportFont(size: 10, weight: .semibold)
        let statusWidth = ceil((status as NSString).size(withAttributes: [.font: statusFont]).width)
        let column = statusWidth + 18
        let titleWidth = contentWidth - column
        let titleLines = wrappedLines(item.title, font: bodyFont, width: titleWidth)
        let lineHeight = ceil(max(statusFont.lineHeight, bodyFont.lineHeight))
        let lines = titleLines.isEmpty ? [""] : titleLines
        for (index, line) in lines.enumerated() {
            if cancelled { return }
            if cursor + lineHeight > contentBottom {
                newPage()
                if cancelled { return }
            }
            if index == 0 {
                let diameter: CGFloat = 6
                let circle = CGRect(
                    x: margin,
                    y: cursor + (lineHeight - diameter) / 2,
                    width: diameter,
                    height: diameter
                )
                color.setFill()
                UIBezierPath(ovalIn: circle).fill()
                drawSingleLine(status, font: statusFont, color: color, x: margin + 12, y: cursor, width: statusWidth + 2)
            }
            drawSingleLine(line, font: bodyFont, color: reportInk, x: margin + column, y: cursor, width: titleWidth)
            cursor += lineHeight
        }
        cursor += 2
    }

    func drawIssues() {
        if stop() { return }
        let issues = snapshot.packs.flatMap { pack in
            pack.stages.flatMap { stage in
                stage.items.compactMap { item -> (ChecklistReportPack, ChecklistReportStage, ChecklistReportItem)? in
                    guard item.status == .issue else { return nil }
                    return (pack, stage, item)
                }
            }
        }
        if issues.isEmpty {
            if options.scope == .issuesOnly {
                ensure(48)
                drawWrapped("Замечания", font: sectionFont, color: reportInk, spacing: 6)
            }
            drawWrapped("Активных замечаний нет.", font: bodyFont, color: reportInk, spacing: 4)
            return
        }
        ensure(96)
        drawWrapped("Замечания", font: sectionFont, color: reportInk, spacing: 6)
        for (pack, stage, item) in issues {
            if stop() { return }
            drawIssue(pack: pack, stage: stage, item: item)
        }
    }

    func drawIssue(pack: ChecklistReportPack, stage: ChecklistReportStage, item: ChecklistReportItem) {
        if cancelled { return }
        ensure(64)
        if cancelled { return }
        drawWrapped("\(pack.title) · \(stage.title)", font: captionFont, color: reportSecondary, spacing: 2)
        if let subtitle = stage.subtitle {
            drawWrapped(subtitle, font: captionFont, color: reportSecondary, spacing: 2)
        }
        drawWrapped(item.title, font: strongFont, color: reportInk, spacing: 3)
        if let note = item.noteText {
            drawWrapped(note, font: bodyFont, color: reportInk, spacing: 4)
        } else {
            drawWrapped("Без описания", font: bodyFont, color: reportSecondary, spacing: 4)
        }
        if options.includePhotos {
            drawIssuePhotos(item)
        } else {
            drawWrapped("Фото: \(item.photoCount)", font: bodyFont, color: reportInk, spacing: 2)
            if item.missingPhotoCount > 0 {
                drawWrapped(
                    "Не удалось вставить фото: \(item.missingPhotoCount)",
                    font: bodyFont,
                    color: reportSecondary,
                    spacing: 2
                )
            }
        }
        cursor += 8
    }

    func drawIssuePhotos(_ item: ChecklistReportItem) {
        if stop() { return }
        var shown = 0
        var failed = 0
        var extra = 0
        var column = 0
        let gap: CGFloat = 8
        let rowHeight: CGFloat = 128
        let cellWidth = (contentWidth - gap) / 2
        let cellHeight: CGFloat = 116

        func closeRow() {
            if column != 0 {
                cursor += rowHeight
                column = 0
            }
        }

        for path in item.photoPaths {
            if stop() { return }
            guard let image = reportThumbnail(path: path, maxPixelSize: 640) else {
                failed += 1
                continue
            }
            if shown >= ChecklistReportPDFRenderer.maxPhotosPerIssue {
                extra += 1
                continue
            }
            if column == 0, cursor + rowHeight > contentBottom {
                newPage()
                if cancelled { return }
            }
            let x = margin + CGFloat(column) * (cellWidth + gap)
            let cell = CGRect(x: x, y: cursor + 4, width: cellWidth, height: cellHeight)
            reportRule.setStroke()
            context.cgContext.setLineWidth(0.6)
            context.cgContext.stroke(cell)
            let fitted = aspectFit(image.size, in: cell.insetBy(dx: 4, dy: 4))
            image.draw(in: fitted)
            shown += 1
            column += 1
            if column == 2 {
                cursor += rowHeight
                column = 0
            }
        }
        closeRow()
        if shown == 0 && item.photoCount == 0 {
            drawWrapped("Фото: 0", font: bodyFont, color: reportSecondary, spacing: 2)
        }
        if failed > 0 {
            drawWrapped("Не удалось вставить фото: \(failed)", font: bodyFont, color: reportSecondary, spacing: 2)
        }
        if extra > 0 {
            drawWrapped("Ещё \(extra) фото не включено.", font: bodyFont, color: reportInk, spacing: 2)
        }
    }

    func ensure(_ height: CGFloat) {
        if cancelled { return }
        if cursor + height > contentBottom {
            newPage()
        }
    }

    func drawWrapped(
        _ text: String,
        font: UIFont,
        color: UIColor,
        indent: CGFloat = 0,
        spacing: CGFloat
    ) {
        if cancelled { return }
        let width = contentWidth - indent
        let lines = wrappedLines(text, font: font, width: width)
        let lineHeight = ceil(font.lineHeight)
        let pieces = lines.isEmpty ? [""] : lines
        for line in pieces {
            if cancelled { return }
            if cursor + lineHeight > contentBottom {
                newPage()
                if cancelled { return }
            }
            drawSingleLine(line, font: font, color: color, x: margin + indent, y: cursor, width: width)
            cursor += lineHeight
        }
        cursor += spacing
    }

    func drawSingleLine(
        _ text: String,
        font: UIFont,
        color: UIColor,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        alignment: NSTextAlignment = .left,
        truncating: Bool = false
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = truncating ? .byTruncatingTail : .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: x, y: y, width: width, height: ceil(font.lineHeight) + 1)
        (text as NSString).draw(in: rect, withAttributes: attrs)
    }

    func wrappedLines(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        let source = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !source.isEmpty else { return [] }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: source,
            attributes: [.font: font, .paragraphStyle: paragraph]
        )
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let ns = source as NSString
        var lines: [String] = []
        var index = 0
        while index < ns.length {
            var count = CTTypesetterSuggestLineBreak(typesetter, index, Double(max(width, 1)))
            if count <= 0 { count = 1 }
            let line = ns.substring(with: NSRange(location: index, length: count))
                .trimmingCharacters(in: .newlines)
            lines.append(line)
            index += count
        }
        return lines
    }
}

private nonisolated func reportFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
    let preferredName = weight >= .semibold ? "Arial-BoldMT" : "ArialMT"
    if let arial = UIFont(name: preferredName, size: size) {
        return arial
    }
    return UIFont.systemFont(ofSize: size, weight: weight)
}

private nonisolated func statusColor(_ status: ItemStatus?) -> UIColor {
    switch status {
    case .ok: return reportDone
    case .issue: return reportIssue
    case .na, .none: return reportIdle
    }
}

private nonisolated func reportDateText(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    return formatter.string(from: date)
}

private nonisolated func aspectFit(_ size: CGSize, in bounds: CGRect) -> CGRect {
    guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
    let scale = min(bounds.width / size.width, bounds.height / size.height)
    let width = size.width * scale
    let height = size.height * scale
    return CGRect(
        x: bounds.midX - width / 2,
        y: bounds.midY - height / 2,
        width: width,
        height: height
    )
}

/// ImageIO thumbnail. Does not decode a full-size UIImage and does not write the file.
private nonisolated func reportThumbnail(path: String, maxPixelSize: CGFloat) -> UIImage? {
    guard let url = reportPhotoURL(path) else { return nil }
    let pixelSize = Int(max(maxPixelSize, 1).rounded(.up))
    let options: [CFString: Any] = [
        kCGImageSourceShouldCache: false,
        kCGImageSourceShouldCacheImmediately: false
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options as CFDictionary) else { return nil }
    let thumbOptions: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: pixelSize,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
        return nil
    }
    return UIImage(cgImage: image)
}

private nonisolated func reportPhotoURL(_ path: String) -> URL? {
    let fileManager = FileManager.default
    if fileManager.fileExists(atPath: path) {
        return URL(fileURLWithPath: path)
    }
    let direct = URL(fileURLWithPath: path)
    if fileManager.fileExists(atPath: direct.path) { return direct }
    let fileName = (path as NSString).lastPathComponent
    if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
        let candidates = [
            docs.appendingPathComponent(path),
            docs.appendingPathComponent("BC_Media/Images", isDirectory: true).appendingPathComponent(fileName),
            docs.appendingPathComponent("BC_Media/PDF", isDirectory: true).appendingPathComponent(fileName),
            docs.appendingPathComponent("BCPhotos").appendingPathComponent(fileName),
            docs.appendingPathComponent("BCDocs").appendingPathComponent(fileName)
        ]
        if let match = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return match
        }
    }
    let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
    if fileManager.fileExists(atPath: temporary.path) { return temporary }
    return nil
}
