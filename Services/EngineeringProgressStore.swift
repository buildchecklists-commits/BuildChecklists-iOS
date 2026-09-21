import Foundation

@MainActor
enum EngineeringProgressStore {
    private static let folderName = "BC_Engineering"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // MARK: - Простой загрузчик (как было раньше)
    //
    // Можно использовать в дашбордах / сводках, где просто нужно взять сохранённые стадии
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - Загрузка с MERGE шаблона
    //
    // Использовать в EngineeringStagesScreen, где есть typeID
    // (сейчас это всегда "default", но позже может быть больше вариантов).
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // Берём актуальный шаблон инженерки для переданного типа
        let templateStages = EngineeringStagesProvider.loadStages(for: typeID)

        // Если шаблон вдруг пустой — не ломаем пользователя, а отдаём то, что было
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

    // MARK: - MERGE шаблона и сохранённых данных

    /// Объединяем сохранённые стадии с текущим шаблоном.
    /// Сопоставление по `title` этапа.
    private static func merge(saved: [Stage], template: [Stage]) -> [Stage] {
        guard !template.isEmpty else { return saved }

        var result: [Stage] = []

        // 1. Идём по шаблону
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                // Обновляем пункты, сохраняя прогресс
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                // Новый этап — добавляем целиком
                result.append(tmplStage)
            }
        }

        // 2. Этапы, которые были у пользователя, но исчезли из шаблона — не выбрасываем
        for oldStage in saved where !template.contains(where: { $0.title == oldStage.title }) {
            result.append(oldStage)
        }

        return result
    }

    /// Объединяем пункты этапа. Сопоставление по `title` пункта.
    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Идём по пунктам шаблона
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {
                // Сохраняем статус/заметки/фото, но infoSlug обновляем по шаблону
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                // Новый пункт
                merged.append(tmplItem)
            }
        }

        // 2. Пункты, которых больше нет в шаблоне — добавляем в конец, чтобы не потерять заметки/фото
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
