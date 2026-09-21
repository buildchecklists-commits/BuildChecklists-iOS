import Foundation

@MainActor
enum FinishingProgressStore {
    private static let folderName = "BC_Finishing"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // MARK: - Старый простой загрузчик (оставляем)
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - Новый MERGE-загрузчик
    // Вызывается из FinishingStagesScreen:
    //
    // if let saved = FinishingProgressStore.load(projectID: project.id, typeID: typeID) { ... }
    //
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // 🔴 ВАЖНО: FinishingStagesProvider — экземплярный,
        // поэтому создаём инстанс и вызываем метод у него.
        let provider = FinishingStagesProvider()
        let templateStages = provider.loadStages(for: typeID)

        guard !templateStages.isEmpty else {
            // если pack не загрузился — возвращаем сохранённое как есть
            return savedStages
        }

        return merge(saved: savedStages, template: templateStages)
    }

    // MARK: - Save

    static func save(projectID: UUID, stages: [Stage]) {
        let url = fileURL(projectID: projectID)
        if let data = try? JSONEncoder().encode(stages) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - MERGE логика

    private static func merge(saved: [Stage], template: [Stage]) -> [Stage] {
        guard !template.isEmpty else { return saved }

        var result: [Stage] = []

        // 1. Проходим по шаблону
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                result.append(tmplStage)
            }
        }

        // 2. Добавляем старые этапы, которых нет в шаблоне
        for oldStage in saved where !template.contains(where: { $0.title == oldStage.title }) {
            result.append(oldStage)
        }

        return result
    }

    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Проходим по шаблонным пунктам
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {

                // Обновляем только infoSlug (новые MD-файлы),
                // прогресс/фото/заметки не трогаем
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }

                merged.append(existing)
            } else {
                // Новый пункт
                merged.append(tmplItem)
            }
        }

        // 2. Добавляем старые пользовательские пункты (которых нет в шаблоне)
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
