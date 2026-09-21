import Foundation

@MainActor
enum WindowsProgressStore {
    private static let folderName = "BC_Windows"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // MARK: - Обычная загрузка (как раньше)
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - MERGE ЗАГРУЗКА (Новый вариант — использовать в экране окон)
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // Загружаем актуальный шаблон окон
        // предполагаем, что он выглядит так:
        // WindowsStagesProvider.loadStages(for: typeID)
        let templateStages = WindowsStagesProvider.loadStages(for: typeID)

        guard !templateStages.isEmpty else {
            return savedStages
        }

        return merge(saved: savedStages, template: templateStages)
    }

    static func save(projectID: UUID, stages: [Stage]) {
        let url = fileURL(projectID: projectID)
        if let data = try? JSONEncoder().encode(stages) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - MERGE ЛОГИКА

    private static func merge(saved: [Stage], template: [Stage]) -> [Stage] {
        guard !template.isEmpty else { return saved }

        var result: [Stage] = []

        // 1. Идём по шаблону и обновляем/создаём этапы
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                result.append(tmplStage)
            }
        }

        // 2. Добавляем старые этапы, которые отсутствуют в шаблоне (чтобы не потерять пользовательские данные)
        for oldStage in saved where !template.contains(where: { $0.title == oldStage.title }) {
            result.append(oldStage)
        }

        return result
    }

    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Обрабатываем пункты из шаблона
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {
                // Обновим infoSlug (MD-файлы) — прогресс, заметки и фото останутся
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                merged.append(tmplItem)
            }
        }

        // 2. Добавим старые пользовательские пункты, которые исключены из шаблона
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
