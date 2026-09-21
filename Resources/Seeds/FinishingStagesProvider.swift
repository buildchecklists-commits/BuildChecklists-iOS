import Foundation

/// Провайдер стадий для раздела "Отделка".
///
/// Умеет работать с ДВУМЯ форматами JSON:
///
/// 1) НОВЫЙ (нормальный):
/// {
///   "title": "Отделка — базовый комплект",
///   "stages": [
///     { "title": "...", "items": [ { "text": "...", "infoSlug": "..." }, ... ] },
///     ...
///   ]
/// }
///
/// 2) СТАРЫЙ (как у тебя сейчас):
/// {
///   "title": "Подготовка коробки под отделку",
///   "items": [ { "text": "...", "infoSlug": "..." }, ... ]
/// }
/// ,
/// {
///   "title": "Черновая инженерия (стены и потолок)",
///   "items": [ ... ]
/// }
/// , ...
///
/// Во втором случае мы читаем файл как текст, оборачиваем его в [ ... ]
/// и декодируем как массив объектов.
struct FinishingStagesProvider {

    /// Пока один тип — "default"
    func loadStages(for typeID: String = "default") -> [Stage] {
        let filename = "finishing_\(typeID)"

        // 1. Ищем файл в Resources/FinishingPacks
        let bundle = Bundle.main
        let url =
            bundle.url(
                forResource: filename,
                withExtension: "json",
                subdirectory: "Resources/FinishingPacks"
            )
            ?? bundle.url(forResource: filename, withExtension: "json")

        guard let url else {
            print("⚠️ Finishing pack not found in bundle:", filename)
            return []
        }

        do {
            let data = try Data(contentsOf: url)

            // Сначала пытаемся декодировать "новый" формат с title + stages
            if let pack = try? JSONDecoder().decode(FinishingPack.self, from: data) {
                return mapPackToStages(pack)
            }

            // Если не получилось — пробуем "старый" формат:
            // несколько объектов подряд, разделённых запятыми.
            if let looseStages = try? decodeLooseStagesArray(from: data) {
                return looseStages.map { mapFileToStage($0) }
            }

            print("❌ FinishingStagesProvider: unable to decode", filename)
            return []
        } catch {
            print("❌ FinishingStagesProvider read error:", error)
            return []
        }
    }
}

// MARK: - Декодирование "кривого" формата (несколько объектов подряд)

/// Читает Data как UTF-8 строку, оборачивает в [ ... ],
/// декодирует как массив { title, items }.
private func decodeLooseStagesArray(from data: Data) throws -> [FinishingStageFile] {
    guard let raw = String(data: data, encoding: .utf8) else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [],
                  debugDescription: "Unable to decode finishing JSON as UTF-8 string")
        )
    }

    let wrapped = "[\n" + raw + "\n]"
    guard let wrappedData = wrapped.data(using: .utf8) else {
        throw DecodingError.dataCorrupted(
            .init(codingPath: [],
                  debugDescription: "Unable to build wrapped JSON data")
        )
    }

    return try JSONDecoder().decode([FinishingStageFile].self, from: wrappedData)
}

// MARK: - Mapping в Stage / StageItem

/// Новый формат: pack со списком стадий
private func mapPackToStages(_ pack: FinishingPack) -> [Stage] {
    pack.stages.map { file in
        mapFileToStage(file)
    }
}

/// Старый/универсальный формат: один этап
private func mapFileToStage(_ file: FinishingStageFile) -> Stage {
    Stage(
        id: UUID(),
        title: file.title,      // тут уже полностью "Этап 1. ..." или что ты напишешь
        subtitle: nil,
        items: file.items.map { tmpl in
            StageItem(
                id: UUID(),
                code: "",
                title: tmpl.text,        // текст из JSON кладём в title
                note: nil,
                status: .na,
                severity: .medium,
                photoPaths: [],
                pdfPaths: [],
                infoSlug: tmpl.infoSlug  // может быть nil — это нормально
            )
        }
    )
}

// MARK: - JSON-модели

/// Новый формат: общий pack с массивом stages
private struct FinishingPack: Codable {
    let title: String
    let stages: [FinishingStageFile]
}

/// Универсальная стадия: title + items
private struct FinishingStageFile: Codable {
    let title: String
    let items: [FinishingItemTemplate]
}

private struct FinishingItemTemplate: Codable {
    let text: String
    let infoSlug: String?
}
