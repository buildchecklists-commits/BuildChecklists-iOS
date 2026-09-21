import Foundation

/// Провайдер загрузки и маппинга сидов для этапов фундамента.
enum FoundationStagesProvider {

    // MARK: - Публичный API

    /// Загружает пакет (например, "foundation_pile") и маппит его в твои модели `Stage` / `StageItem`.
    static func loadStages(named name: String, in bundle: Bundle = .main) -> [Stage] {
        guard let pack = loadPack(named: name, in: bundle) else { return [] }
        return mapPackToStages(pack)
    }

    // MARK: - Приватная загрузка JSON

    private static func loadPack(named name: String, in bundle: Bundle) -> FoundationPack? {
        // Вариант 1: если папки добавлены как folder reference: Resources/Seeds/FoundationPacks
        if let url = bundle.url(forResource: name,
                                withExtension: "json",
                                subdirectory: "Resources/Seeds/FoundationPacks") {
            return decode(url: url)
        }
        // Вариант 2: если файлы лежат на верхнем уровне бандла
        if let url = bundle.url(forResource: name, withExtension: "json") {
            return decode(url: url)
        }
        print("⛔️ Foundation pack not found:", name)
        return nil
    }

    private static func decode(url: URL) -> FoundationPack? {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(FoundationPack.self, from: data)
        } catch {
            print("⛔️ Decode foundation pack error:", error)
            return nil
        }
    }

    // MARK: - Маппинг в твои модели Stage/StageItem

    private static func mapPackToStages(_ pack: FoundationPack) -> [Stage] {
        pack.stages.map { tmpl in
            Stage(
                id: UUID(),
                title: tmpl.title,
                items: tmpl.items.map { it in
                    // ⬇️ Главное изменение: берём текст из объекта `FoundationItemTemplate`
                    StageItem(
                        id: UUID(),
                        code: "",                      // если нужно — подставь it.code, когда появится
                        title: it.text,                // было: просто String; теперь: поле text
                        status: .na,
                        severity: .medium,
                        photoPaths: [],
                        pdfPaths: [],
                        infoSlug: it.infoSlug          // ⬅︎ если в твоём StageItem нет такого поля — удали эту строку
                    )
                }
            )
        }
    }
}
