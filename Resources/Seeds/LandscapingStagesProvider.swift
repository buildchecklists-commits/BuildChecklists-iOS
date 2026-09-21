import Foundation

/// Провайдер этапов «Благоустройство»
/// Ищет JSON: Resources/LandscapingPacks/landscaping_<typeID>.json
enum LandscapingStagesProvider {
    static func loadStages(for typeID: String = "default") -> [Stage] {
        let filename = "landscaping_\(typeID)"
        guard let pack = loadPack(named: filename) else {
            print("⚠️ LandscapingStagesProvider: pack not found:", filename)
            return []
        }
        return mapPackToStages(pack)
    }
}

// MARK: - Загрузка JSON

private func loadPack(named name: String) -> LandscapingPack? {
    let bundle = Bundle.main

    // 1. Пробуем найти в подпапке Resources/LandscapingPacks
    if let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Resources/LandscapingPacks"
    ) {
        return decode(url: url)
    }

    // 2. Фолбэк — корень бандла
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }

    print("⚠️ Landscaping pack not found in bundle:", name)
    return nil
}

private func decode(url: URL) -> LandscapingPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(LandscapingPack.self, from: data)
    } catch {
        print("❌ Decode landscaping pack error:", error)
        return nil
    }
}

// MARK: - Mapping JSON -> [Stage]

private func mapPackToStages(_ pack: LandscapingPack) -> [Stage] {
    pack.stages.map { tmpl in
        Stage(
            id: UUID(),
            title: tmpl.title,
            subtitle: nil,
            items: tmpl.items.map { item in
                StageItem(
                    id: UUID(),
                    code: "",
                    title: item.text,
                    note: nil,
                    status: .na,
                    severity: .medium,
                    photoPaths: [],
                    pdfPaths: [],
                    infoSlug: item.infoSlug
                )
            }
        )
    }
}

// MARK: - JSON-модели

/// Ожидаемый формат файла landscaping_default.json:
/// {
///   "stages": [
///     {
///       "title": "...",
///       "items": [ { "text": "...", "infoSlug": "..." }, ... ]
///     },
///     ...
///   ]
/// }
private struct LandscapingPack: Codable {
    let stages: [LandscapingStageTemplate]
}

private struct LandscapingStageTemplate: Codable {
    let title: String
    let items: [LandscapingItemTemplate]
}

private struct LandscapingItemTemplate: Codable {
    let text: String
    let infoSlug: String?
}
