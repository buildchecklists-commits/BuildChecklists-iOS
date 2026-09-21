import Foundation
import PDFKit
import UIKit

struct PDFReportService {

    /// Генерация PDF-отчёта по проекту
    func makeProjectReport(project: Project,
                           stages: [Stage],
                           expenses: [ExpenseItem]) throws -> URL {

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @72 dpi
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)

        let data = renderer.pdfData { context in
            context.beginPage()

            let margin: CGFloat = 32
            let contentWidth = pageRect.width - margin * 2
            var cursorY: CGFloat = margin

            func newPageIfNeeded(_ height: CGFloat) {
                if cursorY + height > pageRect.height - margin {
                    context.beginPage()
                    cursorY = margin
                }
            }

            func draw(_ text: String,
                      font: UIFont,
                      color: UIColor = .label,
                      spacingBelow: CGFloat = 4) {

                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraph
                ]

                let maxSize = CGSize(width: contentWidth, height: .greatestFiniteMagnitude)
                let bounding = (text as NSString).boundingRect(
                    with: maxSize,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )

                newPageIfNeeded(bounding.height + spacingBelow)

                let rect = CGRect(x: margin,
                                  y: cursorY,
                                  width: contentWidth,
                                  height: bounding.height)

                (text as NSString).draw(in: rect, withAttributes: attrs)
                cursorY += bounding.height + spacingBelow
            }

            let titleFont        = UIFont.boldSystemFont(ofSize: 20)
            let sectionTitleFont = UIFont.boldSystemFont(ofSize: 16)
            let subtitleFont     = UIFont.systemFont(ofSize: 14)
            let bodyFont         = UIFont.systemFont(ofSize: 12)

            // MARK: - Шапка отчёта

            draw("Отчёт по проекту", font: titleFont, spacingBelow: 8)
            draw(project.name, font: sectionTitleFont, spacingBelow: 12)

            if !project.address.isEmpty {
                draw("Адрес: \(project.address)", font: subtitleFont, spacingBelow: 4)
            }

            let df = DateFormatter()
            df.dateStyle = .medium

            if let start = project.dateStart {
                draw("Начало строительства: \(df.string(from: start))",
                     font: subtitleFont,
                     spacingBelow: 2)
            }

            if let end = project.dateEnd {
                draw("Плановое окончание: \(df.string(from: end))",
                     font: subtitleFont,
                     spacingBelow: 4)
            }

            if let manager = project.manager, !manager.isEmpty {
                draw("Ответственный: \(manager)",
                     font: subtitleFont,
                     spacingBelow: 8)
            }

            draw("Сгенерировано: \(df.string(from: Date()))",
                 font: bodyFont,
                 color: .secondaryLabel,
                 spacingBelow: 16)

            // MARK: - 1. Чек-листы по этапам

            draw("1. Чек-листы по этапам", font: sectionTitleFont, spacingBelow: 8)

            for stage in stages {
                draw("Этап: \(stage.title)", font: bodyFont, spacingBelow: 4)

                if let subtitle = stage.subtitle, !subtitle.isEmpty {
                    draw("  \(subtitle)",
                         font: bodyFont,
                         color: .secondaryLabel,
                         spacingBelow: 4)
                }

                if stage.items.isEmpty {
                    draw("  Нет элементов",
                         font: bodyFont,
                         color: .secondaryLabel,
                         spacingBelow: 6)
                    continue
                }

                for item in stage.items {
                    let statusSymbol: String
                    switch item.status {
                    case .some(.ok):    statusSymbol = "✅"
                    case .some(.issue): statusSymbol = "⚠️"
                    case .some(.na):    statusSymbol = "◻️"
                    case .none:         statusSymbol = "◻️"
                    }

                    var line = "\(statusSymbol) \(item.title)"
                    if let note = item.note, !note.isEmpty {
                        line += " — \(note)"
                    }

                    draw("  • \(line)", font: bodyFont, spacingBelow: 2)
                }

                cursorY += 6
                newPageIfNeeded(0)
            }

            // MARK: - 2. Расходы

            if !expenses.isEmpty {
                cursorY += 8
                newPageIfNeeded(0)

                draw("2. Расходы по проекту",
                     font: sectionTitleFont,
                     spacingBelow: 8)

                let totalAmount = expenses.reduce(Decimal(0)) { $0 + $1.amount }
                draw("Итого расходов: \(formatAmount(totalAmount))",
                     font: bodyFont,
                     spacingBelow: 6)

                // Сводка по категориям (по названию категории)
                var totalsByCategory: [String: Decimal] = [:]
                for exp in expenses {
                    let key = exp.category.title
                    totalsByCategory[key, default: 0] += exp.amount
                }

                for (cat, sum) in totalsByCategory
                    .sorted(by: { $0.key < $1.key }) {
                    draw("  • \(cat): \(formatAmount(sum))",
                         font: bodyFont,
                         spacingBelow: 2)
                }

                cursorY += 6
                newPageIfNeeded(0)

                draw("Детализация расходов:",
                     font: bodyFont,
                     spacingBelow: 4)

                let dfTime = DateFormatter()
                dfTime.dateStyle = .medium

                for exp in expenses.sorted(by: { $0.date < $1.date }) {
                    let dateStr = dfTime.string(from: exp.date)
                    var line = "\(dateStr) — \(exp.category.title): \(formatAmount(exp.amount))"
                    if let note = exp.note, !note.isEmpty {
                        line += " — \(note)"
                    }
                    draw("  • \(line)", font: bodyFont, spacingBelow: 2)
                }
            }
        }

        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let safeName = project.name.replacingOccurrences(of: "/", with: "_")
        let fileName = "BC_Report_\(safeName)_\(Int(Date().timeIntervalSince1970)).pdf"
        let url = docs.appendingPathComponent(fileName)

        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - helpers

    private func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "RUB"
        formatter.maximumFractionDigits = 2
        let number = amount as NSDecimalNumber
        return formatter.string(from: number) ?? "\(amount)"
    }
}
