import Foundation

/// In-memory pack of a working checklist. Not persisted.
nonisolated enum ChecklistPack: String, CaseIterable, Equatable, Sendable {
    case geology
    case foundation
    case walls
    case slab
    case roof
    case roofCover
    case engineering
    case windows
    case doors
    case finishing
    case landscaping

    var title: String {
        switch self {
        case .geology: return "Геология и подготовка участка"
        case .foundation: return "Фундамент"
        case .walls: return "Стены"
        case .slab: return "Перекрытия"
        case .roof: return "Крыша"
        case .roofCover: return "Покрытие крыши"
        case .engineering: return "Инженерия"
        case .windows: return "Окна"
        case .doors: return "Двери"
        case .finishing: return "Отделка"
        case .landscaping: return "Благоустройство"
        }
    }
}

/// Derived issue row. Exists only in memory; not a stored entity.
nonisolated struct ChecklistIssueRef: Identifiable, Equatable, Sendable {
    var id: String { "\(pack.rawValue)|\(stageID.uuidString)|\(itemID.uuidString)" }

    let projectID: UUID
    let pack: ChecklistPack
    let stageID: UUID
    let itemID: UUID
    let packTitle: String
    let stageTitle: String
    let itemTitle: String
    let blockSubtitle: String?
    /// Trimmed `BCNotes/<itemUUID>.txt` for display. Nil if missing, unreadable, or whitespace-only.
    let noteText: String?
    let photoCount: Int
    /// First `photoPaths` entry, if any. Collector does not load image data.
    let firstPhotoPath: String?

    var hasPhotos: Bool { photoCount > 0 }
    var hasNote: Bool { noteText != nil }
}

nonisolated enum ProjectIssuesCollector {

    /// Reads all 11 working-checklist stores without merge or save.
    static func issues(for projectID: UUID) -> [ChecklistIssueRef] {
        let packs = ChecklistPack.allCases.map { pack in
            (pack, ChecklistPackStore.load(pack: pack, projectID: projectID))
        }
        return ChecklistIssuesReducer.collect(
            projectID: projectID,
            packs: packs,
            noteTextForItem: { ChecklistWorkingNote.readDisplayText(itemID: $0) }
        )
    }
}

/// Read-only access to working-item notes.
/// Path matches `ChecklistItemRow2`: `Documents/BCNotes/<itemUUID>.txt`.
/// Does not create folders or files and does not write.
nonisolated enum ChecklistWorkingNote {
    static func fileURL(itemID: UUID, documentsDirectory: URL) -> URL {
        documentsDirectory
            .appendingPathComponent("BCNotes", isDirectory: true)
            .appendingPathComponent("\(itemID.uuidString).txt")
    }

    static func documentsDirectory() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    static func fileURL(itemID: UUID) -> URL? {
        guard let documents = documentsDirectory() else { return nil }
        return fileURL(itemID: itemID, documentsDirectory: documents)
    }

    static func readDisplayText(itemID: UUID) -> String? {
        guard let documents = documentsDirectory() else { return nil }
        return readDisplayText(itemID: itemID, documentsDirectory: documents)
    }

    /// Missing, unreadable, non-UTF8, empty, or whitespace-only files yield `nil`.
    static func readDisplayText(itemID: UUID, documentsDirectory: URL, fileManager: FileManager = .default) -> String? {
        guard let raw = readRawText(itemID: itemID, documentsDirectory: documentsDirectory, fileManager: fileManager) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Raw UTF-8 contents. Nil if the file is missing or unreadable. Empty files return `""`.
    static func readRawText(itemID: UUID) -> String? {
        guard let documents = documentsDirectory() else { return nil }
        return readRawText(itemID: itemID, documentsDirectory: documents)
    }

    static func readRawText(itemID: UUID, documentsDirectory: URL, fileManager: FileManager = .default) -> String? {
        let url = fileURL(itemID: itemID, documentsDirectory: documentsDirectory)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Creates `BCNotes` only when writing. Matches `ChecklistItemRow2` format.
    static func write(_ text: String, itemID: UUID) throws {
        guard let documents = documentsDirectory() else {
            throw cocoaError(.fileNoSuchFile, "Documents unavailable")
        }
        let notesDir = documents.appendingPathComponent("BCNotes", isDirectory: true)
        try FileManager.default.createDirectory(at: notesDir, withIntermediateDirectories: true)
        let url = fileURL(itemID: itemID, documentsDirectory: documents)
        guard let data = text.data(using: .utf8) else {
            throw cocoaError(.fileWriteInapplicableStringEncoding, "UTF-8 encode failed")
        }
        try data.write(to: url, options: .atomic)
    }

    static func deleteIfExists(itemID: UUID) throws {
        guard let url = fileURL(itemID: itemID) else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private static func cocoaError(_ code: CocoaError.Code, _ message: String) -> NSError {
        NSError(
            domain: NSCocoaErrorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

nonisolated enum ChecklistIssuesReducer {

    /// Pure mapping: filter `.issue`, keep store order, skip duplicate composite ids.
    /// `noteTextForItem` is invoked only for `.issue` items. It must not write.
    static func collect(
        projectID: UUID,
        packs: [(ChecklistPack, [Stage])],
        noteTextForItem: (UUID) -> String?
    ) -> [ChecklistIssueRef] {
        var seen = Set<String>()
        var result: [ChecklistIssueRef] = []

        for (pack, stages) in packs {
            for stage in stages {
                for item in stage.items {
                    guard item.status == .issue else { continue }
                    let ref = ChecklistIssueRef(
                        projectID: projectID,
                        pack: pack,
                        stageID: stage.id,
                        itemID: item.id,
                        packTitle: pack.title,
                        stageTitle: stage.title,
                        itemTitle: item.title,
                        blockSubtitle: {
                            let trimmed = stage.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
                            return (trimmed?.isEmpty == false) ? trimmed : nil
                        }(),
                        noteText: noteTextForItem(item.id),
                        photoCount: item.photoPaths.count,
                        firstPhotoPath: item.photoPaths.first
                    )
                    if seen.insert(ref.id).inserted {
                        result.append(ref)
                    }
                }
            }
        }

        return result
    }
}

// MARK: - Pack ProgressStore adapter (same files/keys as the 11 stores)

nonisolated enum ChecklistPackStore {
    static func load(pack: ChecklistPack, projectID: UUID) -> [Stage] {
        switch pack {
        case .doors:
            return decodeDefaults(key: "doors_progress_\(projectID.uuidString)")
        case .roofCover:
            return decodeDefaults(key: "roofcover_progress_\(projectID.uuidString)")
        case .geology:
            return decodeFile(folderName: "BC_Geology", projectID: projectID)
        case .foundation:
            return decodeFile(folderName: "BC_Foundation", projectID: projectID)
        case .walls:
            return decodeFile(folderName: "BC_Walls", projectID: projectID)
        case .slab:
            return decodeFile(folderName: "BC_Slab", projectID: projectID)
        case .roof:
            return decodeFile(folderName: "BC_Roof", projectID: projectID)
        case .engineering:
            return decodeFile(folderName: "BC_Engineering", projectID: projectID)
        case .windows:
            return decodeFile(folderName: "BC_Windows", projectID: projectID)
        case .finishing:
            return decodeFile(folderName: "BC_Finishing", projectID: projectID)
        case .landscaping:
            return decodeFile(folderName: "BC_Landscaping", projectID: projectID)
        }
    }

    static func save(pack: ChecklistPack, projectID: UUID, stages: [Stage]) {
        switch pack {
        case .doors:
            encodeDefaults(key: "doors_progress_\(projectID.uuidString)", stages: stages)
        case .roofCover:
            encodeDefaults(key: "roofcover_progress_\(projectID.uuidString)", stages: stages)
        case .geology:
            encodeFile(folderName: "BC_Geology", projectID: projectID, stages: stages)
        case .foundation:
            encodeFile(folderName: "BC_Foundation", projectID: projectID, stages: stages)
        case .walls:
            encodeFile(folderName: "BC_Walls", projectID: projectID, stages: stages)
        case .slab:
            encodeFile(folderName: "BC_Slab", projectID: projectID, stages: stages)
        case .roof:
            encodeFile(folderName: "BC_Roof", projectID: projectID, stages: stages)
        case .engineering:
            encodeFile(folderName: "BC_Engineering", projectID: projectID, stages: stages)
        case .windows:
            encodeFile(folderName: "BC_Windows", projectID: projectID, stages: stages)
        case .finishing:
            encodeFile(folderName: "BC_Finishing", projectID: projectID, stages: stages)
        case .landscaping:
            encodeFile(folderName: "BC_Landscaping", projectID: projectID, stages: stages)
        }
    }

    /// Reads JSON if present. Does not create folders and does not write.
    private static func decodeFile(folderName: String, projectID: UUID) -> [Stage] {
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return []
        }
        let url = root
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("\(projectID.uuidString).json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Stage].self, from: data)) ?? []
    }

    private static func decodeDefaults(key: String) -> [Stage] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Stage].self, from: data)) ?? []
    }

    private static func encodeFile(folderName: String, projectID: UUID, stages: [Stage]) {
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = root.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(projectID.uuidString).json")
        guard let data = try? JSONEncoder().encode(stages) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func encodeDefaults(key: String, stages: [Stage]) {
        guard let data = try? JSONEncoder().encode(stages) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
