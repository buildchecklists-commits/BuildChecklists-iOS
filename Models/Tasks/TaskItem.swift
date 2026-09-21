import Foundation

struct TaskItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var details: String?
    var projectID: UUID?
    var projectName: String?
    var dueDate: Date?
    var isCompleted: Bool
    var reminderDate: Date?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        projectID: UUID? = nil,
        projectName: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        reminderDate: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.projectID = projectID
        self.projectName = projectName
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.reminderDate = reminderDate
        self.createdAt = createdAt
    }
}
