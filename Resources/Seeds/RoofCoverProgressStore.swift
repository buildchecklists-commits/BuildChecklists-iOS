import Foundation

enum RoofCoverProgressStore {

    private static func key(projectID: UUID) -> String {
        "roofcover_progress_\(projectID.uuidString)"
    }

    @discardableResult
    static func save(projectID: UUID, stages: [Stage], epoch: Int) -> IssueProgressSaveOutcome {
        switch IssueProgressAutosaveGuard.adjusting(pack: .roofCover, projectID: projectID, memory: stages, epoch: epoch) {
        case .stale:
            return .stale
        case .refused:
            return .refused
        case .write(let stages, let bumpEpoch):
            do {
                let data = try JSONEncoder().encode(stages)
                UserDefaults.standard.set(data, forKey: key(projectID: projectID))
                if bumpEpoch { IssueProgressEpoch.bump() }
            } catch {
                print("❌ RoofCoverProgressStore.save error:", error)
            }
            return .saved(epoch: IssueProgressEpoch.current)
        }
    }

    static func load(projectID: UUID) -> [Stage]? {
        guard let data = UserDefaults.standard.data(forKey: key(projectID: projectID)) else {
            return nil
        }
        do {
            return try JSONDecoder().decode([Stage].self, from: data)
        } catch {
            print("❌ RoofCoverProgressStore.load error:", error)
            return nil
        }
    }

    static func clear(projectID: UUID) {
        UserDefaults.standard.removeObject(forKey: key(projectID: projectID))
    }
}
