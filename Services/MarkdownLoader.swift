import Foundation

/// Универсальный загрузчик:
/// 1) Seed’ы чек-листов из JSON (из бандла)
/// 2) Markdown-тексты (Info) из `Resources/InfoTexts/**.md`
final class MarkdownLoader {

    // MARK: - Errors

    enum LoaderError: Error, LocalizedError {
        case noSeedFilesFound
        case decodeFailed(URL)
        case infoNotFound(String)

        var errorDescription: String? {
            switch self {
            case .noSeedFilesFound:
                return "Не найдено ни одного JSON с seed-стадиями."
            case .decodeFailed(let url):
                return "Не удалось декодировать файл: \(url.lastPathComponent)"
            case .infoNotFound(let slug):
                return "Markdown по слагу '\(slug)' не найден."
            }
        }
    }

    // MARK: - Seeds

    /// Поддерживает оба формата:
    ///   1) Объект-оболочка: { "stages": [ … ] }
    ///   2) Чистый массив:   [ … ]
    private struct StagesWrapper: Decodable {
        let stages: [SeedStage]
    }

    /// Загружаем seed-файлы из приложения максимально «жёстко»:
    /// - проверяем точный путь Seeds/stages.json
    /// - перебираем все json в папке Seeds
    /// - перебираем вообще все json в бандле и отфильтровываем нужные
    /// Всё подробно логируем, чтобы сразу видеть, что именно нашлось.
    func loadSeedStages() throws -> [SeedStage] {
        BCTiming.log("loadSeedStages start (MarkdownLoader)")
        var results: [SeedStage] = []
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        func tryDecode(_ url: URL) {
            do {
                let data = try Data(contentsOf: url)

                if let wrapper = try? decoder.decode(StagesWrapper.self, from: data) {
                    debugPrint("✅ \(pretty(url)): wrapper.stages = \(wrapper.stages.count)")
                    results += wrapper.stages
                    return
                }
                if let arr = try? decoder.decode([SeedStage].self, from: data) {
                    debugPrint("✅ \(pretty(url)): array = \(arr.count)")
                    results += arr
                    return
                }
                if let single = try? decoder.decode(SeedStage.self, from: data) {
                    debugPrint("✅ \(pretty(url)): single = 1")
                    results.append(single)
                    return
                }
                debugPrint("⚠️  \(pretty(url)): формат не распознан, пропуск")
            } catch {
                debugPrint("❌ Read \(pretty(url)):", error.localizedDescription)
            }
        }

        // 0) Отладочный дамп всех JSON, доступных в бандле (один раз).
        if let allJSON = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            debugPrint("🔎 Bundle JSON total:", allJSON.count)
            for u in allJSON.prefix(20) { debugPrint("   •", pretty(u)) }
            if allJSON.count > 20 { debugPrint("   • … (ещё \(allJSON.count - 20))") }
        } else {
            debugPrint("🔎 Bundle JSON total: 0")
        }

        // 1) Точный путь: Seeds/stages.json
        if let url = Bundle.main.url(forResource: "stages", withExtension: "json", subdirectory: "Seeds") {
            tryDecode(url)
        } else {
            debugPrint("ℹ️  Seeds/stages.json не найден прямым путём")
        }

        // 2) Любые JSON в Seeds/
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "Seeds") {
            for url in urls {
                // не дублируем, если уже обработали точный stages.json
                tryDecode(url)
            }
        } else {
            debugPrint("ℹ️  В подкаталоге Seeds не найдено json-файлов")
        }

        // 3) Фоллбек: переберём вообще все json в бандле и отфильтруем по названию/пути
        if let all = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) {
            for url in all {
                let name = url.lastPathComponent.lowercased()
                if name == "stages.json" || url.path.contains("/Seeds/") || url.path.contains("/seeds/") {
                    tryDecode(url)
                }
            }
        }

        // Уникализируем по id
        var uniq: [UUID: SeedStage] = [:]
        for s in results { uniq[s.id] = s }
        var final = Array(uniq.values)

        // Если в JSON есть поле "order", отсортируем по нему (иначе — по title)
        final.sort {
            let l = $0.order ?? Int.max
            let r = $1.order ?? Int.max
            if l != r { return l < r }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        guard !final.isEmpty else {
            BCTiming.log("loadSeedStages end (0 stages, throw)")
            debugPrint("⛔️ Итог: 0 стадий после всех проходов")
            throw LoaderError.noSeedFilesFound
        }

        BCTiming.log("loadSeedStages end (\(final.count) stages)")
        debugPrint("📦 Total seed stages loaded (ordered): \(final.count)")
        return final
    }

    // MARK: - Markdown Info

    /// Загружает markdown-файл по слагу из каталога `Resources/InfoTexts`.
    /// Поддерживает как плоские, так и вложенные пути (например, `site/geology`).
    func load(slug: String) throws -> String {
        if let url = urlForSlug(slug) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        if let url = deepSearchMarkdown(named: slug + ".md") {
            return try String(contentsOf: url, encoding: .utf8)
        }
        throw LoaderError.infoNotFound(slug)
    }

    // MARK: - Helpers (Info)

    private func urlForSlug(_ slug: String) -> URL? {
        let comps = slug.split(separator: "/").map(String.init)
        guard let name = comps.last else { return nil }
        let subdir: String
        if comps.count > 1 {
            let folder = comps.dropLast().joined(separator: "/")
            subdir = "InfoTexts/\(folder)"
        } else {
            subdir = "InfoTexts"
        }
        return Bundle.main.url(forResource: name, withExtension: "md", subdirectory: subdir)
    }

    private func deepSearchMarkdown(named filename: String) -> URL? {
        guard let base = Bundle.main.resourceURL?.appendingPathComponent("InfoTexts") else { return nil }
        let fm = FileManager.default
        let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == filename { return item }
        }
        return nil
    }

    // MARK: - Small util

    private func pretty(_ url: URL) -> String {
        // урежем длинный префикс …/Containers/Bundle/Application/<UUID>/
        let p = url.path
        if let idx = p.range(of: "/BuildChecklists.app/") {
            return "…\(p[idx.lowerBound...])"
        }
        return p
    }
}
