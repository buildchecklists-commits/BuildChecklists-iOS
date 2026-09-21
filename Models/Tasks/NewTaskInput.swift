import Foundation

struct NewTaskInput {
    var title: String
    var details: String?
    var projectID: UUID?
    var projectName: String?
    var dueDate: Date?
    var reminderDate: Date?
}
