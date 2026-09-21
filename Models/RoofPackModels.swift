import Foundation

struct RoofPack: Codable {
    let title: String
    let stages: [RoofStageTemplate]
}

struct RoofStageTemplate: Codable {
    let title: String
    let items: [ItemTemplate]
}
