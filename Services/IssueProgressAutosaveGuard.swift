import Foundation

/// Bumped when a confirmed progress write lands. A screen keeps the epoch it last claimed.
/// An older screen cannot write its snapshot over a newer one.
nonisolated enum IssueProgressEpoch {
    private static var value = 0
    static var current: Int { value }
    static func bump() { value += 1 }
}

enum IssueProgressSaveOutcome: Equatable {
    case saved(epoch: Int)
    case stale
    case refused
}

/// Points checklist saves at the history store for this process.
/// DEMO replaces it with the session memory store and never opens history files.
nonisolated enum IssueHistoryRuntime {
    private static var demoSession: IssueHistoryMemorySession?
    static var documentsDirectory: () -> URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static func beginDemoSession() {
        demoSession = IssueHistoryMemorySession()
    }

    static func endDemoSession() {
        demoSession = nil
    }

    static func store() -> IssueHistoryStore {
        if let demoSession {
            return IssueHistoryStore(memorySession: demoSession)
        }
        let root = documentsDirectory() ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return IssueHistoryStore(fileRoot: root)
    }

    static func pending(projectID: UUID, pack: ChecklistPack) throws -> [IssueHistoryPendingOperation] {
        try store().load(projectID: projectID).pending.filter { $0.identity.pack == pack }
    }
}

/// Stops `onChange` / `onDisappear` from writing an older in-memory item over a pending operation.
nonisolated enum IssueProgressAutosaveGuard {
    enum Adjustment {
        case write(stages: [Stage], bumpEpoch: Bool)
        case stale
        case refused
    }

    /// `.refused` means the history file could not be read. The caller must not write progress
    /// and must not present the in-memory edit as saved.
    static func adjusting(pack: ChecklistPack, projectID: UUID, memory: [Stage], epoch: Int) -> Adjustment {
        if epoch < IssueProgressEpoch.current {
            return .stale
        }
        let disk = ChecklistPackStore.load(pack: pack, projectID: projectID)
        let pending: [IssueHistoryPendingOperation]
        do {
            pending = try IssueHistoryRuntime.pending(projectID: projectID, pack: pack)
        } catch {
            return .refused
        }
        let merged = merging(memory: memory, disk: disk, pending: pending)
        return .write(stages: merged, bumpEpoch: !sameSignatures(signatures(merged), signatures(disk)))
    }

    /// Pure merge. A pending item is taken from disk unless memory already matches that disk item or the operation target.
    static func merging(
        memory: [Stage],
        disk: [Stage],
        pending: [IssueHistoryPendingOperation]
    ) -> [Stage] {
        let diskItems = Dictionary(uniqueKeysWithValues: disk.flatMap(\.items).map { ($0.id, $0) })
        var result = memory
        for operation in pending {
            guard let diskItem = diskItems[operation.identity.itemID] else { continue }
            for stageIndex in result.indices {
                guard let itemIndex = result[stageIndex].items.firstIndex(where: { $0.id == operation.identity.itemID }) else {
                    continue
                }
                let memoryItem = result[stageIndex].items[itemIndex]
                if sameProgress(memoryItem, diskItem) || matchesTarget(memoryItem, operation.target) {
                    continue
                }
                result[stageIndex].items[itemIndex] = diskItem
            }
        }
        return result
    }

    private static func signatures(_ stages: [Stage]) -> [(UUID, ItemStatus, [String])] {
        stages.flatMap { stage in
            stage.items.map { ($0.id, $0.status ?? .na, $0.photoPaths) }
        }
    }

    private static func sameSignatures(
        _ lhs: [(UUID, ItemStatus, [String])],
        _ rhs: [(UUID, ItemStatus, [String])]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for (left, right) in zip(lhs, rhs) {
            if left.0 != right.0 || left.1 != right.1 || left.2 != right.2 { return false }
        }
        return true
    }

    private static func sameProgress(_ lhs: StageItem, _ rhs: StageItem) -> Bool {
        (lhs.status ?? .na) == (rhs.status ?? .na) && lhs.photoPaths == rhs.photoPaths
    }

    private static func matchesTarget(_ item: StageItem, _ target: IssueHistorySnapshot) -> Bool {
        (item.status ?? .na) == target.status && item.photoPaths == target.photoPaths
    }

}

@MainActor
enum IssueProgressSaveFeedback {
    static let refusedNotification = Notification.Name("bc.issueHistory.saveRefused")
    static let message = "История замечаний повреждена. Изменение не сохранено. Повреждённый файл не изменён."

    static func apply(
        outcome: IssueProgressSaveOutcome,
        stages: [Stage],
        epoch: Int,
        reload: () -> [Stage]
    ) -> (stages: [Stage], epoch: Int) {
        switch outcome {
        case .saved(let newEpoch):
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
            return (stages, newEpoch)
        case .stale:
            return (stages, epoch)
        case .refused:
            let disk = reload()
            if disk != stages {
                NotificationCenter.default.post(name: refusedNotification, object: nil)
                return (disk, epoch)
            }
            return (stages, epoch)
        }
    }
}
