import Foundation

struct GeologyPack: Codable {
    let title: String
    let stages: [GeologyStageTemplate]
}

struct GeologyStageTemplate: Codable {
    let title: String
    let items: [ItemTemplate]  // поддерживает String и { "text", "infoSlug" }
}
