import Foundation

struct SlabPack: Codable {
    let title: String
    let stages: [SlabStageTemplate]
}

struct SlabStageTemplate: Codable {
    let title: String
    let items: [ItemTemplate]
}
