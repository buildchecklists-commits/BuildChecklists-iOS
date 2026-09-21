import Foundation

enum WindowsStagesProvider {
    /// Пока один вариант окон — "default".
    static func loadStages(for typeID: String = "default") -> [Stage] {
        let filename = "windows_\(typeID)"
        guard let pack = loadPack(named: filename) else {
            print("⚠️ Windows pack not found:", filename)
            return []
        }
        return mapPackToStages(pack)
    }
}

// MARK: - Loading JSON

private func loadPack(named name: String) -> WindowsPack? {
    let bundle = Bundle.main

    // Ищем строго в Resources/WindowsPacks
    if let url = bundle.url(
        forResource: name,
        withExtension: "json",
        subdirectory: "Resources/WindowsPacks"
    ) {
        return decode(url: url)
    }

    // fallback в корень бандла (на всякий случай)
    if let url = bundle.url(forResource: name, withExtension: "json") {
        return decode(url: url)
    }

    print("⚠️ Windows pack not found in bundle:", name)
    return nil
}

private func decode(url: URL) -> WindowsPack? {
    do {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WindowsPack.self, from: data)
    } catch {
        print("❌ Decode windows pack error:", error)
        return nil
    }
}

// MARK: - Mapping JSON → [Stage]

private func mapPackToStages(_ pack: WindowsPack) -> [Stage] {
    pack.stages.map { stage in
        Stage(
            id: UUID(),
            title: stage.title,
            subtitle: nil,
            items: stage.items.map { item in
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

// MARK: - JSON models

/// Формат файла windows_default.json:
/// {
///   "title": "Окна",
///   "stages": [
///      {
///        "title": "Этап 1. ...",
///        "items": [
///            { "text": "...", "infoSlug": "windows/..." }
///        ]
///      }
///   ]
/// }
private struct WindowsPack: Codable {
    let title: String
    let stages: [WindowsStageTemplate]
}

private struct WindowsStageTemplate: Codable {
    let title: String
    let items: [WindowsItemTemplate]
}

private struct WindowsItemTemplate: Codable {
    let text: String
    let infoSlug: String
}
