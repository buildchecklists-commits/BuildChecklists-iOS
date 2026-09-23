import Foundation
import UIKit

/// Temporary checklist PDF owned by one export screen.
///
/// Lifecycle:
/// - The screen picks a new file in `temporaryDirectory`. Documents, `projectPDFPath` and `pdfPaths` are never used.
/// - The name is `BuildChecklists_<safe project name>_<yyyy-MM-dd_HHmmss>.pdf`.
/// - `/`, `\`, `:`, controls and other unsafe characters are removed. Cyrillic stays. The project name is limited to 40 characters.
/// - If that exact name already exists, a short unique suffix is added. Another file is not overwritten.
/// - Only the URL created by this screen is deleted: before the next export, after an error or cancellation, and when the screen closes.
/// - The file stays on disk while Preview is visible and while the system share sheet is open.
/// - Other temporary PDFs, including expense and project reports, are left untouched.
nonisolated enum ChecklistReportExportFile {
    static let nameLimit = 40

    static func makeURL(
        projectName: String,
        now: Date = Date(),
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        let directory = FileManager.default.temporaryDirectory
        let safe = sanitizedProjectName(projectName)
        let stamp = timestamp(now)
        let base = "BuildChecklists_\(safe)_\(stamp)"
        var url = directory.appendingPathComponent("\(base).pdf")
        if fileExists(url.path) {
            let suffix = String(UUID().uuidString.prefix(8))
            url = directory.appendingPathComponent("\(base)_\(suffix).pdf")
        }
        return url
    }

    static func sanitizedProjectName(_ name: String) -> String {
        let scalars = name.unicodeScalars.map { scalar -> Unicode.Scalar in
            if scalar.value < 32 || forbidden.contains(scalar) {
                return Unicode.Scalar(32)
            }
            return scalar
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limited = String(collapsed.prefix(nameLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
        return limited.isEmpty ? "Project" : limited
    }

    /// Deletes one owned temporary file. Ignores URLs outside the system temporary directory.
    static func remove(_ url: URL?) {
        guard let url, url.isFileURL else { return }
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.path
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        guard parent == temporary else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.string(from: date)
    }
}

nonisolated enum ChecklistReportExportMessage {
    static let prepareData = "Не удалось подготовить данные отчёта."
    static let createPDF = "Не удалось создать PDF. Попробуйте ещё раз."
    static let temporaryFile = "Не удалось подготовить временный файл."
    static let partialReport = "Отчёт создан не полностью: некоторые данные не удалось прочитать."

    /// `nil` means cancellation: the screen returns to its initial state without an error alert.
    static func text(for error: Error) -> String? {
        if error is CancellationError { return nil }
        if error is ChecklistReportSnapshotError { return nil }
        if let error = error as? ChecklistReportPDFError {
            switch error {
            case .cancelled:
                return nil
            case .destinationUnavailable:
                return temporaryFile
            case .pdfStartFailed, .writeFailed:
                return createPDF
            }
        }
        return prepareData
    }
}

func checklistReportConfigurePopover(_ controller: UIActivityViewController, sourceView: UIView) {
    guard let popover = controller.popoverPresentationController else { return }
    popover.sourceView = sourceView
    let bounds = sourceView.bounds
    if bounds.width >= 1, bounds.height >= 1 {
        popover.sourceRect = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    } else {
        popover.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    popover.permittedArrowDirections = []
}
