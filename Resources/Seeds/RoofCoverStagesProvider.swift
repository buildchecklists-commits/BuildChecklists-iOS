import Foundation

// MARK: - Провайдер стадий для покрытия крыши (по типу покрытия)

enum RoofCoverStagesProvider {
    /// typeID: metal / prof / seam / shingle / ceramic / composite / membrane
    static func loadStages(for typeID: String) -> [Stage] {
        let filename = "roof_cover_\(typeID)"   // ✅ ищем roof_cover_metal.json
        guard let pack = loadPack(named: filename) else {
            print("❌ RoofCover pack not found:", filename)
            return []
        }
        return mapPackToStages(pack)
    }
}

// MARK: - Модели пакета

private struct RoofCoverPack: Codable {
    let title: String
    let stages: [RoofCoverStageTemplate]
}

private struct RoofCoverStageTemplate: Codable {
    let title: String
    let items: [RoofCoverItemTemplate]
}

private struct RoofCoverItemTemplate: Codable {
    let text: String
    let infoSlug: String
}

// MARK: - Загрузка JSON

private func loadPack(named name: String) -> RoofCoverPack? {
    let bundle = Bundle.main

    // Пытаемся найти в подпапке Resources/RoofCoverPacks
    if let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Resources/RoofCoverPacks"
    ) {
        return decode(url: url)
    }

    // Фоллбэк — прямой поиск в бандле
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }

    print("❌ RoofCover JSON not found:", name)
    return nil
}

private func decode(url: URL) -> RoofCoverPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoofCoverPack.self, from: data)
    } catch {
        print("❌ Decode roof cover pack error:", error)
        return nil
    }
}

// MARK: - Маппинг в [Stage]

private func mapPackToStages(_ pack: RoofCoverPack) -> [Stage] {
    pack.stages.map { tmpl in
        Stage(
            id: UUID(),
            title: tmpl.title,
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
