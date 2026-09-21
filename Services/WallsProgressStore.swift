import Foundation

@MainActor
enum WallsProgressStore {
    private static let folderName = "BC_Walls"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    // Старый простой загрузчик — можно использовать в дашборде, если нужен только сохранённый прогресс
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // Новый загрузчик с MERGE шаблона.
    // ВЫЗЫВАТЬ из WallsStagesScreen:
    // if let saved = WallsProgressStore.load(projectID: project.id, typeID: typeID) { ... }
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)

        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        // 🔴 ВАЖНО: здесь был вызов без параметра, из-за этого и ошибка.
        //           Теперь передаём typeID.
        let templateStages = WallsStagesProvider.loadStages(for: typeID)

        guard !templateStages.isEmpty else {
            // если по какой-то причине шаблон не загрузился — возвращаем сохранённые данные как есть
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

    // MARK: - Merge шаблона и сохранённых данных

    private static func merge(saved: [Stage], template: [Stage]) -> [Stage] {
        guard !template.isEmpty else { return saved }

        var result: [Stage] = []

        // 1. Проходим по актуальному шаблону
        for tmplStage in template {
            if var existing = saved.first(where: { $0.title == tmplStage.title }) {
                // Есть сохранённый этап с таким же title — мержим пункты
                existing.items = mergeItems(saved: existing.items, template: tmplStage.items)
                result.append(existing)
            } else {
                // Новый этап, которого раньше не было — добавляем целиком
                result.append(tmplStage)
            }
        }

        // 2. Этапы, которых больше нет в шаблоне, но есть у пользователя — не выбрасываем
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
                // Сохраняем прогресс/заметки/файлы, но обновляем infoSlug на актуальный
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                // Новый пункт
                merged.append(tmplItem)
            }
        }

        // 2. Старые пользовательские пункты, которых больше нет в шаблоне — добавляем в конец
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
