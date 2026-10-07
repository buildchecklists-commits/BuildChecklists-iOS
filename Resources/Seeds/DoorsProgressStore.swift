import Foundation

enum DoorsProgressStore {

    private static func key(for projectID: UUID) -> String {
        "doors_progress_\(projectID.uuidString)"
    }

    static func load(projectID: UUID) -> [Stage]? {
        let k = key(for: projectID)
        guard let data = UserDefaults.standard.data(forKey: k) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([Stage].self, from: data)
        } catch {
            print("❌ DoorsProgressStore load error:", error)
            return nil
        }
    }

    @discardableResult
    static func save(projectID: UUID, stages: [Stage], epoch: Int) -> IssueProgressSaveOutcome {
        switch IssueProgressAutosaveGuard.adjusting(pack: .doors, projectID: projectID, memory: stages, epoch: epoch) {
        case .stale:
            return .stale
        case .refused:
            return .refused
        case .write(let stages, let bumpEpoch):
            let k = key(for: projectID)
            do {
                let data = try JSONEncoder().encode(stages)
                UserDefaults.standard.set(data, forKey: k)
                if bumpEpoch { IssueProgressEpoch.bump() }
            } catch {
                print("❌ DoorsProgressStore save error:", error)
            }
            return .saved(epoch: IssueProgressEpoch.current)
        }
    }
}
