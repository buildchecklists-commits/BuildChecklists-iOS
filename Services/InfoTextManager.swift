import Foundation

/// Менеджер текстов "Инфо".
/// Источники:
/// 1) Markdown-файлы в бандле по пути: InfoTexts/<slug с точками -> слэшами>.md
///    Пример: slug "foundation.piles.verticality" -> InfoTexts/foundation/piles/verticality.md
/// 2) JSON-файлы в корне папки InfoTexts (формат: [slug: text])
///
/// Кэш в памяти, загрузка лениво.
@MainActor
final class InfoTextManager {
    static let shared = InfoTextManager()

    private var cachePlain: [String: String] = [:]   // тексты из JSON или как plain fallback
    private var loadedMD: Set<String> = []           // какие md уже читали (по slug)
    private var jsonMerged = false                   // мердж JSON-ов сделан?

    private init() {}

    // MARK: - Публичные методы

    /// Возвращает plain-текст по slug (из JSON либо из md как fallback).
    func text(for slug: String) -> String? {
        let key = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        if !jsonMerged { mergeAllJSONs() }

        // если уже есть кэш — отдадим
        if let t = cachePlain[key] { return t }

        // попытка взять из md и сохранить plain-кэш (без разметки)
        if let md = loadMarkdown(slug: key) {
            cachePlain[key] = md
            return md
        }

        return nil
    }

    /// Возвращает исходный Markdown-текст из .md по slug (если есть).
    func loadMarkdown(slug: String) -> String? {
        let key = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        // Строим путь: InfoTexts/foundation/piles/verticality.md
        let mdRelativePath = "InfoTexts/" + key.replacingOccurrences(of: ".", with: "/")
        // В Bundle сначала ищем точное совпадение имени файла
        if let url = Bundle.main.url(forResource: mdRelativePath, withExtension: "md") {
            return try? String(contentsOf: url, encoding: .utf8)
        }

        // На случай, если кто-то добавил как folder reference и Xcode не находит через url(forResource:)
        // попробуем вручную пройтись по папке InfoTexts
        if let dir = Bundle.main.url(forResource: "InfoTexts", withExtension: nil) {
            let targetLastPath = key.split(separator: ".").map(String.init).joined(separator: "/") + ".md"
            if let url = findFileRecursively(in: dir, endingWith: targetLastPath) {
                return try? String(contentsOf: url, encoding: .utf8)
            }
        }

        return nil
    }

    /// Позволяет переопределить/дополнить в рантайме.
    func registerRuntimeText(slug: String, text: String) {
        cachePlain[slug] = text
    }

    // MARK: - Внутреннее: JSON

    private func mergeAllJSONs() {
        jsonMerged = true
        guard let dirURL = Bundle.main.url(forResource: "InfoTexts", withExtension: nil) else { return }

        if let fileURLs = try? FileManager.default.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for url in fileURLs where url.pathExtension.lowercased() == "json" {
                merge(jsonAt: url)
            }
        }
    }

    private func merge(jsonAt url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        if let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            for (k, v) in dict { cachePlain[k] = v }
        }
    }

    // MARK: - Поиск файла в подпапках (для folder reference)

    private func findFileRecursively(in dir: URL, endingWith tail: String) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == (tail as NSString).lastPathComponent &&
               url.path.hasSuffix(tail) {
                return url
            }
        }
        return nil
    }
}
