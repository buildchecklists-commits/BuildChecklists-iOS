import Foundation

/// In-memory working-checklist snapshot for a future PDF. Nothing here is written to disk.
nonisolated struct ChecklistReportSource: Sendable, Equatable {
    var projectID: UUID
    var name: String
    var address: String
    var manager: String?
    var generatedAt: Date
    var dateStart: Date?
    var dateEnd: Date?
    var budget: Decimal?
    var projectDescription: String?
    var foundationTitle: String?
    var wallTitle: String?
    var slabTitle: String?
    var roofShapeTitle: String?
    var roofCoverTitle: String?
}

nonisolated struct ChecklistReportSnapshot: Sendable, Equatable {
    let projectID: UUID
    let projectName: String
    let address: String?
    let manager: String?
    let generatedAt: Date
    let dateStart: Date?
    let dateEnd: Date?
    let budget: Decimal?
    let projectDescription: String?
    let foundationTitle: String?
    let wallTitle: String?
    let slabTitle: String?
    let roofShapeTitle: String?
    let roofCoverTitle: String?
    /// Unrounded fraction. Same formula as the project card. See `ChecklistReportProgress`.
    let overallProgress: Double
    let packs: [ChecklistReportPack]
}

nonisolated enum ChecklistReportPackReadState: String, Sendable, Equatable {
    /// Missing storage is an empty readable pack. Decoded JSON, including `[]`, is also ready.
    case ready
    /// Storage exists but cannot be decoded, or the bytes cannot be read. The file is left untouched.
    case unreadable
}

nonisolated struct ChecklistReportPack: Sendable, Equatable, Identifiable {
    var id: ChecklistPack { pack }

    let pack: ChecklistPack
    let title: String
    let readState: ChecklistReportPackReadState
    /// User-facing text. Nil when `readState == .ready`. Never contains a filesystem path.
    let readError: String?
    let stages: [ChecklistReportStage]
    let itemCount: Int
    let doneCount: Int
    let issueCount: Int
    let notDoneCount: Int
    /// `ok / all items` for a ready pack. Unreadable packs contribute 0.
    let progress: Double
    /// Photo path links on `.issue` items. Display limit belongs to the PDF renderer.
    let issuePhotoCount: Int
}

nonisolated struct ChecklistReportStage: Sendable, Equatable, Identifiable {
    var id: UUID { stageID }

    let stageID: UUID
    let title: String
    let subtitle: String?
    let order: Int
    let items: [ChecklistReportItem]
    let itemCount: Int
    let doneCount: Int
    let issueCount: Int
    let notDoneCount: Int
    let progress: Double
}

nonisolated struct ChecklistReportItem: Sendable, Equatable, Identifiable {
    var id: UUID { itemID }

    let itemID: UUID
    let title: String
    let status: ItemStatus?
    let statusTitle: String
    /// Stage subtitle, when it has non-whitespace text.
    let sectionContext: String?
    /// `BCNotes/<itemID>.txt`. Nil when missing, empty, or not UTF-8. Not `StageItem.note`.
    let noteText: String?
    let photoPaths: [String]
    let photoCount: Int
    let missingPhotoCount: Int

    var hasMissingPhotos: Bool { missingPhotoCount > 0 }
}

/// Counts and the project-card progress formula. No file access.
nonisolated enum ChecklistReportProgress {
    /// Ten packs averaged by `ProjectDashboardView.overallProgress` and `ProjectsListView.overallProgress`.
    /// Doors are stored in the snapshot and have their own percent, but they are not in this list.
    static let overallPacks: [ChecklistPack] = [
        .geology,
        .foundation,
        .walls,
        .slab,
        .roof,
        .roofCover,
        .engineering,
        .windows,
        .finishing,
        .landscaping
    ]

    /// Denominator of the project card. A missing or unreadable pack still occupies one slot as 0.
    static var overallDenominator: Int { overallPacks.count }

    static let unreadablePackMessage = "Данные пакета не прочитаны."

    static func statusTitle(_ status: ItemStatus?) -> String {
        switch status {
        case .ok: return "Выполнено"
        case .issue: return "Проблема"
        case .na, .none: return "Не выполнено"
        }
    }

    static func counts(statuses: [ItemStatus?]) -> (total: Int, done: Int, issues: Int, notDone: Int) {
        let total = statuses.count
        let done = statuses.filter { $0 == .ok }.count
        let issues = statuses.filter { $0 == .issue }.count
        let notDone = total - done - issues
        return (total, done, issues, notDone)
    }

    /// `ok / all items`. Empty input is 0. `issue` and `na` are not done.
    static func fraction(done: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(done) / Double(total)
    }

    /// Sum of the ten card packs divided by 10. Missing keys and unreadable packs count as 0.
    static func overallFraction(_ packFractions: [ChecklistPack: Double]) -> Double {
        let sum = overallPacks.reduce(0.0) { partial, pack in
            partial + (packFractions[pack] ?? 0)
        }
        return sum / Double(overallDenominator)
    }

    /// Label rounding used by the stage screens. The stored fraction itself is not rounded.
    static func roundedDisplayPercent(_ fraction: Double) -> Int {
        Int((fraction * 100).rounded())
    }
}

nonisolated enum ChecklistReportSnapshotBuilder {
    static func make(from source: ChecklistReportSource) -> ChecklistReportSnapshot {
        let packs = ChecklistPack.allCases.map { pack in
            makePack(pack, projectID: source.projectID)
        }
        var fractions: [ChecklistPack: Double] = [:]
        for pack in packs where ChecklistReportProgress.overallPacks.contains(pack.pack) {
            fractions[pack.pack] = pack.progress
        }
        return ChecklistReportSnapshot(
            projectID: source.projectID,
            projectName: source.name,
            address: nonempty(source.address),
            manager: source.manager.flatMap(nonempty),
            generatedAt: source.generatedAt,
            dateStart: source.dateStart,
            dateEnd: source.dateEnd,
            budget: source.budget,
            projectDescription: source.projectDescription.flatMap(nonempty),
            foundationTitle: source.foundationTitle.flatMap(nonempty),
            wallTitle: source.wallTitle.flatMap(nonempty),
            slabTitle: source.slabTitle.flatMap(nonempty),
            roofShapeTitle: source.roofShapeTitle.flatMap(nonempty),
            roofCoverTitle: source.roofCoverTitle.flatMap(nonempty),
            overallProgress: ChecklistReportProgress.overallFraction(fractions),
            packs: packs
        )
    }

    private static func makePack(_ pack: ChecklistPack, projectID: UUID) -> ChecklistReportPack {
        switch classify(pack, projectID: projectID) {
        case .unreadable:
            return ChecklistReportPack(
                pack: pack,
                title: pack.title,
                readState: .unreadable,
                readError: ChecklistReportProgress.unreadablePackMessage,
                stages: [],
                itemCount: 0,
                doneCount: 0,
                issueCount: 0,
                notDoneCount: 0,
                progress: 0,
                issuePhotoCount: 0
            )
        case .ready:
            let stages = ChecklistPackStore.load(pack: pack, projectID: projectID)
            return packFromLoadedStages(pack, stages: stages)
        }
    }

    private static func packFromLoadedStages(_ pack: ChecklistPack, stages: [Stage]) -> ChecklistReportPack {
        let reportStages = stages.enumerated().map { index, stage in
            makeStage(stage, order: index)
        }
        let statuses = reportStages.flatMap { $0.items.map(\.status) }
        let counts = ChecklistReportProgress.counts(statuses: statuses)
        let issuePhotoCount = reportStages
            .flatMap(\.items)
            .filter { $0.status == .issue }
            .reduce(0) { $0 + $1.photoCount }
        return ChecklistReportPack(
            pack: pack,
            title: pack.title,
            readState: .ready,
            readError: nil,
            stages: reportStages,
            itemCount: counts.total,
            doneCount: counts.done,
            issueCount: counts.issues,
            notDoneCount: counts.notDone,
            progress: ChecklistReportProgress.fraction(done: counts.done, total: counts.total),
            issuePhotoCount: issuePhotoCount
        )
    }

    private static func makeStage(_ stage: Stage, order: Int) -> ChecklistReportStage {
        let sectionContext = nonempty(stage.subtitle ?? "")
        let items = stage.items.map { item in
            makeItem(item, sectionContext: sectionContext)
        }
        let counts = ChecklistReportProgress.counts(statuses: items.map(\.status))
        return ChecklistReportStage(
            stageID: stage.id,
            title: stage.title,
            subtitle: sectionContext,
            order: order,
            items: items,
            itemCount: counts.total,
            doneCount: counts.done,
            issueCount: counts.issues,
            notDoneCount: counts.notDone,
            progress: ChecklistReportProgress.fraction(done: counts.done, total: counts.total)
        )
    }

    private static func makeItem(_ item: StageItem, sectionContext: String?) -> ChecklistReportItem {
        let paths = item.photoPaths
        let missing = paths.filter { !photoFileExists($0) }.count
        return ChecklistReportItem(
            itemID: item.id,
            title: item.title,
            status: item.status,
            statusTitle: ChecklistReportProgress.statusTitle(item.status),
            sectionContext: sectionContext,
            noteText: ChecklistWorkingNote.readDisplayText(itemID: item.id),
            photoPaths: paths,
            photoCount: paths.count,
            missingPhotoCount: missing
        )
    }

    /// `load` collapses a corrupt payload and a missing file into `[]`.
    /// This probe only reads the same locations and does not create directories.
    private enum Classification {
        case ready
        case unreadable
    }

    private static func classify(_ pack: ChecklistPack, projectID: UUID) -> Classification {
        switch storedData(pack, projectID: projectID) {
        case .missing:
            return .ready
        case .unreadable:
            return .unreadable
        case .payload(let data):
            return (try? JSONDecoder().decode([Stage].self, from: data)) == nil ? .unreadable : .ready
        }
    }

    private enum StoredData {
        case missing
        case payload(Data)
        case unreadable
    }

    private static func storedData(_ pack: ChecklistPack, projectID: UUID) -> StoredData {
        switch pack {
        case .doors:
            return defaultsData(key: "doors_progress_\(projectID.uuidString)")
        case .roofCover:
            return defaultsData(key: "roofcover_progress_\(projectID.uuidString)")
        case .geology:
            return fileData(folderName: "BC_Geology", projectID: projectID)
        case .foundation:
            return fileData(folderName: "BC_Foundation", projectID: projectID)
        case .walls:
            return fileData(folderName: "BC_Walls", projectID: projectID)
        case .slab:
            return fileData(folderName: "BC_Slab", projectID: projectID)
        case .roof:
            return fileData(folderName: "BC_Roof", projectID: projectID)
        case .engineering:
            return fileData(folderName: "BC_Engineering", projectID: projectID)
        case .windows:
            return fileData(folderName: "BC_Windows", projectID: projectID)
        case .finishing:
            return fileData(folderName: "BC_Finishing", projectID: projectID)
        case .landscaping:
            return fileData(folderName: "BC_Landscaping", projectID: projectID)
        }
    }

    private static func fileData(folderName: String, projectID: UUID) -> StoredData {
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return .unreadable
        }
        let url = root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .missing
        }
        if isDirectory.boolValue {
            return .unreadable
        }
        do {
            return .payload(try Data(contentsOf: url))
        } catch {
            return .unreadable
        }
    }

    private static func defaultsData(key: String) -> StoredData {
        guard let data = UserDefaults.standard.data(forKey: key) else { return .missing }
        return .payload(data)
    }

    private static func nonempty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Same lookup as `existingFileURL`, without decoding pixels and without creating directories.
    private static func photoFileExists(_ path: String) -> Bool {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: path) { return true }
        if fileManager.fileExists(atPath: URL(fileURLWithPath: path).path) { return true }

        let fileName = (path as NSString).lastPathComponent
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let candidates = [
                docs.appendingPathComponent(path),
                docs.appendingPathComponent("BC_Media/PDF", isDirectory: true).appendingPathComponent(fileName),
                docs.appendingPathComponent("BC_Media/Images", isDirectory: true).appendingPathComponent(fileName),
                docs.appendingPathComponent("BCPhotos").appendingPathComponent(fileName),
                docs.appendingPathComponent("BCDocs").appendingPathComponent(fileName)
            ]
            if candidates.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
                return true
            }
        }

        let temporary = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: temporary.path) { return true }

        if let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let cached = caches.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: cached.path) { return true }
        }
        return false
    }
}
