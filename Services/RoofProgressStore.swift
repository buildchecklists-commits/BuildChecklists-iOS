import Foundation

@MainActor
enum RoofProgressStore {
    private static let folderName = "BC_Roof"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // MARK: - Старый загрузчик (используется в дашборде)
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - Новый загрузчик с MERGE шаблона
    //
    // Использовать в экране крыши:
    //
    // if let saved = RoofProgressStore.load(projectID: project.id, typeID: typeID) {
    //     stages = saved
    // }
    //
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // Загружаем актуальный шаблон для типа крыши
        let templateStages = RoofStagesProvider.loadStages(for: typeID)

        guard !templateStages.isEmpty else {
            print("⚠️ Warning: Roof template for type =", typeID, "is empty.")
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

    // MARK: - MERGE

    private static func merge(saved: [Stage], template: [Stage]) -> [Stage] {
        var result: [Stage] = []

        // 1. Пробегаем по шаблону по порядку и подмешиваем
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                // обновляем пункты
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                // Новый этап
                result.append(tmplStage)
            }
        }

        // 2. Добавляем старые этапы, которые исключены из шаблона (чтобы не терять данные пользователя)
        for oldStage in saved where !template.contains(where: { $0.title == oldStage.title }) {
            result.append(oldStage)
        }

        return result
    }

    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Обрабатываем все пункты из шаблона
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {
                // Обновляем только infoSlug (остальное — прогресс пользователя)
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                // Новый пункт
                merged.append(tmplItem)
            }
        }

        // 2. Добавляем старые пункты, которые исключены из шаблона
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
