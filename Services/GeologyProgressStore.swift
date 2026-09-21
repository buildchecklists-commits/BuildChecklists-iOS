import Foundation

@MainActor
enum GeologyProgressStore {
    private static let folderName = "BC_Geology"

    private static func fileURL(projectID: UUID) -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = root.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(projectID.uuidString).json")
    }

    /// Загружаем сохранённые стадии и мягко совмещаем их
    /// с актуальным шаблоном из GeologyStagesProvider.
    ///
    /// Логика:
    /// - если файла нет — возвращаем nil (экран сам возьмёт шаблон целиком);
    /// - если файл есть — декодируем сохранённые стадии и
    ///   добавляем в них новые этапы/пункты из шаблона,
    ///   не трогая уже отмеченный прогресс.
    static func load(projectID: UUID) -> [Stage]? {
        let url = fileURL(projectID: projectID)
        guard
            let data = try? Data(contentsOf: url),
            let savedStages = try? JSONDecoder().decode([Stage].self, from: data)
        else {
            return nil
        }

        let templateStages = GeologyStagesProvider.loadStages()
        return merge(saved: savedStages, template: templateStages)
    }

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
                // но при этом обновляем infoSlug на актуальный из шаблона
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
