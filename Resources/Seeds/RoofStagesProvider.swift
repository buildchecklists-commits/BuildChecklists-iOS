import Foundation

enum RoofStagesProvider {
    /// typeID: flat / gable / hip / mansard / shed / multi / tent / halfhip
    static func loadStages(for typeID: String) -> [Stage] {
        let filename = "roof_\(typeID)"
        guard let pack = loadPack(named: filename) else { return [] }
        return mapPackToStages(pack)
    }
}

private func loadPack(named name: String) -> RoofPack? {
    let bundle = Bundle.main
    if let url = bundle.url(forResource: name, withExtension: "json",
                            subdirectory: "Resources/RoofPacks") {
        return decode(url: url)
    }
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }
    print("❌ Roof pack not found:", name)
    return nil
}

private func decode(url: URL) -> RoofPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RoofPack.self, from: data)
    } catch {
        print("❌ Decode roof pack error:", error)
        return nil
    }
}

private func mapPackToStages(_ pack: RoofPack) -> [Stage] {
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
                    infoSlug: it.infoSlug  // <— пробрасываем инфо
                )
            }
        )
    }
}
