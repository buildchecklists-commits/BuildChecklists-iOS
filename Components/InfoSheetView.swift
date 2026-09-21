import SwiftUI

/// Экран подсказки с читаемым рендером Markdown-подобного текста:
/// Поддержка: #, ##, абзацы, -, *, 1., 2., ..., и ЭМОДЗИ-СПИСКИ (✅/❌/⚠️/✔️/✖️ и др.)
struct InfoSheetView: View {
    private let slug: String

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var rawText: String = ""
    @State private var error: String?

    init(slug: String) {
        self.slug = slug.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(infoSlug: String) {
        self.init(slug: infoSlug)
    }

    var body: some View {
        NavigationStack {
            Group {
                // ✅ Read-only: Info/Markdown полностью запрещены (enterprise-режим)
                if store.isReadOnlyMode {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Информация недоступна в режиме только просмотра.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                } else if let error {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(error)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                } else if rawText.isEmpty {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(parseBlocks(from: rawText)) { block in
                                switch block.kind {
                                case .header(let t, let level):
                                    Text(t)
                                        .font(level == 1 ? .title2.bold() : .headline)
                                        .padding(.top, level == 1 ? 4 : 0)

                                case .paragraph(let t):
                                    Text(t)
                                        .font(.body)

                                case .bulletList(let items):
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(items, id: \.self) { line in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("•")
                                                Text(line)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                    }

                                case .numberedList(let items):
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(Array(items.enumerated()), id: \.offset) { idx, line in
                                            HStack(alignment: .top, spacing: 8) {
                                                Text("\(idx + 1).")
                                                Text(line)
                                                    .multilineTextAlignment(.leading)
                                            }
                                        }
                                    }

                                case .emojiList(let items):
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(items, id: \.self) { line in
                                            Text(line)
                                                .multilineTextAlignment(.leading)
                                        }
                                    }

                                case .divider:
                                    Divider()
                                        .padding(.vertical, 4)

                                case .quote(let t):
                                    HStack(alignment: .top, spacing: 8) {
                                        Rectangle()
                                            .fill(Color.secondary.opacity(0.4))
                                            .frame(width: 3)
                                        Text(t)
                                            .italic()
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                    }
                }
            }
            .navigationTitle(titleFromFirstHeader(rawText) ?? "Информация")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // ✅ Если read-only — сразу закрываем экран, чтобы не было доступа вообще
            if store.isReadOnlyMode {
                dismiss()
                return
            }
            loadFile()
        }
    }

    // MARK: - Загрузка файла

    private func loadFile() {
        let key = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            error = "Пустой slug"
            return
        }

        let bundle = Bundle.main

        // 1. Вариант с "точечной" записью: foundation.piles.verticality
        let parts = key.split(separator: ".").map(String.init)
        if parts.count > 1 {
            let file = parts.last!
            let subdir = parts.dropLast().joined(separator: "/")

            if let url = bundle.url(forResource: file,
                                    withExtension: "md",
                                    subdirectory: "Resources/InfoTexts/\(subdir)") {
                read(url); return
            }
            if let url = bundle.url(forResource: file,
                                    withExtension: "md",
                                    subdirectory: "InfoTexts/\(subdir)") {
                read(url); return
            }
        }

        // 2. Fallback: slug — просто имя файла (как в отделке),
        //    ищем его рекурсивно во всех подпапках InfoTexts.
        let targetName = key + ".md"
        let candidates = [
            bundle.url(forResource: "Resources/InfoTexts", withExtension: nil),
            bundle.url(forResource: "InfoTexts", withExtension: nil)
        ]

        for base in candidates.compactMap({ $0 }) {
            if let url = findFileRecursively(in: base, endingWith: targetName) {
                read(url); return
            }
        }

        // 3. Последняя попытка — в корне бандла
        if let url = bundle.url(forResource: key, withExtension: "md") {
            read(url); return
        }

        error = "Файл не найден для slug: \(slug)"
    }

    private func read(_ url: URL) {
        do {
            rawText = try String(contentsOf: url, encoding: .utf8)
        } catch {
            self.error = "Ошибка чтения файла: \(error.localizedDescription)"
        }
    }

    // MARK: - Поиск файла в подпапках (fallback)

    private func findFileRecursively(in dir: URL, endingWith tail: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir,
                                                              includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.lastPathComponent == (tail as NSString).lastPathComponent &&
                url.path.hasSuffix(tail) {
                return url
            }
        }
        return nil
    }

    // MARK: - Примитивный парсер блоков

    private func titleFromFirstHeader(_ text: String) -> String? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                return String(trimmed.dropFirst(2))
            }
            if trimmed.hasPrefix("## ") {
                return String(trimmed.dropFirst(3))
            }
        }
        return nil
    }

    private enum BlockKind {
        case header(String, level: Int)
        case paragraph(String)
        case bulletList([String])
        case numberedList([String])
        case emojiList([String])
        case divider
        case quote(String)
    }

    private struct Block: Identifiable {
        let id = UUID()
        let kind: BlockKind
    }

    private func parseBlocks(from text: String) -> [Block] {
        let chunks = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")

        var blocks: [Block] = []

        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Заголовки
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2))
                blocks.append(.init(kind: .header(title, level: 1)))
                continue
            }
            if trimmed.hasPrefix("## ") {
                let title = String(trimmed.dropFirst(3))
                blocks.append(.init(kind: .header(title, level: 2)))
                continue
            }

            // Горизонтальная линия
            if trimmed == "---" || trimmed == "***" {
                blocks.append(.init(kind: .divider))
                continue
            }

            let lines = trimmed
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Эмодзи-список (✅/❌/⚠️/✔️/✖️/⛔️/➕/➖)
            if let emojiItems = parseEmojiList(lines) {
                blocks.append(.init(kind: .emojiList(emojiItems)))
                continue
            }

            // Маркированный список
            if lines.allSatisfy({ $0.hasPrefix("- ") || $0.hasPrefix("* ") }) {
                let items = lines.map { String($0.dropFirst(2)) }
                blocks.append(.init(kind: .bulletList(items)))
                continue
            }

            // Нумерованный список "1. ..."
            if lines.allSatisfy({ $0.range(of: #"^\d+\.\s"#,
                                           options: .regularExpression) != nil }) {
                let items = lines.map { line -> String in
                    if let range = line.range(of: #"^\d+\.\s"#,
                                              options: .regularExpression) {
                        return String(line[range.upperBound...])
                    } else {
                        return line
                    }
                }
                blocks.append(.init(kind: .numberedList(items)))
                continue
            }

            // Цитата ">"
            if lines.allSatisfy({ $0.hasPrefix("> ") }) {
                let joined = lines
                    .map { String($0.dropFirst(2)) }
                    .joined(separator: " ")
                blocks.append(.init(kind: .quote(joined)))
                continue
            }

            // Обычный абзац
            blocks.append(.init(kind: .paragraph(trimmed)))
        }

        return blocks
    }

    private func parseEmojiList(_ lines: [String]) -> [String]? {
        let emojis = ["✅", "❌", "⚠️", "✔️", "✖️", "⛔️", "➕", "➖", "🔹", "🔸", "👉"]

        guard lines.allSatisfy({
            line in emojis.contains(where: { line.hasPrefix($0) })
        }) else {
            return nil
        }

        return lines
    }
}
