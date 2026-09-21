import Foundation

// MARK: - Публичный провайдер стадий инженерии

enum EngineeringStagesProvider {
    /// typeID пока один — "default". Если позже появятся варианты,
    /// называем файлы engineering_<typeID>.json
    static func loadStages(for typeID: String = "default") -> [Stage] {
        let filename = "engineering_\(typeID)"
        guard let pack = loadEngineeringPack(named: filename) else {
            print("⚠️ Engineering pack not found:", filename)
            return []
        }
        return mapEngineeringPackToStages(pack)
    }
}

// MARK: - Внутренние функции загрузки JSON

private func loadEngineeringPack(named name: String) -> EngineeringPack? {
    let bundle = Bundle.main

    // Основной путь — подпапка Resources/EngineeringPacks
    if let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Resources/EngineeringPacks"
    ) {
        return decodeEngineeringPack(url: url)
    }

    // Фолбэк — корень бандла
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decodeEngineeringPack(url: url)
    }

    return nil
}

private func decodeEngineeringPack(url: URL) -> EngineeringPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(EngineeringPack.self, from: data)
    } catch {
        print("❌ Decode engineering pack error:", error)
        return nil
    }
}

// MARK: - Маппинг в [Stage]

private func mapEngineeringPackToStages(_ pack: EngineeringPack) -> [Stage] {
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

// MARK: - JSON-модели под инженерный пакет

private struct EngineeringPack: Codable {
    let stages: [EngineeringStageTemplate]
}

private struct EngineeringStageTemplate: Codable {
    let title: String
    let items: [EngineeringItemTemplate]
}

private struct EngineeringItemTemplate: Codable {
    let text: String
    let infoSlug: String
}
