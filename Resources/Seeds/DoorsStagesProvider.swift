import Foundation

enum DoorsStagesProvider {
    /// typeID: пока один — "default". Если потом захочешь разные наборы, добавим doors_<typeID>.json
    static func loadStages(for typeID: String = "default") -> [Stage] {
        let filename = "doors_\(typeID)"
        guard let pack = loadPack(named: filename) else {
            print("⚠️ Doors pack not found:", filename)
            return []
        }
        return mapPackToStages(pack)
    }
}

// MARK: - Загрузка JSON

private func loadPack(named name: String) -> DoorsPack? {
    let bundle = Bundle.main

    // Ищем в подпапке Resources/DoorsPacks
    if let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Resources/DoorsPacks"
    ) {
        return decode(url: url)
    }

    // Фолбэк — вдруг файл лежит в корне бандла
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }

    print("⚠️ Doors pack not found in bundle:", name)
    return nil
}

private func decode(url: URL) -> DoorsPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(DoorsPack.self, from: data)
    } catch {
        print("❌ Decode doors pack error:", error)
        return nil
    }
}

// MARK: - Mapping JSON -> [Stage]

private func mapPackToStages(_ pack: DoorsPack) -> [Stage] {
    pack.stages.map { tmpl in
        Stage(
            id: UUID(),
            title: tmpl.title,
            subtitle: nil,
            items: tmpl.items.map { it in
                StageItem(
                    id: UUID(),
                    code: "",
                    title: it.text,
                    status: .na,
                    severity: .medium,
                    photoPaths: [],
                    pdfPaths: [],
                    infoSlug: it.infoSlug
                )
            }
        )
    }
}

// MARK: - JSON-модели

/// В файле doors_default.json:
/// {
///   "title": "Двери — базовый комплект",
///   "stages": [ ... ]
/// }
private struct DoorsPack: Codable {
    let title: String
    let stages: [DoorsStageTemplate]
}

private struct DoorsStageTemplate: Codable {
    let title: String
    let items: [DoorsItemTemplate]
}

private struct DoorsItemTemplate: Codable {
    let text: String
    let infoSlug: String
}
