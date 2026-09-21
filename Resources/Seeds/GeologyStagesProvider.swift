import Foundation

enum GeologyStagesProvider {
    /// Один базовый пак: geology_default.json
    static func loadStages() -> [Stage] {
        guard let pack = loadPack(named: "geology_default") else { return [] }
        return mapPackToStages(pack)
    }
}

private func loadPack(named name: String) -> GeologyPack? {
    let bundle = Bundle.main
    if let url = bundle.url(forResource: name, withExtension: "json",
                            subdirectory: "Resources/GeologyPacks") {
        return decode(url: url)
    }
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }
    print("❌ Geology pack not found:", name)
    return nil
}

private func decode(url: URL) -> GeologyPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(GeologyPack.self, from: data)
    } catch {
        print("❌ Decode geology pack error:", error)
        return nil
    }
}

private func mapPackToStages(_ pack: GeologyPack) -> [Stage] {
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
