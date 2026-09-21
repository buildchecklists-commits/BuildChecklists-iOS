import Foundation

/// StorageService с мягкой миграцией проектов и безопасным decode.
/// Для задач используется обычный decode/encode (Вариант A).
struct StorageService {

    // MARK: - URLs

    /// Файл проектов
    private var projectsURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("build_checklists_projects.json")
    }

    /// Файл расходов
    private var expensesURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("build_checklists_expenses.json")
    }

    /// Файл задач
    private var tasksURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("build_checklists_tasks.json")
    }

    // MARK: - PROJECTS (c fallback migration)

    func loadProjects() throws -> [Project] {
        guard FileManager.default.fileExists(atPath: projectsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: projectsURL)

        // 1. стандартный decode
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Project].self, from: data)
        } catch {
            print("❌ [StorageService] Стандартный decode проектов провалился: \(error)")
        }

        // 2. fallback
        return migrateProjects(from: data)
    }

    func saveProjects(_ projects: [Project]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(projects)
        try data.write(to: projectsURL, options: .atomic)
    }

    // MARK: - EXPENSES

    func loadExpenses() throws -> [ExpenseItem] {
        guard FileManager.default.fileExists(atPath: expensesURL.path) else { return [] }
        let data = try Data(contentsOf: expensesURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ExpenseItem].self, from: data)
    }

    func saveExpenses(_ expenses: [ExpenseItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(expenses)
        try data.write(to: expensesURL, options: .atomic)
    }

    // MARK: - TASKS (Вариант A: обычный decode/encode)

    func loadTasks() throws -> [TaskItem] {
        guard FileManager.default.fileExists(atPath: tasksURL.path) else {
            return []
        }

        let data = try Data(contentsOf: tasksURL)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode([TaskItem].self, from: data)
        } catch {
            print("❌ [StorageService] Ошибка decode задач: \(error)")
            return []   // в Варианте A возвращаем пустой массив
        }
    }

    func saveTasks(_ tasks: [TaskItem]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(tasks)
        try data.write(to: tasksURL, options: .atomic)
    }

    // MARK: - MIGRATION (projects only)

    private func migrateProjects(from data: Data) -> [Project] {
        print("⚠️ [StorageService] Запуск fallback-миграции проектов…")

        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            print("❌ [StorageService] JSON не читается как массив словарей")
            return []
        }

        var migrated: [Project] = []

        for dict in raw {
            if let project = migrateSingleProject(dict) {
                migrated.append(project)
            }
        }

        print("✅ [StorageService] Миграция завершена. Восстановлено проектов: \(migrated.count)")
        return migrated
    }

    private func migrateSingleProject(_ dict: [String: Any]) -> Project? {
        guard
            let idString = dict["id"] as? String,
            let id = UUID(uuidString: idString),
            let name = dict["name"] as? String,
            let address = dict["address"] as? String
        else {
            print("❌ [StorageService] Проект пропущен — нет id/name/address")
            return nil
        }

        let photoPaths = dict["photoPaths"] as? [String] ?? []
        let documentPaths = dict["documentPaths"] as? [String] ?? []
        let projectPDFPath = dict["projectPDFPath"] as? String

        let stages = migrateStages(dict["stages"])
        let contacts = migrateContacts(dict["contacts"])

        let project = Project(
            id: id,
            name: name,
            address: address,
            dateStart: parseISO(dict["dateStart"]),
            dateEnd: parseISO(dict["dateEnd"]),
            budget: parseDecimal(dict["budget"]),
            manager: dict["manager"] as? String,
            coverImagePath: dict["coverImagePath"] as? String,
            description: dict["description"] as? String,
            foundationType: nil,
            wallType: nil,
            slabType: nil,
            roofShapeType: nil,
            roofCoverType: nil,
            cardColor: dict["cardColor"] as? String,
            lastUpdated: parseISO(dict["lastUpdated"]),
            stages: stages,
            contacts: contacts,
            photoPaths: photoPaths,
            documentPaths: documentPaths,
            projectPDFPath: projectPDFPath,
            plannedBudgetByStage: [:]
        )

        print("🔄 Мигрирован проект: \(project.name)")
        return project
    }

    private func migrateStages(_ raw: Any?) -> [Stage] {
        guard let arr = raw as? [[String: Any]] else { return [] }

        var result: [Stage] = []

        for dict in arr {
            guard
                let idString = dict["id"] as? String,
                let id = UUID(uuidString: idString),
                let title = dict["title"] as? String
            else { continue }

            let items = migrateItems(dict["items"])

            let stage = Stage(
                id: id,
                title: title,
                subtitle: dict["subtitle"] as? String,
                items: items,
                plannedStart: parseISO(dict["plannedStart"]),
                plannedEnd: parseISO(dict["plannedEnd"]),
                actualStart: parseISO(dict["actualStart"]),
                actualEnd: parseISO(dict["actualEnd"]),
                delayReason: nil,
                delayComment: dict["delayComment"] as? String
            )

            result.append(stage)
        }

        return result
    }

    private func migrateContacts(_ raw: Any?) -> [ProjectContact] {
        guard let arr = raw as? [[String: Any]] else { return [] }

        var contacts: [ProjectContact] = []

        for dict in arr {
            guard let name = dict["name"] as? String else { continue }

            let role = dict["role"] as? String ?? "Контакт"
            let phone = dict["phone"] as? String ?? ""
            let note = dict["note"] as? String
            let isFavorite = dict["isFavorite"] as? Bool ?? false

            contacts.append(
                ProjectContact(
                    id: UUID(),
                    name: name,
                    role: role,
                    phone: phone,
                    note: note,
                    isFavorite: isFavorite
                )
            )
        }

        return contacts
    }

    private func migrateItems(_ raw: Any?) -> [StageItem] {
        guard let arr = raw as? [[String: Any]] else { return [] }

        var items: [StageItem] = []

        for dict in arr {
            guard
                let idString = dict["id"] as? String,
                let id = UUID(uuidString: idString),
                let title = dict["title"] as? String
            else { continue }

            // ✅ Новая модель StageItem (без isCompleted)
            let code = dict["code"] as? String ?? ""
            let note = dict["note"] as? String

            // status/severity — типы enum, из старого JSON их безопасно поднимем ТОЛЬКО если уже лежали как строки.
            // Если формат другой — оставим nil (это безопасно и компилируется).
            let statusRaw = dict["status"] as? String
            let severityRaw = dict["severity"] as? String

            let status: ItemStatus? = {
                guard let statusRaw else { return nil }
                return ItemStatus(rawValue: statusRaw)
            }()

            let severity: Severity? = {
                guard let severityRaw else { return nil }
                return Severity(rawValue: severityRaw)
            }()

            // фото/пдф
            let photoPaths = dict["photoPaths"] as? [String] ?? []
            let pdfPaths = dict["pdfPaths"] as? [String] ?? []

            let infoSlug = dict["infoSlug"] as? String

            items.append(
                StageItem(
                    id: id,
                    code: code,
                    title: title,
                    note: note,
                    status: status,
                    severity: severity,
                    photoPaths: photoPaths,
                    pdfPaths: pdfPaths,
                    infoSlug: infoSlug
                )
            )
        }

        return items
    }

    private func parseISO(_ value: Any?) -> Date? {
        guard let str = value as? String else { return nil }
        let df = ISO8601DateFormatter()
        return df.date(from: str)
    }

    private func parseDecimal(_ value: Any?) -> Decimal? {
        if let d = value as? Double { return Decimal(d) }
        if let s = value as? String, let d = Double(s) { return Decimal(d) }
        return nil
    }

    // MARK: - Account deletion (wipe local data)

    /// Полное удаление всех локальных данных приложения из Documents.
    /// Используется для "Delete Account" (App Review 5.1.1(v)), т.к. backend отсутствует.
    func wipeAllUserData() throws {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [])
        for url in items {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
