import Foundation

enum SlabStagesProvider {
    /// typeID: monolithic / pb / pc / steel / wood
    static func loadStages(for typeID: String) -> [Stage] {
        let filename = "slab_\(typeID)"
        guard let pack = loadPack(named: filename) else { return [] }
        return mapPackToStages(pack)
    }
}

private func loadPack(named name: String) -> SlabPack? {
    let bundle = Bundle.main
    if let url = bundle.url(forResource: name, withExtension: "json",
                            subdirectory: "Resources/SlabPacks") {
        return decode(url: url)
    }
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }
    print("❌ Slab pack not found:", name)
    return nil
}

private func decode(url: URL) -> SlabPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SlabPack.self, from: data)
    } catch {
        print("❌ Decode slab pack error:", error)
        return nil
    }
}

private func mapPackToStages(_ pack: SlabPack) -> [Stage] {
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
