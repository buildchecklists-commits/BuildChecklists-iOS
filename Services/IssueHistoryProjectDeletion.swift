import Foundation

/// Outcome of reading the projects file. A missing, unreadable, or only partially recovered
/// file is not a trusted complete list for destructive reconcile or deletion verify.
enum ProjectsLoadOutcome: Equatable {
    case missingFile
    /// Every entry in the file was decoded or migrated successfully.
    case loaded([Project])
    /// Fallback migration recovered some rows but skipped others — not proof that a UUID is absent.
    case partiallyLoaded([Project])
    case unreadable(String)

    /// `true` when writing `projects.json` from the in-memory list is safe.
    /// Missing file (first install) and a fully trusted load allow writes; partial/unreadable do not.
    var allowsProjectsDiskWrite: Bool {
        switch self {
        case .missingFile, .loaded:
            return true
        case .partiallyLoaded, .unreadable:
            return false
        }
    }
}

/// Thrown when a partial/unreadable projects load must not overwrite `projects.json`.
struct ProjectsDiskWriteBlockedError: Error, Equatable, LocalizedError {
    var errorDescription: String? {
        "Список проектов загружен неполностью или повреждён. Сохранение и удаление проектов временно недоступны, чтобы не затереть записи на диске. Просмотр восстановленных проектов разрешён."
    }
}

/// Blocks history and checklist progress writes for project IDs with a saved deletion intent
/// or an in-session DEMO deletion.
nonisolated enum IssueDeletedProjectGate {
    private static let lock = NSLock()
    private static var sessionIDs: Set<UUID> = []

    static func isBlocked(_ projectID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if sessionIDs.contains(projectID) { return true }
        return ProjectDeletionIntentStore.hasIntent(projectID)
    }

    static func blockSession(_ projectID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        sessionIDs.insert(projectID)
        IssueProgressEpoch.bump()
    }

    static func clearSessionBlocks() {
        lock.lock()
        defer { lock.unlock() }
        sessionIDs.removeAll()
    }
}

/// Durable deletion intent. Restore and finalize run only for these UUIDs.
struct ProjectDeletionIntent: Codable, Equatable {
    enum Phase: String, Codable {
        /// Intent recorded; history may not be moved yet.
        case recorded
        /// History moved aside (possibly partial: JSON staged, media still live).
        case historyStaged
        /// Projects file on disk no longer contains this UUID.
        case projectsCommitted
        /// History cleanup finished; intent kept so writes stay blocked.
        case finalized
    }

    var projectID: UUID
    var projectName: String
    var phase: Phase
    var updatedAt: Date
}

nonisolated enum ProjectDeletionIntentStore {
    static let folderName = "BC_ProjectDeletionIntents"

    static func folder(fileRoot: URL) -> URL {
        fileRoot.appendingPathComponent(folderName, isDirectory: true)
    }

    static func url(fileRoot: URL, projectID: UUID) -> URL {
        folder(fileRoot: fileRoot).appendingPathComponent("\(projectID.uuidString).json")
    }

    static func hasIntent(_ projectID: UUID, fileManager: FileManager = .default) -> Bool {
        guard let root = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        return fileManager.fileExists(atPath: url(fileRoot: root, projectID: projectID).path)
    }

    static func load(fileRoot: URL, projectID: UUID, fileManager: FileManager = .default) throws -> ProjectDeletionIntent? {
        let file = url(fileRoot: fileRoot, projectID: projectID)
        guard fileManager.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectDeletionIntent.self, from: data)
    }

    static func save(_ intent: ProjectDeletionIntent, fileRoot: URL, fileManager: FileManager = .default) throws {
        let file = url(fileRoot: fileRoot, projectID: intent.projectID)
        try fileManager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(intent)
        try data.write(to: file, options: .atomic)
        let verify = try Data(contentsOf: file)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        _ = try decoder.decode(ProjectDeletionIntent.self, from: verify)
    }

    static func remove(fileRoot: URL, projectID: UUID, fileManager: FileManager = .default) throws {
        let file = url(fileRoot: fileRoot, projectID: projectID)
        if fileManager.fileExists(atPath: file.path) {
            try fileManager.removeItem(at: file)
        }
    }

    static func allIntents(fileRoot: URL, fileManager: FileManager = .default) throws -> [ProjectDeletionIntent] {
        let dir = folder(fileRoot: fileRoot)
        guard fileManager.fileExists(atPath: dir.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var result: [ProjectDeletionIntent] = []
        for url in urls where url.pathExtension == "json" {
            let data = try Data(contentsOf: url)
            result.append(try decoder.decode(ProjectDeletionIntent.self, from: data))
        }
        return result
    }
}

/// Result of deleting a project together with its issue history.
struct ProjectDeleteResult: Equatable {
    var projectRemoved: Bool
    var historyCleanupFinished: Bool
    var message: String?

    static var success: ProjectDeleteResult {
        ProjectDeleteResult(projectRemoved: true, historyCleanupFinished: true, message: nil)
    }
}

/// Stages history aside, commits the projects list, then removes history for that UUID only.
nonisolated enum IssueHistoryProjectDeletion {
    static let pendingFolderName = "BC_IssueHistoryPendingRemoval"

    enum StageOutcome: Equatable {
        case staged
        case nothingToStage
    }

    static func pendingRoot(fileRoot: URL) -> URL {
        fileRoot.appendingPathComponent(pendingFolderName, isDirectory: true)
    }

    static func pendingProjectDir(fileRoot: URL, projectID: UUID) -> URL {
        pendingRoot(fileRoot: fileRoot).appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    static func stage(projectID: UUID, store: IssueHistoryStore) throws -> StageOutcome {
        try store.stageOwnedHistoryForDeletion(projectID: projectID)
    }

    static func restore(projectID: UUID, store: IssueHistoryStore) throws {
        try store.restoreOwnedHistoryAfterFailedDeletion(projectID: projectID)
    }

    static func finalize(projectID: UUID, store: IssueHistoryStore) throws {
        try store.finalizeOwnedHistoryDeletion(projectID: projectID)
    }

    /// Reconcile only UUIDs that have a saved deletion intent.
    /// If the projects list cannot be trusted, do nothing.
    static func reconcileAfterLoad(projectsOutcome: ProjectsLoadOutcome, fileRoot: URL?) {
        guard let fileRoot else { return }
        let intents: [ProjectDeletionIntent]
        do {
            intents = try ProjectDeletionIntentStore.allIntents(fileRoot: fileRoot)
        } catch {
            return
        }
        guard !intents.isEmpty else { return }

        switch projectsOutcome {
        case .missingFile, .unreadable, .partiallyLoaded:
            // Partial recovery is not proof a UUID is absent from the source file.
            return
        case .loaded(let projects):
            let surviving = Set(projects.map(\.id))
            let store = IssueHistoryStore(fileRoot: fileRoot)
            for intent in intents {
                reconcileOne(intent: intent, surviving: surviving, store: store, fileRoot: fileRoot)
            }
        }
    }

    private static func reconcileOne(
        intent: ProjectDeletionIntent,
        surviving: Set<UUID>,
        store: IssueHistoryStore,
        fileRoot: URL
    ) {
        let id = intent.projectID
        if intent.phase == .finalized {
            return
        }

        if surviving.contains(id) {
            // Deletion did not commit the projects file — restore history, then clear intent.
            do {
                try store.restoreOwnedHistoryAfterFailedDeletion(projectID: id)
                try ProjectDeletionIntentStore.remove(fileRoot: fileRoot, projectID: id)
            } catch {
                // Keep intent so writes stay blocked. Do not invent an empty history file.
                var stuck = intent
                stuck.phase = .historyStaged
                stuck.updatedAt = Date()
                try? ProjectDeletionIntentStore.save(stuck, fileRoot: fileRoot)
            }
            return
        }

        // Projects file proves P is gone — finish history cleanup for this intent only.
        var committed = intent
        committed.phase = .projectsCommitted
        committed.updatedAt = Date()
        try? ProjectDeletionIntentStore.save(committed, fileRoot: fileRoot)

        do {
            try store.finalizeOwnedHistoryDeletion(projectID: id)
            if !store.ownedHistoryExists(projectID: id) {
                var done = committed
                done.phase = .finalized
                done.updatedAt = Date()
                try? ProjectDeletionIntentStore.save(done, fileRoot: fileRoot)
            }
        } catch {
            // Incomplete cleanup; intent remains so writes stay blocked.
        }
    }

    static func incompleteCleanupMessage(projectName: String) -> String {
        "Проект «\(projectName)» удалён из списка, но очистка сохранённой истории замечаний не завершена. Повторите попытку позже; история этого проекта больше не должна пополняться."
    }

    static func partialPersistMessage(projectName: String) -> String {
        "Проект «\(projectName)» уже удалён из сохранённого списка проектов. Связанные расходы или задачи могли сохраниться неполностью. Очистка истории продолжена; не считайте удаление отменённым."
    }

    static func uncertainProjectsVerifyMessage(projectName: String) -> String {
        "Запись списка проектов для «\(projectName)» могла пройти, но подтвердить её чтением не удалось. Удаление не завершено и не отменено: история и вложения сохранены. Список в памяти приведён к ожидаемому состоянию без этого проекта, чтобы не записать его обратно."
    }

    static func hasIncompleteCleanupIntents(fileRoot: URL) -> Bool {
        let intents = (try? ProjectDeletionIntentStore.allIntents(fileRoot: fileRoot)) ?? []
        return intents.contains { $0.phase == .projectsCommitted }
    }
}

/// Testable deletion steps for a normal (non-DEMO) project.
struct ProjectDeleteEngine {
    var fileRoot: URL
    var loadProjects: () throws -> ProjectsLoadOutcome
    var saveProjects: ([Project]) throws -> Void
    var saveExpenses: ([ExpenseItem]) throws -> Void
    var saveTasks: ([TaskItem]) throws -> Void
    var removeAttachments: (Project) -> Void
    var now: () -> Date = { Date() }

    func delete(
        existing: Project,
        allProjects: [Project],
        allExpenses: [ExpenseItem],
        allTasks: [TaskItem]
    ) throws -> (projects: [Project], expenses: [ExpenseItem], tasks: [TaskItem], result: ProjectDeleteResult) {
        // Refuse before intent/stage/attachments when the on-disk list is not fully trusted.
        let preflight = try loadProjects()
        switch preflight {
        case .partiallyLoaded, .unreadable:
            throw ProjectsDiskWriteBlockedError()
        case .missingFile, .loaded:
            break
        }

        let projectID = existing.id
        let projectName = existing.name
        let historyStore = IssueHistoryStore(fileRoot: fileRoot)

        var intent = ProjectDeletionIntent(
            projectID: projectID,
            projectName: projectName,
            phase: .recorded,
            updatedAt: now()
        )
        try ProjectDeletionIntentStore.save(intent, fileRoot: fileRoot)
        IssueProgressEpoch.bump()

        do {
            _ = try IssueHistoryProjectDeletion.stage(projectID: projectID, store: historyStore)
            intent.phase = .historyStaged
            intent.updatedAt = now()
            try ProjectDeletionIntentStore.save(intent, fileRoot: fileRoot)
        } catch {
            do {
                try IssueHistoryProjectDeletion.restore(projectID: projectID, store: historyStore)
                try ProjectDeletionIntentStore.remove(fileRoot: fileRoot, projectID: projectID)
            } catch {
                // Intent remains → writes stay blocked until restore succeeds.
            }
            throw error
        }

        let nextProjects = allProjects.filter { $0.id != projectID }
        let nextExpenses = allExpenses.filter { $0.projectID != projectID }
        let nextTasks = allTasks.filter { $0.projectID != projectID }

        // Projects list must commit first. Attachments stay until this is verified.
        do {
            try saveProjects(nextProjects)
        } catch {
            try abortBeforeProjectsCommitted(projectID: projectID, historyStore: historyStore)
            throw error
        }

        let loaded = try loadProjects()
        switch loaded {
        case .missingFile, .unreadable, .partiallyLoaded:
            // Save may have succeeded — do not restore, finalize, or remove attachments.
            // Return nextProjects so callers do not keep a stale in-memory list that could
            // rewrite the deleted project back onto disk on the next persistProjects().
            return (
                nextProjects,
                allExpenses,
                allTasks,
                ProjectDeleteResult(
                    projectRemoved: false,
                    historyCleanupFinished: false,
                    message: IssueHistoryProjectDeletion.uncertainProjectsVerifyMessage(projectName: projectName)
                )
            )
        case .loaded(let diskProjects):
            if diskProjects.contains(where: { $0.id == projectID }) {
                try abortBeforeProjectsCommitted(projectID: projectID, historyStore: historyStore)
                throw IssueHistoryError(
                    code: .writeFailed,
                    message: "Список проектов не подтвердил удаление."
                )
            }
        }

        intent.phase = .projectsCommitted
        intent.updatedAt = now()
        do {
            try ProjectDeletionIntentStore.save(intent, fileRoot: fileRoot)
        } catch {
            // Projects already committed on disk — never restore or claim cancellation.
        }

        var partialMessage: String?

        do {
            try saveExpenses(nextExpenses)
        } catch {
            partialMessage = IssueHistoryProjectDeletion.partialPersistMessage(projectName: projectName)
        }

        do {
            try saveTasks(nextTasks)
        } catch {
            partialMessage = IssueHistoryProjectDeletion.partialPersistMessage(projectName: projectName)
        }

        // Existing attachment/cover removal only after projects list confirmed the deletion.
        removeAttachments(existing)

        do {
            try IssueHistoryProjectDeletion.finalize(projectID: projectID, store: historyStore)
        } catch {
            return (
                nextProjects,
                nextExpenses,
                nextTasks,
                ProjectDeleteResult(
                    projectRemoved: true,
                    historyCleanupFinished: false,
                    message: partialMessage ?? IssueHistoryProjectDeletion.incompleteCleanupMessage(projectName: projectName)
                )
            )
        }

        if historyStore.ownedHistoryExists(projectID: projectID) {
            return (
                nextProjects,
                nextExpenses,
                nextTasks,
                ProjectDeleteResult(
                    projectRemoved: true,
                    historyCleanupFinished: false,
                    message: partialMessage ?? IssueHistoryProjectDeletion.incompleteCleanupMessage(projectName: projectName)
                )
            )
        }

        intent.phase = .finalized
        intent.updatedAt = now()
        try? ProjectDeletionIntentStore.save(intent, fileRoot: fileRoot)

        return (
            nextProjects,
            nextExpenses,
            nextTasks,
            ProjectDeleteResult(
                projectRemoved: true,
                historyCleanupFinished: true,
                message: partialMessage
            )
        )
    }

    private func abortBeforeProjectsCommitted(projectID: UUID, historyStore: IssueHistoryStore) throws {
        try IssueHistoryProjectDeletion.restore(projectID: projectID, store: historyStore)
        try ProjectDeletionIntentStore.remove(fileRoot: fileRoot, projectID: projectID)
    }
}
