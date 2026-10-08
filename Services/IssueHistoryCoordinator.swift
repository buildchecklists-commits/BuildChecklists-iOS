import CryptoKit
import Foundation

nonisolated enum IssueHistoryUserKind: Equatable, Sendable {
    case create
    case update
    case resolve
    case withdraw
}

nonisolated struct IssueHistoryChange: Equatable, Sendable {
    var eventID: UUID
    var caseID: UUID
    var adoptionEventID: UUID
    var kind: IssueHistoryUserKind
    var note: String?
    var keptPhotoPaths: [String]
    var newPhotoJPEG: [Data]
}

nonisolated struct IssueChecklistIO {
    var loadStages: (ChecklistPack, UUID) -> [Stage]
    var saveStages: (ChecklistPack, UUID, [Stage]) throws -> Void
    var readNote: (UUID) -> String?
    var writeNote: (UUID, String?) throws -> Void
    var readPhoto: (String) throws -> Data
    var writePhoto: (_ fileName: String, _ data: Data) throws -> String
    var deletePhoto: (String) throws -> Void

    static func live() -> IssueChecklistIO {
        IssueChecklistIO(
            loadStages: { pack, projectID in
                ChecklistPackStore.load(pack: pack, projectID: projectID)
            },
            saveStages: { pack, projectID, stages in
                try ChecklistPackStore.saveConfirmed(pack: pack, projectID: projectID, stages: stages)
            },
            readNote: { itemID in
                ChecklistWorkingNote.readRawText(itemID: itemID)
            },
            writeNote: { itemID, text in
                if let text, !text.isEmpty {
                    try ChecklistWorkingNote.write(text, itemID: itemID)
                } else {
                    try ChecklistWorkingNote.deleteIfExists(itemID: itemID)
                }
            },
            readPhoto: { path in
                try IssuePhotoLocation.read(
                    storedPath: path,
                    documentsDirectory: IssueHistoryRuntime.documentsDirectory()
                )
            },
            writePhoto: { fileName, data in
                try IssueHistoryMediaWriter.write(fileName: fileName, data: data)
            },
            deletePhoto: { path in
                try IssuePhotoLocation.deleteOwnedOriginal(
                    storedPath: path,
                    documentsDirectory: IssueHistoryRuntime.documentsDirectory()
                )
            }
        )
    }
}

/// Resolves a photo stored as an absolute path after the app container root changes.
/// The stable address is the path tail after `Documents`. A same-named file in tmp or caches is not a substitute.
nonisolated enum IssuePhotoLocation {
    static func read(storedPath: String, documentsDirectory: URL?, fileManager: FileManager = .default) throws -> Data {
        if let exact = regularFile(atPath: storedPath, fileManager: fileManager) {
            return try Data(contentsOf: exact)
        }
        if let documentsDirectory,
           let moved = ownedFile(storedPath: storedPath, documentsDirectory: documentsDirectory, fileManager: fileManager) {
            return try Data(contentsOf: moved)
        }
        throw IssueHistoryError(code: .photoCopyFailed, message: "Исходное фото не найдено")
    }

    /// Deletes the file only when it is the one original inside the current Documents tree.
    /// A stored path that still exists outside Documents is left alone, as is any same-named file in tmp or caches.
    static func deleteOwnedOriginal(storedPath: String, documentsDirectory: URL?, fileManager: FileManager = .default) throws {
        guard let documentsDirectory,
              let original = ownedOriginal(storedPath: storedPath, documentsDirectory: documentsDirectory, fileManager: fileManager) else {
            return
        }
        try fileManager.removeItem(at: original)
    }

    /// The unique file inside `documentsDirectory` that this stored path still names.
    /// Nil when the original is missing, still lives outside Documents, or two different files both qualify.
    static func ownedOriginal(storedPath: String, documentsDirectory: URL, fileManager: FileManager = .default) -> URL? {
        let exact = regularFile(atPath: storedPath, fileManager: fileManager)
        let exactInside = exact.flatMap { containedFile($0, documentsDirectory: documentsDirectory, fileManager: fileManager) }
        let mapped = ownedFile(storedPath: storedPath, documentsDirectory: documentsDirectory, fileManager: fileManager)
        if exact != nil {
            guard let exactInside else { return nil }
            if let mapped, canonical(mapped).path != canonical(exactInside).path {
                return nil
            }
            return exactInside
        }
        return mapped
    }

    /// Tail after the `Documents` component, or a path that is already relative to Documents.
    /// `..` is rejected. The file name alone is not a search key.
    static func documentsRelativePath(_ storedPath: String) -> String? {
        guard !storedPath.isEmpty, !storedPath.contains("\0") else { return nil }
        let parts: ArraySlice<String>
        if storedPath.hasPrefix("/") {
            let components = URL(fileURLWithPath: storedPath).pathComponents
            guard let documentsIndex = components.lastIndex(of: "Documents"),
                  documentsIndex + 1 < components.count else {
                return nil
            }
            parts = components[(documentsIndex + 1)...]
        } else {
            var relative = storedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            if relative.first == "Documents" {
                relative.removeFirst()
            }
            parts = ArraySlice(relative)
        }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != ".." && $0 != "." && !$0.isEmpty }) else { return nil }
        return parts.joined(separator: "/")
    }

    private static func ownedFile(storedPath: String, documentsDirectory: URL, fileManager: FileManager) -> URL? {
        guard let relative = documentsRelativePath(storedPath) else { return nil }
        let candidate = relative.split(separator: "/").reduce(documentsDirectory) { url, part in
            url.appendingPathComponent(String(part))
        }
        return containedFile(candidate, documentsDirectory: documentsDirectory, fileManager: fileManager)
    }

    private static func regularFile(atPath path: String, fileManager: FileManager) -> URL? {
        let url = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private static func containedFile(_ url: URL, documentsDirectory: URL, fileManager: FileManager) -> URL? {
        let file = canonical(url)
        let root = canonical(documentsDirectory)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard file.path.hasPrefix(rootPrefix) else { return nil }
        return file
    }

    private static func canonical(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }
}

nonisolated enum IssueHistoryMediaWriter {
    static var imagesDirectory: () -> URL? = {
        guard let root = IssueHistoryRuntime.documentsDirectory() else { return nil }
        return root.appendingPathComponent("BC_Media/Images", isDirectory: true)
    }

    static func write(fileName: String, data: Data) throws -> String {
        guard IssueHistoryStore.isSafeFileName(fileName), let directory = imagesDirectory() else {
            throw IssueHistoryError(code: .photoCopyFailed, message: "Не удалось записать фотографию замечания")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            guard existing == data else {
                throw IssueHistoryError(code: .photoCopyFailed, message: "Файл фотографии уже занят другими данными")
            }
            return url.path
        }
        try data.write(to: url, options: .atomic)
        let written = try Data(contentsOf: url)
        guard written == data else {
            throw IssueHistoryError(code: .notConfirmed, message: "Фотография не подтвердилась после записи")
        }
        return url.path
    }
}

nonisolated enum IssueHistoryRecovery: Equatable, Sendable {
    case committed
    case stillPending
    case conflict
}

nonisolated struct IssueHistoryCoordinator {
    var history: IssueHistoryStore
    var io: IssueChecklistIO
    var now: () -> Date
    var beforeCommit: () throws -> Void

    init(
        history: IssueHistoryStore,
        io: IssueChecklistIO,
        now: @escaping () -> Date = Date.init,
        beforeCommit: @escaping () throws -> Void = {}
    ) {
        self.history = history
        self.io = io
        self.now = now
        self.beforeCommit = beforeCommit
    }

    static func live() -> IssueHistoryCoordinator {
        IssueHistoryCoordinator(history: IssueHistoryRuntime.store(), io: .live())
    }

    @discardableResult
    func perform(
        identity: IssueHistoryIdentity,
        screenStages: [Stage],
        change: IssueHistoryChange
    ) throws -> IssueHistorySnapshot {
        if IssueDeletedProjectGate.isBlocked(identity.projectID) {
            throw IssueHistoryError(
                code: .projectDeleted,
                message: "Проект удалён. История замечаний больше не записывается."
            )
        }
        let before = try loadOrCorrupt(identity.projectID)
        let pendingBefore = before.pending.first { $0.identity.itemKey == identity.itemKey }
        let recovery = try recover(projectID: identity.projectID, pack: identity.pack)
        if recovery[identity.itemID] == .conflict {
            throw IssueHistoryError(
                code: .conflict,
                message: "Сохранённые данные не совпали с незавершённой операцией и не перезаписаны"
            )
        }
        var change = change
        if recovery[identity.itemID] == .committed, let pendingBefore {
            if try sameCommand(change, pendingBefore) {
                for path in pendingBefore.source.photoPaths where !pendingBefore.target.photoPaths.contains(path) {
                    try? io.deletePhoto(path)
                }
                return pendingBefore.target
            }
        }
        var document = try loadOrCorrupt(identity.projectID)
        let live = try observedSource(identity: identity, screenStages: screenStages)
        let openCase = document.cases.first { $0.itemKey == identity.itemKey && $0.isOpen }
        let blocking = document.pending.first { $0.identity.itemKey == identity.itemKey }
        if let blocking, resumesPreparedPhotos(change, blocking) {
            guard preparedTargetPhotosReady(blocking) else {
                throw IssueHistoryError(
                    code: .pendingBlocks,
                    message: "Предыдущая запись этого пункта не завершена. Повторите то же действие, не меняя описание и фото."
                )
            }
            return try finishPrepared(blocking, identity: identity, screenStages: screenStages)
        }
        if let blocking {
            let probe = try plan(change: change, identity: identity, source: blocking.source, openCase: openCase)
            guard blocking.fingerprint == probe.fingerprint else {
                throw IssueHistoryError(
                    code: .pendingBlocks,
                    message: "Предыдущая запись этого пункта не завершена. Повторите то же действие, не меняя описание и фото."
                )
            }
            change.eventID = blocking.eventID
            change.caseID = blocking.caseID
            if let adoptionEventID = blocking.adoptionEventID {
                change.adoptionEventID = adoptionEventID
            }
            document = try loadOrCorrupt(identity.projectID)
        }
        let recordedSource = blocking?.source ?? live
        let planned = try plan(change: change, identity: identity, source: recordedSource, openCase: openCase)
        if blocking == nil,
           openCase != nil,
           matches(live, planned.target) {
            return planned.target
        }
        let operation = try preparedOperation(planned: planned, existing: document)
        _ = try history.prepare(operation, adoptionPhotos: planned.adoptionPhotos, actionPhotos: planned.actionPhotos)

        let created = try writeContentIfNeeded(planned: planned, source: recordedSource, screenStages: screenStages)
        do {
            try writeProgress(identity: identity, screenStages: screenStages, target: planned.target)
        } catch {
            try? undoContent(created: created, source: recordedSource, identity: identity)
            throw error
        }
        let saved = try observedSource(identity: identity, screenStages: [])
        guard matches(saved, planned.target) else {
            try? undoContent(created: created, source: recordedSource, identity: identity)
            throw IssueHistoryError(code: .notConfirmed, message: "Сохранение замечания не подтвердилось")
        }
        try beforeCommit()
        _ = try history.commit(projectID: identity.projectID, eventID: operation.eventID, fingerprint: operation.fingerprint)
        IssueProgressEpoch.bump()
        for path in recordedSource.photoPaths where !planned.target.photoPaths.contains(path) {
            try? io.deletePhoto(path)
        }
        return planned.target
    }

    /// The editor reopened after a partial photo write shows the new note and the old photos.
    /// Saving that screen finishes the prepared operation and its target files.
    /// It does not adopt the old photo set as a new command.
    private func resumesPreparedPhotos(
        _ change: IssueHistoryChange,
        _ operation: IssueHistoryPendingOperation
    ) -> Bool {
        guard change.newPhotoJPEG.isEmpty else { return false }
        guard operation.actionKind == .opened || operation.actionKind == .updated else { return false }
        guard operation.target.photoPaths != operation.source.photoPaths else { return false }
        guard normalized(change.note) == operation.target.note else { return false }
        return change.keptPhotoPaths == operation.source.photoPaths
    }

    private func preparedTargetPhotosReady(_ operation: IssueHistoryPendingOperation) -> Bool {
        guard operation.target.photoPaths.count == operation.target.photoHashes.count else { return false }
        for (path, hash) in zip(operation.target.photoPaths, operation.target.photoHashes) {
            guard let data = try? io.readPhoto(path), Self.hash(data) == hash else { return false }
        }
        return true
    }

    private func finishPrepared(
        _ operation: IssueHistoryPendingOperation,
        identity: IssueHistoryIdentity,
        screenStages: [Stage]
    ) throws -> IssueHistorySnapshot {
        try writeProgress(identity: identity, screenStages: screenStages, target: operation.target)
        let saved = try observedSource(identity: identity, screenStages: [])
        guard matches(saved, operation.target) else {
            throw IssueHistoryError(code: .notConfirmed, message: "Сохранение замечания не подтвердилось")
        }
        try beforeCommit()
        _ = try history.commit(
            projectID: identity.projectID,
            eventID: operation.eventID,
            fingerprint: operation.fingerprint
        )
        IssueProgressEpoch.bump()
        for path in operation.source.photoPaths where !operation.target.photoPaths.contains(path) {
            try? io.deletePhoto(path)
        }
        return operation.target
    }

    /// Separate procedure. Does not run while a list or PDF is read, and does not rewrite conflicting progress.
    func recover(projectID: UUID, pack: ChecklistPack) throws -> [UUID: IssueHistoryRecovery] {
        let document = try loadOrCorrupt(projectID)
        var results: [UUID: IssueHistoryRecovery] = [:]
        for operation in document.pending where operation.identity.pack == pack {
            let saved = try observedSource(identity: operation.identity, screenStages: [])
            switch alignment(saved: saved, operation: operation) {
            case .target:
                _ = try history.commit(
                    projectID: projectID,
                    eventID: operation.eventID,
                    fingerprint: operation.fingerprint
                )
                IssueProgressEpoch.bump()
                results[operation.identity.itemID] = .committed
            case .source, .noteAlreadyApplied:
                results[operation.identity.itemID] = .stillPending
            case .conflict:
                results[operation.identity.itemID] = .conflict
            }
        }
        return results
    }

    // MARK: - Planning

    private struct Plan {
        var operation: IssueHistoryPendingOperation
        var fingerprint: String { operation.fingerprint }
        var target: IssueHistorySnapshot { operation.target }
        var adoptionPhotos: [Data]
        var actionPhotos: [Data]
        var newFiles: [(fileName: String, data: Data)]
    }

    private func plan(
        change: IssueHistoryChange,
        identity: IssueHistoryIdentity,
        source: IssueHistorySnapshot,
        openCase: IssueHistoryCase?
    ) throws -> Plan {
        let kind = try resolvedKind(change.kind, openCase: openCase, source: source)
        let adopting = openCase == nil && kind.action != .opened
        let eventID = change.eventID
        let note = kind.action == .closed ? source.note : normalized(change.note)
        let keptPaths = kind.action == .closed ? source.photoPaths : change.keptPhotoPaths
        let newJPEG = kind.action == .closed ? [] : change.newPhotoJPEG
        var keptDatas: [Data] = []
        for path in keptPaths {
            keptDatas.append(try io.readPhoto(path))
        }
        let newNames = try plannedFileNames(eventID: eventID, count: newJPEG.count)
        let targetPaths = keptPaths + newNames.map(\.path)
        let keptHashes = keptDatas.map(Self.hash)
        let newHashes = newJPEG.map(Self.hash)
        let targetHashes = kind.action == .closed ? source.photoHashes : keptHashes + newHashes
        let target = IssueHistorySnapshot(
            status: kind.status,
            note: note,
            photoPaths: targetPaths,
            photoHashes: targetHashes
        )
        let fingerprint = Self.fingerprint(
            action: kind.action,
            closeKind: kind.close,
            source: source,
            targetNote: note,
            targetStatus: kind.status,
            keptHashes: keptHashes,
            newHashes: newHashes
        )
        var sourceDatas: [Data] = []
        for path in source.photoPaths {
            sourceDatas.append(try io.readPhoto(path))
        }
        let actionDatas = kind.action == .closed ? sourceDatas : keptDatas + newJPEG
        let actionAt = now()
        let adoptionAt = adopting ? now() : nil
        let operation = IssueHistoryPendingOperation(
            eventID: eventID,
            adoptionEventID: adopting ? change.adoptionEventID : nil,
            caseID: openCase?.id ?? change.caseID,
            fingerprint: fingerprint,
            identity: identity,
            actionKind: kind.action,
            closeKind: kind.close,
            actionAt: actionAt,
            adoptionAt: adoptionAt,
            source: source,
            target: target,
            actionNote: note,
            adoptionPhotoFileNames: [],
            actionPhotoFileNames: []
        )
        return Plan(
            operation: operation,
            adoptionPhotos: adopting ? sourceDatas : [],
            actionPhotos: actionDatas,
            newFiles: Array(zip(newNames.map(\.name), newJPEG))
        )
    }

    private func plannedFileNames(eventID: UUID, count: Int) throws -> [(name: String, path: String)] {
        guard count > 0 else { return [] }
        guard let directory = IssueHistoryMediaWriter.imagesDirectory() else {
            throw IssueHistoryError(code: .photoCopyFailed, message: "Нет каталога для фотографий замечания")
        }
        return (0..<count).map { index in
            let name = "\(eventID.uuidString)-\(index).jpg"
            return (name, directory.appendingPathComponent(name).path)
        }
    }

    private func resolvedKind(
        _ kind: IssueHistoryUserKind,
        openCase: IssueHistoryCase?,
        source: IssueHistorySnapshot
    ) throws -> (action: IssueHistoryEventKind, close: IssueHistoryCloseKind?, status: ItemStatus) {
        switch kind {
        case .create:
            if openCase != nil {
                return (.updated, nil, .issue)
            }
            return (.opened, nil, .issue)
        case .update:
            guard source.status == .issue else {
                throw IssueHistoryError(code: .notConfirmed, message: "Пункт не является замечанием")
            }
            return (.updated, nil, .issue)
        case .resolve:
            guard source.status == .issue else {
                throw IssueHistoryError(code: .notConfirmed, message: "Пункт не является замечанием")
            }
            return (.closed, .resolved, .ok)
        case .withdraw:
            guard source.status == .issue else {
                throw IssueHistoryError(code: .notConfirmed, message: "Пункт не является замечанием")
            }
            return (.closed, .withdrawn, .na)
        }
    }

    private func preparedOperation(planned: Plan, existing: IssueHistoryDocument) throws -> IssueHistoryPendingOperation {
        if let pending = existing.pending.first(where: { $0.identity.itemKey == planned.operation.identity.itemKey }) {
            guard pending.fingerprint == planned.fingerprint else {
                throw IssueHistoryError(code: .pendingBlocks, message: "Незавершённая операция не совпала с новым действием")
            }
            return pending
        }
        if let done = existing.completed.first(where: { $0.eventID == planned.operation.eventID }) {
            guard done.fingerprint == planned.fingerprint else {
                throw IssueHistoryError(code: .commandMismatch, message: "Идентификатор события уже использован другой командой")
            }
        }
        return planned.operation
    }

    // MARK: - Saved state

    private func observedSource(identity: IssueHistoryIdentity, screenStages: [Stage]) throws -> IssueHistorySnapshot {
        let disk = io.loadStages(identity.pack, identity.projectID)
        let stages = contains(identity, in: disk) ? disk : screenStages
        guard let item = find(identity, in: stages) else {
            throw IssueHistoryError(code: .notConfirmed, message: "Пункт не найден в сохранённом прогрессе")
        }
        var hashes: [String] = []
        for path in item.photoPaths {
            let data = try io.readPhoto(path)
            hashes.append(Self.hash(data))
        }
        let note = normalized(io.readNote(identity.itemID))
        return IssueHistorySnapshot(
            status: item.status ?? .na,
            note: note,
            photoPaths: item.photoPaths,
            photoHashes: hashes
        )
    }

    private func writeContentIfNeeded(
        planned: Plan,
        source: IssueHistorySnapshot,
        screenStages: [Stage]
    ) throws -> [String] {
        let saved = try observedSource(identity: planned.operation.identity, screenStages: screenStages)
        let state = alignment(saved: saved, operation: planned.operation)
        switch state {
        case .target:
            return []
        case .conflict:
            throw IssueHistoryError(code: .conflict, message: "Сохранённые данные пункта изменились и не перезаписаны")
        case .source, .noteAlreadyApplied:
            break
        }
        var created: [String] = []
        do {
            for file in planned.newFiles {
                let path = try io.writePhoto(file.fileName, file.data)
                created.append(path)
            }
            if state == .source, planned.target.note != source.note {
                try io.writeNote(planned.operation.identity.itemID, planned.target.note)
            }
        } catch {
            try? undoContent(created: created, source: source, identity: planned.operation.identity)
            throw error
        }
        return created
    }

    private func writeProgress(
        identity: IssueHistoryIdentity,
        screenStages: [Stage],
        target: IssueHistorySnapshot
    ) throws {
        var stages = io.loadStages(identity.pack, identity.projectID)
        if !contains(identity, in: stages),
           let screenStage = screenStages.first(where: { $0.id == identity.stageID }) {
            stages.append(screenStage)
        }
        guard let located = locate(identity, in: &stages) else {
            throw IssueHistoryError(code: .notConfirmed, message: "Пункт не найден для записи прогресса")
        }
        stages[located.stage].items[located.item].status = target.status
        stages[located.stage].items[located.item].photoPaths = target.photoPaths
        try io.saveStages(identity.pack, identity.projectID, stages)
    }

    private func undoContent(created: [String], source: IssueHistorySnapshot, identity: IssueHistoryIdentity) throws {
        try io.writeNote(identity.itemID, source.note)
        for path in created {
            try io.deletePhoto(path)
        }
    }

    private func loadOrCorrupt(_ projectID: UUID) throws -> IssueHistoryDocument {
        do {
            return try history.load(projectID: projectID)
        } catch let error as IssueHistoryError where error.code == .corruptFile {
            throw error
        } catch {
            throw IssueHistoryError(code: .corruptFile, message: "История замечаний повреждена и не перезаписана")
        }
    }

    private enum SavedAlignment {
        case target
        case source
        case noteAlreadyApplied
        case conflict
    }

    /// Status equality is not enough: the note and photo bytes have to match too.
    /// A note that already matches the target while the live photos are still the source is the same operation, interrupted after the note write.
    private func alignment(saved: IssueHistorySnapshot, operation: IssueHistoryPendingOperation) -> SavedAlignment {
        if matches(saved, operation.target) { return .target }
        if matches(saved, operation.source) { return .source }
        if saved.status == operation.source.status,
           saved.photoHashes == operation.source.photoHashes,
           saved.note == operation.target.note,
           saved.note != operation.source.note {
            return .noteAlreadyApplied
        }
        return .conflict
    }

    private func sameCommand(_ change: IssueHistoryChange, _ operation: IssueHistoryPendingOperation) throws -> Bool {
        let openCase = operation.actionKind == .opened ? nil : IssueHistoryCase(
            id: operation.caseID,
            projectID: operation.identity.projectID,
            pack: operation.identity.pack,
            stageID: operation.identity.stageID,
            itemID: operation.identity.itemID,
            previousCaseID: nil,
            openedAt: nil,
            transferredAt: nil,
            closedAt: nil,
            closeKind: nil,
            events: [IssueHistoryEvent(
                id: operation.eventID,
                kind: operation.actionKind,
                at: operation.actionAt,
                packTitle: operation.identity.packTitle,
                stageTitle: operation.identity.stageTitle,
                itemTitle: operation.identity.itemTitle,
                note: nil,
                photoFileNames: []
            )]
        )
        let probe = try plan(change: change, identity: operation.identity, source: operation.source, openCase: openCase)
        return probe.fingerprint == operation.fingerprint
    }

    private func matches(_ saved: IssueHistorySnapshot, _ expected: IssueHistorySnapshot) -> Bool {
        saved.status == expected.status
            && saved.note == expected.note
            && saved.photoHashes == expected.photoHashes
    }

    private func contains(_ identity: IssueHistoryIdentity, in stages: [Stage]) -> Bool {
        find(identity, in: stages) != nil
    }

    private func find(_ identity: IssueHistoryIdentity, in stages: [Stage]) -> StageItem? {
        guard let stage = stages.first(where: { $0.id == identity.stageID }) else { return nil }
        return stage.items.first { $0.id == identity.itemID }
    }

    private func locate(
        _ identity: IssueHistoryIdentity,
        in stages: inout [Stage]
    ) -> (stage: Int, item: Int)? {
        guard let stageIndex = stages.firstIndex(where: { $0.id == identity.stageID }),
              let itemIndex = stages[stageIndex].items.firstIndex(where: { $0.id == identity.itemID }) else {
            return nil
        }
        return (stageIndex, itemIndex)
    }

    private func normalized(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func fingerprint(
        action: IssueHistoryEventKind,
        closeKind: IssueHistoryCloseKind?,
        source: IssueHistorySnapshot,
        targetNote: String?,
        targetStatus: ItemStatus,
        keptHashes: [String],
        newHashes: [String]
    ) -> String {
        [
            action.rawValue,
            closeKind?.rawValue ?? "-",
            source.status.rawValue,
            source.note ?? "-",
            source.photoHashes.joined(separator: ","),
            targetStatus.rawValue,
            targetNote ?? "-",
            keptHashes.joined(separator: ","),
            newHashes.joined(separator: ",")
        ].joined(separator: "|")
    }
}
