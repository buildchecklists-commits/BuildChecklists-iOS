import Foundation

/// Стадия проекта из seed-JSON.
struct SeedStage: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String?
    var order: Int?
    var items: [SeedItem]

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, order, items
    }

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String? = nil,
        order: Int? = nil,
        items: [SeedItem]
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.order = order
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.title = try c.decode(String.self, forKey: .title)
        self.subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        self.order = try c.decodeIfPresent(Int.self, forKey: .order)
        self.items = try c.decode([SeedItem].self, forKey: .items)
    }
}
