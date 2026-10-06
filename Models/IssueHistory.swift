import Foundation

/// Version of `Documents/BC_IssueHistory/<projectUUID>.json`.
nonisolated enum IssueHistorySchema {
    static let current = 1
}

/// How a case left «Проблема». `.resolved` does not mean the same thing as `.withdrawn`.
nonisolated enum IssueHistoryCloseKind: String, Codable, Equatable, Sendable {
    /// «Проблема устранена» (`.ok`).
    case resolved
    /// «Снять отметку» or block reset (`.na`). Not a claim that the defect was fixed.
    case withdrawn

    var title: String {
        switch self {
        case .resolved: return "Исправлено"
        case .withdrawn: return "Снято"
        }
    }
}

nonisolated enum IssueHistoryEventKind: String, Codable, Equatable, Sendable {
    case opened
    case updated
    case closed
    /// Existing issue adopted into history. This date is not a discovery date.
    case transferred
}

nonisolated enum IssueHistoryCaseState: Equatable, Sendable {
    case open
    case resolved
    case withdrawn
}

nonisolated enum IssueHistoryErrorCode: Equatable, Sendable {
    case corruptFile
    case photoCopyFailed
    case writeFailed
    case openCaseAlreadyExists
    case noOpenCase
    case caseNotFound
}

nonisolated struct IssueHistoryError: Error, Equatable {
    var code: IssueHistoryErrorCode
    var message: String
}

/// Checklist item a case is attached to. Titles are not part of the key.
nonisolated struct IssueHistoryItemKey: Hashable, Equatable, Sendable {
    var projectID: UUID
    var pack: ChecklistPack
    var stageID: UUID
    var itemID: UUID
}

/// Names and identifiers copied onto an event. The store does not look up live checklist rows.
nonisolated struct IssueHistoryIdentity: Equatable, Sendable {
    var projectID: UUID
    var pack: ChecklistPack
    var stageID: UUID
    var itemID: UUID
    var packTitle: String
    var stageTitle: String
    var itemTitle: String

    var itemKey: IssueHistoryItemKey {
        IssueHistoryItemKey(projectID: projectID, pack: pack, stageID: stageID, itemID: itemID)
    }
}

nonisolated struct IssueHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var kind: IssueHistoryEventKind
    /// When this event was recorded. Not a substitute for a missing discovery date.
    var at: Date
    var packTitle: String
    var stageTitle: String
    var itemTitle: String
    var note: String?
    /// Names inside `BC_IssueHistoryMedia/<projectID>/<eventID>/`. Never absolute paths.
    var photoFileNames: [String]
}

nonisolated struct IssueHistoryCase: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var projectID: UUID
    var pack: ChecklistPack
    var stageID: UUID
    var itemID: UUID
    /// Latest earlier case for the same item. Nil for the first case.
    var previousCaseID: UUID?
    /// Nil when nobody observed the moment the problem was found.
    var openedAt: Date?
    /// When an existing issue was adopted without a known discovery date. Not `openedAt`.
    var transferredAt: Date?
    var closedAt: Date?
    var closeKind: IssueHistoryCloseKind?
    var events: [IssueHistoryEvent]

    var itemKey: IssueHistoryItemKey {
        IssueHistoryItemKey(projectID: projectID, pack: pack, stageID: stageID, itemID: itemID)
    }

    var state: IssueHistoryCaseState {
        switch closeKind {
        case .resolved: return .resolved
        case .withdrawn: return .withdrawn
        case nil: return .open
        }
    }

    var isOpen: Bool { closeKind == nil }
}

nonisolated struct IssueHistoryDocument: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var projectID: UUID
    var cases: [IssueHistoryCase]

    static func empty(projectID: UUID) -> IssueHistoryDocument {
        IssueHistoryDocument(
            schemaVersion: IssueHistorySchema.current,
            projectID: projectID,
            cases: []
        )
    }

    func caseContaining(eventID: UUID) -> IssueHistoryCase? {
        cases.first { item in item.events.contains { $0.id == eventID } }
    }
}

nonisolated struct IssueHistoryOpen: Equatable, Sendable {
    var eventID: UUID
    var caseID: UUID
    var identity: IssueHistoryIdentity
    var at: Date
    var note: String?
    var photoURLs: [URL]
}

nonisolated struct IssueHistoryUpdate: Equatable, Sendable {
    var eventID: UUID
    var caseID: UUID
    var identity: IssueHistoryIdentity
    var at: Date
    var note: String?
    var photoURLs: [URL]
}

nonisolated struct IssueHistoryClose: Equatable, Sendable {
    var eventID: UUID
    var caseID: UUID
    var identity: IssueHistoryIdentity
    var at: Date
    var kind: IssueHistoryCloseKind
    var note: String?
    var photoURLs: [URL]
}

/// Adopts an existing issue. `at` is the transfer time. Discovery stays unknown.
nonisolated struct IssueHistoryTransfer: Equatable, Sendable {
    var eventID: UUID
    var caseID: UUID
    var identity: IssueHistoryIdentity
    var at: Date
    var note: String?
    var photoURLs: [URL]
}

nonisolated enum IssueHistoryCommand: Equatable, Sendable {
    case open(IssueHistoryOpen)
    case update(IssueHistoryUpdate)
    case close(IssueHistoryClose)
    case transfer(IssueHistoryTransfer)

    var eventID: UUID {
        switch self {
        case .open(let command): return command.eventID
        case .update(let command): return command.eventID
        case .close(let command): return command.eventID
        case .transfer(let command): return command.eventID
        }
    }

    var projectID: UUID {
        switch self {
        case .open(let command): return command.identity.projectID
        case .update(let command): return command.identity.projectID
        case .close(let command): return command.identity.projectID
        case .transfer(let command): return command.identity.projectID
        }
    }
}
