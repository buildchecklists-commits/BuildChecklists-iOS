import Foundation

@MainActor
enum LandscapingProgressStore {
    private static let folderName = "BC_Landscaping"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // MARK: - Старый простой загрузчик (оставляем как есть)

    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - Новый MERGE-загрузчик
    // Вызывать из LandscapingStagesScreen:
    //
    // if let saved = LandscapingProgressStore.load(projectID: project.id, typeID: typeID) { ... }
    //
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // Предполагаем, что провайдер сделан по аналогии с Roof/Windows:
        // enum/struct LandscapingStagesProvider { static func loadStages(for: String) -> [Stage] }
        let templateStages = LandscapingStagesProvider.loadStages(for: typeID)

        guard !templateStages.isEmpty else {
            // Если pack не загрузился — просто возвращаем сохранённое состояние
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

        // 1. Проходим по актуальному шаблону
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                // Обновляем пункты, не теряя прогресс
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                // Новый этап, которого раньше не было — добавляем
                result.append(tmplStage)
            }
        }

        // 2. Добавляем старые этапы, которых больше нет в шаблоне
        for oldStage in saved where !template.contains(where: { $0.title == oldStage.title }) {
            result.append(oldStage)
        }

        return result
    }

    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Проходим по пунктам из шаблона
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {
                // Обновляем только infoSlug (MD-файлы),
                // прогресс/фото/заметки оставляем
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                // Новый пункт
                merged.append(tmplItem)
            }
        }

        // 2. Старые пользовательские пункты, которых нет в шаблоне — сохраняем
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
