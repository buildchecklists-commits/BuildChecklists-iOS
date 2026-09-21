import Foundation

/// In-memory pack of a working checklist. Not persisted.
enum ChecklistPack: String, CaseIterable, Equatable {
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
struct ChecklistIssueRef: Identifiable, Equatable {
    var id: String { "\(pack.rawValue)|\(stageID.uuidString)|\(itemID.uuidString)" }

    let projectID: UUID
    let pack: ChecklistPack
    let stageID: UUID
    let itemID: UUID
    let packTitle: String
    let stageTitle: String
    let itemTitle: String
    let blockSubtitle: String?
    let photoCount: Int

    var hasPhotos: Bool { photoCount > 0 }
}

enum ProjectIssuesCollector {

    /// Reads all 11 working-checklist stores without merge or save.
    static func issues(for projectID: UUID) -> [ChecklistIssueRef] {
        let packs = ChecklistPack.allCases.map { pack in
            (pack, loadStages(for: pack, projectID: projectID))
        }
        return ChecklistIssuesReducer.collect(projectID: projectID, packs: packs)
    }
}

enum ChecklistIssuesReducer {

    /// Pure mapping: filter `.issue`, keep store order, skip duplicate composite ids.
    static func collect(
        projectID: UUID,
        packs: [(ChecklistPack, [Stage])]
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
                        photoCount: item.photoPaths.count
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

// MARK: - Read-only storage adapter

private extension ProjectIssuesCollector {

    static func loadStages(for pack: ChecklistPack, projectID: UUID) -> [Stage] {
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

    /// Reads JSON if present. Does not create folders and does not write.
    static func decodeFile(folderName: String, projectID: UUID) -> [Stage] {
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

    /// Reads UserDefaults blob if present. Does not write.
    static func decodeDefaults(key: String) -> [Stage] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Stage].self, from: data)) ?? []
    }
}
