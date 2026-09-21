import Foundation

struct StageItem: Identifiable, Codable, Equatable {
    var id: UUID
    var code: String
    var title: String
    var note: String?
    var status: ItemStatus?
    var severity: Severity?
    var photoPaths: [String]
    var pdfPaths: [String]
    var infoSlug: String?
}
