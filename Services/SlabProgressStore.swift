import Foundation

@MainActor
enum SlabProgressStore {
    private static let folderName = "BC_Slab"

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
    // Используется там, где просто нужно прочитать сохранённый прогресс
    // (дашборд, сводные экраны и т.п.).
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Stage].self, from: data)
    }

    // MARK: - Загрузка с учётом типа перекрытия и актуального шаблона
    //
    // ВЫЗЫВАТЬ ЭТОТ метод из экрана плит/перекрытий, где есть typeID:
    //   "monolithic" / "pb" / "pc" / "steel" / "wood"
    //
    // Логика:
    // 1) читаем сохранённые стадии из файла;
    // 2) берём свежий шаблон из SlabStagesProvider.loadStages(for: typeID);
    // 3) мержим: добавляем новые этапы/пункты, обновляем infoSlug,
    //    при этом статусы/заметки/файлы пользователя сохраняются.
    static func load(projectID: UUID, typeID: String) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        let templateStages = SlabStagesProvider.loadStages(for: typeID)
        guard !templateStages.isEmpty else {
            // если по какой-то причине шаблон не загрузился —
            // просто возвращаем сохранённые данные как есть
            return savedStages
        }

        return merge(saved: savedStages, template: templateStages)
    }

    // MARK: - Сохранение

    static func save(projectID: UUID, stages: [Stage]) {
        let url = fileURL(projectID: projectID)
        if let data = try? JSONEncoder().encode(stages) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Merge шаблона и сохранённых данных

    /// Объединяем сохранённые стадии с текущим шаблоном.
    /// Сопоставление по `title` этапа.
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

    /// Объединяем пункты этапа. Сопоставление по `title` пункта.
    private static func mergeItems(saved: [StageItem], template: [StageItem]) -> [StageItem] {
        var merged: [StageItem] = []

        // 1. Берём все пункты из шаблона по порядку
        for tmplItem in template {
            if var existing = saved.first(where: { $0.title == tmplItem.title }) {
                // Сохраняем статус/заметки/файлы пользователя,
                // но обновляем infoSlug на актуальный из шаблона
                if existing.infoSlug != tmplItem.infoSlug {
                    existing.infoSlug = tmplItem.infoSlug
                }
                merged.append(existing)
            } else {
                // Новый пункт — добавляем как есть
                merged.append(tmplItem)
            }
        }

        // 2. Пункты, которые были у пользователя, но которых уже нет в шаблоне — добавляем в конец
        for oldItem in saved where !template.contains(where: { $0.title == oldItem.title }) {
            merged.append(oldItem)
        }

        return merged
    }
}
