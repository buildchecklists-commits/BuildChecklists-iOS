import Foundation

/// Remembers whether the last projects load was complete enough to allow rewriting `projects.json`.
nonisolated final class ProjectsDiskWriteGate: @unchecked Sendable {
    private let lock = NSLock()
    private var allowed = true

    var isWriteAllowed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return allowed
    }

    func apply(_ outcome: ProjectsLoadOutcome) {
        lock.lock()
        defer { lock.unlock() }
        allowed = outcome.allowsProjectsDiskWrite
    }

    func ensureWritable() throws {
        lock.lock()
        let ok = allowed
        lock.unlock()
        if !ok { throw ProjectsDiskWriteBlockedError() }
    }
}

/// StorageService с мягкой миграцией проектов и безопасным decode.
/// Для задач используется обычный decode/encode (Вариант A).
struct StorageService {

    private let documentsDirectory: URL
    /// Shared across copies of this value-typed service so load outcome gates later saves.
    private let projectsWriteGate: ProjectsDiskWriteGate

    /// - Parameter documentsDirectory: Override for isolated probes. Production uses the app Documents directory.
    init(documentsDirectory: URL? = nil, projectsWriteGate: ProjectsDiskWriteGate = ProjectsDiskWriteGate()) {
        if let documentsDirectory {
            self.documentsDirectory = documentsDirectory
        } else {
            self.documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        self.projectsWriteGate = projectsWriteGate
    }

    /// Whether the last `loadProjectsOutcome()` allows rewriting the projects file.
    var isProjectsDiskWriteAllowed: Bool { projectsWriteGate.isWriteAllowed }

    // MARK: - URLs

    /// Файл проектов
    private var projectsURL: URL {
        documentsDirectory.appendingPathComponent("build_checklists_projects.json")
    }

    /// Файл расходов
    private var expensesURL: URL {
        documentsDirectory.appendingPathComponent("build_checklists_expenses.json")
    }

    /// Файл задач
    private var tasksURL: URL {
        documentsDirectory.appendingPathComponent("build_checklists_tasks.json")
    }

    // MARK: - PROJECTS (c fallback migration)

    /// Distinguishes a missing file from a trusted empty list, a partial migration, and unreadable data.
    /// Only `.loaded` means every row was recovered — safe for destructive reconcile / deletion verify.
    /// Updates the write gate: partial/unreadable block later `saveProjects` until a trusted load succeeds.
    func loadProjectsOutcome() -> ProjectsLoadOutcome {
        let outcome: ProjectsLoadOutcome
        if !FileManager.default.fileExists(atPath: projectsURL.path) {
            outcome = .missingFile
        } else {
            let data: Data
            do {
                data = try Data(contentsOf: projectsURL)
            } catch {
                outcome = .unreadable(error.localizedDescription)
                projectsWriteGate.apply(outcome)
                return outcome
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                outcome = .loaded(try decoder.decode([Project].self, from: data))
                projectsWriteGate.apply(outcome)
                return outcome
            } catch {
                print("❌ [StorageService] Стандартный decode проектов провалился: \(error)")
            }

            guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                outcome = .unreadable("JSON проектов не читается как массив")
                projectsWriteGate.apply(outcome)
                return outcome
            }
            if raw.isEmpty {
                outcome = .loaded([])
            } else {
                let migrated = migrateProjects(from: data)
                if migrated.isEmpty {
                    outcome = .unreadable("Миграция проектов не дала ни одной записи")
                } else if migrated.count != raw.count {
                    // Skipped rows may still represent projects in the source file.
                    print("⚠️ [StorageService] Частичная миграция: \(migrated.count)/\(raw.count) — список не достоверен для удаления истории")
                    outcome = .partiallyLoaded(migrated)
                } else {
                    outcome = .loaded(migrated)
                }
            }
        }
        projectsWriteGate.apply(outcome)
        return outcome
    }

    func loadProjects() throws -> [Project] {
        switch loadProjectsOutcome() {
        case .missingFile:
            return []
        case .loaded(let projects):
            return projects
        case .partiallyLoaded:
            throw NSError(
                domain: "StorageService",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Список проектов восстановлен лишь частично"]
            )
        case .unreadable(let message):
            throw NSError(
                domain: "StorageService",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    func saveProjects(_ projects: [Project]) throws {
        try projectsWriteGate.ensureWritable()
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
