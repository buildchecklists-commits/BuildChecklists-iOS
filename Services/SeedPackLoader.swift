import Foundation

// MARK: - DTO структуры для чтения JSON-паков
private struct StagePackDTO: Decodable {
    struct ItemDTO: Decodable {
        let title: String
        let code: String?
    }
    let title: String
    let items: [ItemDTO]
}

// MARK: - Loader для JSON-паков из Seeds/SeedsPacks
struct SeedPackLoader {

    /// Читает один JSON-файл пакета из подпапки Resources/Seeds/SeedsPacks
    func loadSinglePack(named baseName: String) -> Stage? {
        // Чистое имя (без .json)
        let clean = baseName.replacingOccurrences(of: ".json", with: "")
        let subdir = "Seeds/SeedsPacks"

        // Ищем JSON-файл
        guard let url = Bundle.main.url(forResource: clean, withExtension: "json", subdirectory: subdir) else {
            #if DEBUG
            print("⚠️ SeedPack not found:", clean)
            #endif
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let dto = try JSONDecoder().decode(StagePackDTO.self, from: data)

            // Преобразуем DTO → StageItem
            let items: [StageItem] = dto.items.map {
                StageItem(
                    id: UUID(),
                    code: $0.code ?? "",
                    title: $0.title,
                    status: .na,
                    severity: .medium,
                    photoPaths: [],
                    pdfPaths: []
                )
            }

            #if DEBUG
            print("✅ Loaded pack:", clean, "(\(items.count) items)")
            #endif

            return Stage(
                id: UUID(),
                title: dto.title,
                subtitle: nil,
                items: items
            )

        } catch {
            #if DEBUG
            print("❌ Error loading pack '\(clean)':", error.localizedDescription)
            #endif
            return nil
        }
    }
}
