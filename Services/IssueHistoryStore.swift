import Foundation

/// In-memory history for one DEMO session. Dropping the instance drops the history.
/// The store never writes these records to disk.
nonisolated final class IssueHistoryMemorySession: @unchecked Sendable {
    nonisolated struct PhotoKey: Hashable, Sendable {
        var projectID: UUID
        var eventID: UUID
        var fileName: String
    }

    private let lock = NSLock()
    private var documents: [UUID: IssueHistoryDocument] = [:]
    private var photos: [PhotoKey: Data] = [:]

    func document(for projectID: UUID) -> IssueHistoryDocument? {
        lock.lock()
        defer { lock.unlock() }
        return documents[projectID]
    }

    func photo(projectID: UUID, eventID: UUID, fileName: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return photos[PhotoKey(projectID: projectID, eventID: eventID, fileName: fileName)]
    }

    func save(document: IssueHistoryDocument, newPhotos: [PhotoKey: Data]) {
        lock.lock()
        defer { lock.unlock() }
        documents[document.projectID] = document
        for (key, data) in newPhotos {
            photos[key] = data
        }
    }

    func discard(projectID: UUID) {
        lock.lock()
        defer { lock.unlock() }
        documents[projectID] = nil
        photos = photos.filter { $0.key.projectID != projectID }
    }
}

/// History file and its own photo copies. Does not read or write checklist progress, notes, or live photos.
nonisolated final class IssueHistoryStore: @unchecked Sendable {
    static let historyFolderName = "BC_IssueHistory"
    static let mediaFolderName = "BC_IssueHistoryMedia"

    private let lock = NSLock()
    private let fileRoot: URL?
    private let memory: IssueHistoryMemorySession?
    private let fileManager: FileManager

    /// Persistent store rooted at `fileRoot` (the app will pass Documents later).
    init(fileRoot: URL, fileManager: FileManager = .default) {
        self.fileRoot = fileRoot
        self.memory = nil
        self.fileManager = fileManager
    }

    /// DEMO session. `fileRoot` is accepted only so a test can prove it is never touched.
    init(memorySession: IssueHistoryMemorySession, fileRoot: URL? = nil, fileManager: FileManager = .default) {
        self.fileRoot = fileRoot
        self.memory = memorySession
        self.fileManager = fileManager
    }

    func load(projectID: UUID) throws -> IssueHistoryDocument {
        lock.lock()
        defer { lock.unlock() }
        if IssueDeletedProjectGate.isBlocked(projectID) {
            throw IssueHistoryError(
                code: .projectDeleted,
                message: "Проект удалён. История замечаний больше не записывается."
            )
        }
        return try loadUnlocked(projectID: projectID)
    }

    /// True when live JSON or media for this UUID still exist (not counting pending-removal trash).
    func ownedHistoryExists(projectID: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if memory != nil {
            return memory?.document(for: projectID) != nil
        }
        guard let fileRoot else { return false }
        if liveHistoryExistsUnlocked(projectID: projectID, root: fileRoot) { return true }
        let pending = IssueHistoryProjectDeletion.pendingProjectDir(fileRoot: fileRoot, projectID: projectID)
        return fileManager.fileExists(atPath: pending.path)
    }

    /// Moves JSON and media for `projectID` into `BC_IssueHistoryPendingRemoval/<P>/`.
    /// Idempotent: does not wipe an already-staged partial pending dir.
    /// Corrupt JSON is moved as an opaque file. Neighbor UUIDs are not touched.
    @discardableResult
    func stageOwnedHistoryForDeletion(projectID: UUID) throws -> IssueHistoryProjectDeletion.StageOutcome {
        lock.lock()
        defer { lock.unlock() }
        if let memory {
            // DEMO memory discard is irreversible — callers must only reach here after committed removal.
            let had = memory.document(for: projectID) != nil
            memory.discard(projectID: projectID)
            return had ? .staged : .nothingToStage
        }
        guard let fileRoot else {
            throw IssueHistoryError(code: .writeFailed, message: "Каталог истории не задан")
        }
        let json = Self.jsonURL(root: fileRoot, projectID: projectID)
        let media = Self.projectMediaURL(root: fileRoot, projectID: projectID)
        let pending = IssueHistoryProjectDeletion.pendingProjectDir(fileRoot: fileRoot, projectID: projectID)
        let stagedJSON = pending.appendingPathComponent("document.json")
        let stagedMedia = pending.appendingPathComponent("media", isDirectory: true)
        let hasJSON = fileManager.fileExists(atPath: json.path)
        let hasMedia = fileManager.fileExists(atPath: media.path)
        let alreadyStaged =
            fileManager.fileExists(atPath: stagedJSON.path)
            || fileManager.fileExists(atPath: stagedMedia.path)

        guard hasJSON || hasMedia || alreadyStaged else { return .nothingToStage }

        try fileManager.createDirectory(at: pending, withIntermediateDirectories: true)
        if hasJSON {
            try moveItemReplacing(at: json, to: stagedJSON)
        }
        if hasMedia {
            // If this fails after JSON was moved, leave pending as-is for restore.
            try moveItemReplacing(at: media, to: stagedMedia)
        }
        return .staged
    }

    /// Restores staged history to live paths. Throws if a staged item cannot be moved back.
    /// Does not invent an empty history file when there is nothing to restore.
    func restoreOwnedHistoryAfterFailedDeletion(projectID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if memory != nil { return }
        guard let fileRoot else {
            throw IssueHistoryError(code: .writeFailed, message: "Каталог истории не задан")
        }
        let pending = IssueHistoryProjectDeletion.pendingProjectDir(fileRoot: fileRoot, projectID: projectID)
        guard fileManager.fileExists(atPath: pending.path) else { return }
        let stagedJSON = pending.appendingPathComponent("document.json")
        let stagedMedia = pending.appendingPathComponent("media", isDirectory: true)
        if fileManager.fileExists(atPath: stagedJSON.path) {
            let live = Self.jsonURL(root: fileRoot, projectID: projectID)
            try fileManager.createDirectory(at: live.deletingLastPathComponent(), withIntermediateDirectories: true)
            try moveItemReplacing(at: stagedJSON, to: live)
        }
        if fileManager.fileExists(atPath: stagedMedia.path) {
            let live = Self.projectMediaURL(root: fileRoot, projectID: projectID)
            try moveItemReplacing(at: stagedMedia, to: live)
        }
        // Pending must be empty of staged content before removal.
        if fileManager.fileExists(atPath: stagedJSON.path) || fileManager.fileExists(atPath: stagedMedia.path) {
            throw IssueHistoryError(
                code: .writeFailed,
                message: "Не удалось полностью вернуть историю замечаний после отмены удаления."
            )
        }
        if fileManager.fileExists(atPath: pending.path) {
            try fileManager.removeItem(at: pending)
        }
        removeEmptyDirectory(pending.deletingLastPathComponent())
    }

    /// Deletes pending-removal trash and any leftover live JSON/media for this UUID only.
    func finalizeOwnedHistoryDeletion(projectID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        if let memory {
            memory.discard(projectID: projectID)
            return
        }
        guard let fileRoot else {
            throw IssueHistoryError(code: .writeFailed, message: "Каталог истории не задан")
        }
        var failures: [String] = []
        let pending = IssueHistoryProjectDeletion.pendingProjectDir(fileRoot: fileRoot, projectID: projectID)
        if fileManager.fileExists(atPath: pending.path) {
            do { try fileManager.removeItem(at: pending) }
            catch { failures.append("отложенная история") }
        }
        let json = Self.jsonURL(root: fileRoot, projectID: projectID)
        if fileManager.fileExists(atPath: json.path) {
            do { try fileManager.removeItem(at: json) }
            catch { failures.append("файл истории") }
        }
        let media = Self.projectMediaURL(root: fileRoot, projectID: projectID)
        if fileManager.fileExists(atPath: media.path) {
            do { try fileManager.removeItem(at: media) }
            catch { failures.append("фотографии истории") }
        }
        removeEmptyDirectory(json.deletingLastPathComponent())
        removeEmptyDirectory(media.deletingLastPathComponent())
        removeEmptyDirectory(pending.deletingLastPathComponent())
        if liveHistoryExistsUnlocked(projectID: projectID, root: fileRoot)
            || fileManager.fileExists(atPath: pending.path) {
            throw IssueHistoryError(
                code: .writeFailed,
                message: "Не удалось полностью удалить историю замечаний (\(failures.joined(separator: ", ")))."
            )
        }
    }

    private func liveHistoryExistsUnlocked(projectID: UUID, root: URL) -> Bool {
        let json = Self.jsonURL(root: root, projectID: projectID)
        let media = Self.projectMediaURL(root: root, projectID: projectID)
        return fileManager.fileExists(atPath: json.path) || fileManager.fileExists(atPath: media.path)
    }

    private func moveItemReplacing(at source: URL, to destination: URL) throws {
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: source, to: destination)
        } catch {
            throw IssueHistoryError(code: .writeFailed, message: "Не удалось переместить файлы истории")
        }
    }

    private func removeEmptyDirectory(_ url: URL) {
        if Self.directoryIsEmpty(url, fileManager: fileManager) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Inserts the command's event. The same `eventID` is a no-op and does not write again.
    @discardableResult
    func apply(_ command: IssueHistoryCommand) throws -> IssueHistoryDocument {
        lock.lock()
        defer { lock.unlock() }
        let projectID = command.projectID
        try ensureWritableUnlocked(projectID)
        let current = try loadUnlocked(projectID: projectID)
        if current.caseContaining(eventID: command.eventID) != nil {
            return current
        }

        let drafted = try draft(command, into: current)
        let copied = try readPhotoBytes(drafted.photoURLs)
        try persist(document: drafted.document, eventID: command.eventID, photos: copied)
        return drafted.document
    }

    /// Writes the pending operation and photo copies. Does not close the case and does not touch progress.
    @discardableResult
    func prepare(
        _ operation: IssueHistoryPendingOperation,
        adoptionPhotos: [Data],
        actionPhotos: [Data]
    ) throws -> IssueHistoryDocument {
        lock.lock()
        defer { lock.unlock() }
        try ensureWritableUnlocked(operation.identity.projectID)
        let current = try loadUnlocked(projectID: operation.identity.projectID)
        if let done = current.completed.first(where: { $0.eventID == operation.eventID }) {
            guard done.fingerprint == operation.fingerprint else {
                throw IssueHistoryError(code: .commandMismatch, message: "Тот же идентификатор относится к другой команде")
            }
            return current
        }
        if let existing = current.pendingOperation(eventID: operation.eventID) {
            guard existing.fingerprint == operation.fingerprint else {
                throw IssueHistoryError(code: .commandMismatch, message: "Повтор не совпал с незавершённой командой")
            }
            return current
        }
        if current.pending.contains(where: { $0.identity.itemKey == operation.identity.itemKey }) {
            throw IssueHistoryError(code: .pendingBlocks, message: "У пункта уже есть незавершённая операция")
        }
        var photosByEvent: [(UUID, [Data])] = []
        if let adoptionEventID = operation.adoptionEventID {
            photosByEvent.append((adoptionEventID, adoptionPhotos))
        }
        photosByEvent.append((operation.eventID, actionPhotos))
        var staged: [(eventID: UUID, photos: [(name: String, data: Data)])] = []
        for (eventID, datas) in photosByEvent {
            let named = datas.enumerated().map { (Self.photoFileName(index: $0.offset, source: URL(fileURLWithPath: "photo.jpg")), $0.element) }
            staged.append((eventID, named))
        }
        var stamped = operation
        if let adoptionEventID = stamped.adoptionEventID {
            stamped.adoptionPhotoFileNames = staged.first { $0.eventID == adoptionEventID }?.photos.map(\.name) ?? []
        }
        stamped.actionPhotoFileNames = staged.first { $0.eventID == stamped.eventID }?.photos.map(\.name) ?? []
        var next = current
        next.pending.append(stamped)
        try persistPending(document: next, staged: staged)
        return next
    }

    /// Moves a pending operation into the case log. Does not copy photos again and does not write progress.
    @discardableResult
    func commit(projectID: UUID, eventID: UUID, fingerprint: String) throws -> IssueHistoryDocument {
        lock.lock()
        defer { lock.unlock() }
        try ensureWritableUnlocked(projectID)
        let current = try loadUnlocked(projectID: projectID)
        if let done = current.completed.first(where: { $0.eventID == eventID }) {
            guard done.fingerprint == fingerprint else {
                throw IssueHistoryError(code: .commandMismatch, message: "Завершение относится к другой команде")
            }
            return current
        }
        guard let operation = current.pendingOperation(eventID: eventID) else {
            throw IssueHistoryError(code: .caseNotFound, message: "Нет незавершённой операции для завершения")
        }
        guard operation.fingerprint == fingerprint else {
            throw IssueHistoryError(code: .commandMismatch, message: "Завершение не совпало с командой")
        }
        var next = try applying(operation, to: current)
        next.pending.removeAll { $0.eventID == eventID }
        next.completed.append(IssueHistoryCompletion(eventID: eventID, fingerprint: fingerprint))
        try persist(document: next, eventID: eventID, photos: [])
        return next
    }

    private func applying(_ operation: IssueHistoryPendingOperation, to document: IssueHistoryDocument) throws -> IssueHistoryDocument {
        var next = document
        let action = IssueHistoryEvent(
            id: operation.eventID,
            kind: operation.actionKind,
            at: operation.actionAt,
            packTitle: operation.identity.packTitle,
            stageTitle: operation.identity.stageTitle,
            itemTitle: operation.identity.itemTitle,
            note: operation.actionNote,
            photoFileNames: operation.actionPhotoFileNames
        )
        if let index = next.cases.firstIndex(where: { $0.id == operation.caseID }) {
            guard next.cases[index].isOpen else {
                throw IssueHistoryError(code: .noOpenCase, message: "Случай уже закрыт")
            }
            guard next.cases[index].itemKey == operation.identity.itemKey else {
                throw IssueHistoryError(code: .caseNotFound, message: "Операция относится к другому пункту")
            }
            next.cases[index].events.append(action)
            if operation.actionKind == .closed {
                next.cases[index].closedAt = operation.actionAt
                next.cases[index].closeKind = operation.closeKind
            }
            return next
        }
        guard !next.cases.contains(where: { $0.id == operation.caseID }) else {
            throw IssueHistoryError(code: .caseNotFound, message: "Идентификатор случая занят")
        }
        var events: [IssueHistoryEvent] = []
        if let adoptionEventID = operation.adoptionEventID, let adoptionAt = operation.adoptionAt {
            events.append(IssueHistoryEvent(
                id: adoptionEventID,
                kind: .transferred,
                at: adoptionAt,
                packTitle: operation.identity.packTitle,
                stageTitle: operation.identity.stageTitle,
                itemTitle: operation.identity.itemTitle,
                note: operation.source.note,
                photoFileNames: operation.adoptionPhotoFileNames
            ))
        }
        events.append(action)
        var item = baseCase(id: operation.caseID, identity: operation.identity, events: events)
        item.previousCaseID = latestClosedCaseID(next, key: operation.identity.itemKey)
        if operation.adoptionAt != nil {
            item.openedAt = nil
            item.transferredAt = operation.adoptionAt
        } else if operation.actionKind == .opened {
            item.openedAt = operation.actionAt
        }
        if operation.actionKind == .closed {
            item.closedAt = operation.actionAt
            item.closeKind = operation.closeKind
        }
        next.cases.append(item)
        return next
    }

    private func persistPending(
        document: IssueHistoryDocument,
        staged: [(eventID: UUID, photos: [(name: String, data: Data)])]
    ) throws {
        var written: [UUID] = []
        do {
            for entry in staged where !entry.photos.isEmpty {
                if let memory {
                    var keyed: [IssueHistoryMemorySession.PhotoKey: Data] = [:]
                    for photo in entry.photos {
                        keyed[IssueHistoryMemorySession.PhotoKey(
                            projectID: document.projectID,
                            eventID: entry.eventID,
                            fileName: photo.name
                        )] = photo.data
                    }
                    memory.save(document: document, newPhotos: keyed)
                } else if let fileRoot {
                    _ = try writePhotoCopies(
                        root: fileRoot,
                        projectID: document.projectID,
                        eventID: entry.eventID,
                        photos: entry.photos
                    )
                    written.append(entry.eventID)
                }
            }
            if memory != nil {
                memory?.save(document: document, newPhotos: [:])
                return
            }
            guard let fileRoot else {
                throw IssueHistoryError(code: .writeFailed, message: "Каталог истории не задан")
            }
            try writeJSON(document, root: fileRoot)
        } catch {
            if let fileRoot {
                for eventID in written {
                    removeEventMedia(root: fileRoot, projectID: document.projectID, eventID: eventID)
                }
            }
            throw error
        }
    }

    func photoData(projectID: UUID, eventID: UUID, fileName: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard Self.isSafeFileName(fileName) else {
            throw IssueHistoryError(code: .photoCopyFailed, message: "Недопустимое имя файла истории")
        }
        if let memory {
            guard let data = memory.photo(projectID: projectID, eventID: eventID, fileName: fileName) else {
                throw IssueHistoryError(code: .photoCopyFailed, message: "Копия фото в сессии не найдена")
            }
            return data
        }
        guard let fileRoot else {
            throw IssueHistoryError(code: .photoCopyFailed, message: "Каталог истории не задан")
        }
        let url = Self.photoURL(root: fileRoot, projectID: projectID, eventID: eventID, fileName: fileName)
        do {
            return try Data(contentsOf: url)
        } catch {
            throw IssueHistoryError(code: .photoCopyFailed, message: "Копия фото истории не читается")
        }
    }

    // MARK: - Load

    private func loadUnlocked(projectID: UUID) throws -> IssueHistoryDocument {
        if let memory {
            return memory.document(for: projectID) ?? .empty(projectID: projectID)
        }
        guard let fileRoot else {
            return .empty(projectID: projectID)
        }
        let url = Self.jsonURL(root: fileRoot, projectID: projectID)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .empty(projectID: projectID)
        }
        if isDirectory.boolValue {
            throw IssueHistoryError(code: .corruptFile, message: "Файл истории оказался каталогом")
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw IssueHistoryError(code: .corruptFile, message: "Файл истории не читается")
        }
        let document: IssueHistoryDocument
        do {
            document = try Self.makeDecoder().decode(IssueHistoryDocument.self, from: data)
        } catch {
            throw IssueHistoryError(code: .corruptFile, message: "Файл истории повреждён")
        }
        try validate(document, expectedProjectID: projectID)
        return document
    }

    private func validate(_ document: IssueHistoryDocument, expectedProjectID: UUID) throws {
        guard document.schemaVersion == IssueHistorySchema.current else {
            throw IssueHistoryError(code: .corruptFile, message: "Неизвестная версия файла истории")
        }
        guard document.projectID == expectedProjectID else {
            throw IssueHistoryError(code: .corruptFile, message: "Файл истории принадлежит другому проекту")
        }
        var caseIDs = Set<UUID>()
        var eventIDs = Set<UUID>()
        var openKeys = Set<IssueHistoryItemKey>()
        for item in document.cases {
            guard item.projectID == expectedProjectID else {
                throw IssueHistoryError(code: .corruptFile, message: "Случай записан на другой проект")
            }
            guard caseIDs.insert(item.id).inserted else {
                throw IssueHistoryError(code: .corruptFile, message: "Повторяющийся идентификатор случая")
            }
            guard !item.events.isEmpty else {
                throw IssueHistoryError(code: .corruptFile, message: "У случая нет событий")
            }
            switch (item.closeKind, item.closedAt) {
            case (nil, nil), (.some, .some):
                break
            default:
                throw IssueHistoryError(code: .corruptFile, message: "Состояние закрытия записано неполно")
            }
            if item.isOpen, !openKeys.insert(item.itemKey).inserted {
                throw IssueHistoryError(code: .corruptFile, message: "Два открытых случая одного пункта")
            }
            for event in item.events {
                guard eventIDs.insert(event.id).inserted else {
                    throw IssueHistoryError(code: .corruptFile, message: "Повторяющийся идентификатор события")
                }
                for name in event.photoFileNames where !Self.isSafeFileName(name) {
                    throw IssueHistoryError(code: .corruptFile, message: "Имя фото истории содержит путь")
                }
            }
        }
        var pendingIDs = Set<UUID>()
        var pendingKeys = Set<IssueHistoryItemKey>()
        for operation in document.pending {
            guard operation.identity.projectID == expectedProjectID else {
                throw IssueHistoryError(code: .corruptFile, message: "Незавершённая операция другого проекта")
            }
            guard pendingIDs.insert(operation.eventID).inserted else {
                throw IssueHistoryError(code: .corruptFile, message: "Две незавершённые операции с одним событием")
            }
            guard pendingKeys.insert(operation.identity.itemKey).inserted else {
                throw IssueHistoryError(code: .corruptFile, message: "Две незавершённые операции одного пункта")
            }
            guard !operation.fingerprint.isEmpty else {
                throw IssueHistoryError(code: .corruptFile, message: "У операции нет содержимого команды")
            }
            if eventIDs.contains(operation.eventID) {
                throw IssueHistoryError(code: .corruptFile, message: "Событие уже завершено и всё ещё ожидает")
            }
        }
    }

    // MARK: - Draft

    private nonisolated struct Draft {
        var document: IssueHistoryDocument
        var photoURLs: [URL]
    }

    private func draft(_ command: IssueHistoryCommand, into document: IssueHistoryDocument) throws -> Draft {
        switch command {
        case .open(let command):
            return try draftOpen(command, into: document)
        case .update(let command):
            return try draftUpdate(command, into: document)
        case .close(let command):
            return try draftClose(command, into: document)
        case .transfer(let command):
            return try draftTransfer(command, into: document)
        }
    }

    private func draftOpen(_ command: IssueHistoryOpen, into document: IssueHistoryDocument) throws -> Draft {
        try ensureNoOpenCase(document, key: command.identity.itemKey)
        guard !document.cases.contains(where: { $0.id == command.caseID }) else {
            throw IssueHistoryError(code: .openCaseAlreadyExists, message: "Идентификатор случая уже занят")
        }
        let event = makeEvent(
            id: command.eventID,
            kind: .opened,
            at: command.at,
            identity: command.identity,
            note: command.note,
            photoURLs: command.photoURLs
        )
        var item = baseCase(id: command.caseID, identity: command.identity, events: [event])
        item.openedAt = command.at
        item.previousCaseID = latestClosedCaseID(document, key: command.identity.itemKey)
        var next = document
        next.cases.append(item)
        return Draft(document: next, photoURLs: command.photoURLs)
    }

    private func draftUpdate(_ command: IssueHistoryUpdate, into document: IssueHistoryDocument) throws -> Draft {
        guard let index = document.cases.firstIndex(where: { $0.id == command.caseID }) else {
            throw IssueHistoryError(code: .caseNotFound, message: "Случай для правки не найден")
        }
        guard document.cases[index].isOpen else {
            throw IssueHistoryError(code: .noOpenCase, message: "Закрытый случай не правится")
        }
        guard document.cases[index].itemKey == command.identity.itemKey else {
            throw IssueHistoryError(code: .caseNotFound, message: "Правка относится к другому пункту")
        }
        let event = makeEvent(
            id: command.eventID,
            kind: .updated,
            at: command.at,
            identity: command.identity,
            note: command.note,
            photoURLs: command.photoURLs
        )
        var next = document
        next.cases[index].events.append(event)
        return Draft(document: next, photoURLs: command.photoURLs)
    }

    private func draftClose(_ command: IssueHistoryClose, into document: IssueHistoryDocument) throws -> Draft {
        let event = makeEvent(
            id: command.eventID,
            kind: .closed,
            at: command.at,
            identity: command.identity,
            note: command.note,
            photoURLs: command.photoURLs
        )
        var next = document
        if let index = next.cases.firstIndex(where: { $0.id == command.caseID }) {
            guard next.cases[index].isOpen else {
                throw IssueHistoryError(code: .noOpenCase, message: "Случай уже закрыт")
            }
            guard next.cases[index].itemKey == command.identity.itemKey else {
                throw IssueHistoryError(code: .caseNotFound, message: "Закрытие относится к другому пункту")
            }
            next.cases[index].events.append(event)
            next.cases[index].closedAt = command.at
            next.cases[index].closeKind = command.kind
            return Draft(document: next, photoURLs: command.photoURLs)
        }

        let sameItem = next.cases.filter { $0.itemKey == command.identity.itemKey }
        if sameItem.contains(where: \.isOpen) {
            throw IssueHistoryError(code: .caseNotFound, message: "Открытый случай пункта имеет другой идентификатор")
        }
        guard sameItem.isEmpty else {
            throw IssueHistoryError(code: .noOpenCase, message: "Нет открытого случая для закрытия")
        }
        guard !next.cases.contains(where: { $0.id == command.caseID }) else {
            throw IssueHistoryError(code: .caseNotFound, message: "Идентификатор случая занят")
        }
        var item = baseCase(id: command.caseID, identity: command.identity, events: [event])
        item.openedAt = nil
        item.transferredAt = nil
        item.closedAt = command.at
        item.closeKind = command.kind
        next.cases.append(item)
        return Draft(document: next, photoURLs: command.photoURLs)
    }

    private func draftTransfer(_ command: IssueHistoryTransfer, into document: IssueHistoryDocument) throws -> Draft {
        try ensureNoOpenCase(document, key: command.identity.itemKey)
        guard !document.cases.contains(where: { $0.id == command.caseID }) else {
            throw IssueHistoryError(code: .openCaseAlreadyExists, message: "Идентификатор случая уже занят")
        }
        let event = makeEvent(
            id: command.eventID,
            kind: .transferred,
            at: command.at,
            identity: command.identity,
            note: command.note,
            photoURLs: command.photoURLs
        )
        var item = baseCase(id: command.caseID, identity: command.identity, events: [event])
        item.openedAt = nil
        item.transferredAt = command.at
        item.previousCaseID = latestClosedCaseID(document, key: command.identity.itemKey)
        var next = document
        next.cases.append(item)
        return Draft(document: next, photoURLs: command.photoURLs)
    }

    private func ensureNoOpenCase(_ document: IssueHistoryDocument, key: IssueHistoryItemKey) throws {
        if document.cases.contains(where: { $0.itemKey == key && $0.isOpen }) {
            throw IssueHistoryError(code: .openCaseAlreadyExists, message: "У пункта уже есть открытый случай")
        }
    }

    private func latestClosedCaseID(_ document: IssueHistoryDocument, key: IssueHistoryItemKey) -> UUID? {
        let closed = document.cases.enumerated().filter { $0.element.itemKey == key && !$0.element.isOpen }
        return closed.max { lhs, rhs in
            let left = lhs.element.closedAt ?? .distantPast
            let right = rhs.element.closedAt ?? .distantPast
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }?.element.id
    }

    private func baseCase(
        id: UUID,
        identity: IssueHistoryIdentity,
        events: [IssueHistoryEvent]
    ) -> IssueHistoryCase {
        IssueHistoryCase(
            id: id,
            projectID: identity.projectID,
            pack: identity.pack,
            stageID: identity.stageID,
            itemID: identity.itemID,
            previousCaseID: nil,
            openedAt: nil,
            transferredAt: nil,
            closedAt: nil,
            closeKind: nil,
            events: events
        )
    }

    private func makeEvent(
        id: UUID,
        kind: IssueHistoryEventKind,
        at: Date,
        identity: IssueHistoryIdentity,
        note: String?,
        photoURLs: [URL]
    ) -> IssueHistoryEvent {
        IssueHistoryEvent(
            id: id,
            kind: kind,
            at: at,
            packTitle: identity.packTitle,
            stageTitle: identity.stageTitle,
            itemTitle: identity.itemTitle,
            note: note?.isEmpty == true ? nil : note,
            photoFileNames: photoURLs.enumerated().map { Self.photoFileName(index: $0.offset, source: $0.element) }
        )
    }

    // MARK: - Persist

    private func readPhotoBytes(_ urls: [URL]) throws -> [(name: String, data: Data)] {
        var copies: [(name: String, data: Data)] = []
        copies.reserveCapacity(urls.count)
        for (index, url) in urls.enumerated() {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw IssueHistoryError(code: .photoCopyFailed, message: "Не удалось прочитать исходное фото")
            }
            copies.append((Self.photoFileName(index: index, source: url), data))
        }
        return copies
    }

    private func persist(
        document: IssueHistoryDocument,
        eventID: UUID,
        photos: [(name: String, data: Data)]
    ) throws {
        if let memory {
            var keyed: [IssueHistoryMemorySession.PhotoKey: Data] = [:]
            for photo in photos {
                let key = IssueHistoryMemorySession.PhotoKey(
                    projectID: document.projectID,
                    eventID: eventID,
                    fileName: photo.name
                )
                keyed[key] = photo.data
            }
            memory.save(document: document, newPhotos: keyed)
            return
        }
        guard let fileRoot else {
            throw IssueHistoryError(code: .writeFailed, message: "Каталог истории не задан")
        }
        let writtenNames = try writePhotoCopies(
            root: fileRoot,
            projectID: document.projectID,
            eventID: eventID,
            photos: photos
        )
        do {
            try writeJSON(document, root: fileRoot)
        } catch {
            removeEventMedia(root: fileRoot, projectID: document.projectID, eventID: eventID)
            _ = writtenNames
            throw error
        }
    }

    private func writePhotoCopies(
        root: URL,
        projectID: UUID,
        eventID: UUID,
        photos: [(name: String, data: Data)]
    ) throws -> [String] {
        guard !photos.isEmpty else { return [] }
        let eventDir = Self.eventMediaURL(root: root, projectID: projectID, eventID: eventID)
        if fileManager.fileExists(atPath: eventDir.path) {
            try? fileManager.removeItem(at: eventDir)
        }
        do {
            try fileManager.createDirectory(at: eventDir, withIntermediateDirectories: true)
            var names: [String] = []
            for photo in photos {
                guard Self.isSafeFileName(photo.name) else {
                    throw IssueHistoryError(code: .photoCopyFailed, message: "Недопустимое имя копии")
                }
                let url = eventDir.appendingPathComponent(photo.name)
                try photo.data.write(to: url, options: .atomic)
                let written = try Data(contentsOf: url)
                guard written == photo.data else {
                    throw IssueHistoryError(code: .photoCopyFailed, message: "Копия фото не совпала с исходником")
                }
                names.append(photo.name)
            }
            return names
        } catch {
            removeEventMedia(root: root, projectID: projectID, eventID: eventID)
            if let historyError = error as? IssueHistoryError {
                throw historyError
            }
            throw IssueHistoryError(code: .photoCopyFailed, message: "Не удалось записать копию фото")
        }
    }

    private func writeJSON(_ document: IssueHistoryDocument, root: URL) throws {
        let url = Self.jsonURL(root: root, projectID: document.projectID)
        let directory = url.deletingLastPathComponent()
        let directoryExisted = fileManager.fileExists(atPath: directory.path)
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try Self.makeEncoder().encode(document)
            try data.write(to: url, options: .atomic)
        } catch {
            if !directoryExisted {
                try? fileManager.removeItem(at: directory)
            }
            if let historyError = error as? IssueHistoryError {
                throw historyError
            }
            throw IssueHistoryError(code: .writeFailed, message: "Не удалось записать файл истории")
        }
    }

    private func removeEventMedia(root: URL, projectID: UUID, eventID: UUID) {
        let eventDir = Self.eventMediaURL(root: root, projectID: projectID, eventID: eventID)
        try? fileManager.removeItem(at: eventDir)
        let projectDir = eventDir.deletingLastPathComponent()
        if Self.directoryIsEmpty(projectDir, fileManager: fileManager) {
            try? fileManager.removeItem(at: projectDir)
        }
        let mediaRoot = projectDir.deletingLastPathComponent()
        if Self.directoryIsEmpty(mediaRoot, fileManager: fileManager) {
            try? fileManager.removeItem(at: mediaRoot)
        }
    }

    // MARK: - Paths

    static func jsonURL(root: URL, projectID: UUID) -> URL {
        root
            .appendingPathComponent(historyFolderName, isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
    }

    static func projectMediaURL(root: URL, projectID: UUID) -> URL {
        root
            .appendingPathComponent(mediaFolderName, isDirectory: true)
            .appendingPathComponent(projectID.uuidString, isDirectory: true)
    }

    static func eventMediaURL(root: URL, projectID: UUID, eventID: UUID) -> URL {
        projectMediaURL(root: root, projectID: projectID)
            .appendingPathComponent(eventID.uuidString, isDirectory: true)
    }

    private func ensureWritableUnlocked(_ projectID: UUID) throws {
        if IssueDeletedProjectGate.isBlocked(projectID) {
            throw IssueHistoryError(
                code: .projectDeleted,
                message: "Проект удалён. История замечаний больше не записывается."
            )
        }
    }

    static func photoURL(root: URL, projectID: UUID, eventID: UUID, fileName: String) -> URL {
        eventMediaURL(root: root, projectID: projectID, eventID: eventID)
            .appendingPathComponent(fileName)
    }

    static func photoFileName(index: Int, source: URL) -> String {
        let ext = source.pathExtension.lowercased()
        let safe: String
        switch ext {
        case "jpeg", "jpg":
            safe = "jpg"
        case "png", "heic", "heif", "webp":
            safe = ext
        default:
            safe = "jpg"
        }
        return String(format: "%02d.%@", index + 1, safe)
    }

    static func isSafeFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return !name.contains("/") && !name.contains("\\")
    }

    private static func directoryIsEmpty(_ url: URL, fileManager: FileManager) -> Bool {
        guard let names = try? fileManager.contentsOfDirectory(atPath: url.path) else { return false }
        return names.isEmpty
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(iso8601.string(from: date))
        }
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = iso8601.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Не удалось прочитать дату истории"
                )
            }
            return date
        }
        return decoder
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
