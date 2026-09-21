import Foundation

struct WallsPack: Codable {
    let title: String
    let stages: [WallsStageTemplate]
}

struct WallsStageTemplate: Codable {
    let title: String
    let items: [ItemTemplate]
}
