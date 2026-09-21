import Foundation

enum WallsStagesProvider {
    /// Загружает набор этапов по typeID: aac / brick / keramBlock / woodcrete / monolithic / keramzit / combo
    static func loadStages(for typeID: String) -> [Stage] {
        let canon = canonicalID(from: typeID)
        let filename = "walls_\(canon)"
        guard let pack = loadPack(named: filename) else { return [] }
        return mapPackToStages(pack)
    }

    /// Приводим входной typeID к имени json-пака:
    /// - нормализуем регистр
    /// - мапим алиасы (например, woodcrete -> arbolit)
    private static func canonicalID(from raw: String) -> String {
        let id = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // алиасы для файлов паков
        switch id {
        case "keramblock": return "keramblock"   // как в файле
        case "woodcrete":  return "arbolit"      // файл называется walls_arbolit.json
        default:           return id             // aac, brick, monolithic, keramzit, combo
        }
    }
}

private func loadPack(named name: String) -> WallsPack? {
    let bundle = Bundle.main

    // 1) Правильная папка с паками стен
    if let url = bundle.url(forResource: name,
                            withExtension: "json",
                            subdirectory: "Resources/Seeds/WallsPacks") {
        return decode(url: url)
    }

    // 2) Фолбэк — корень бандла (на случай иной сборки)
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }

    print("❌ Walls pack not found:", name)
    return nil
}

private func decode(url: URL) -> WallsPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WallsPack.self, from: data)
    } catch {
        print("❌ Decode walls pack error:", error)
        return nil
    }
}

private func mapPackToStages(_ pack: WallsPack) -> [Stage] {
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
