import Foundation

/// Пакет данных по фундаменту (из seed JSON)
struct FoundationPack: Codable, Identifiable {
    var id: UUID = UUID()
    let title: String
    let stages: [FoundationStageTemplate]

    enum CodingKeys: String, CodingKey {
        case title, stages
    }

    init(id: UUID = UUID(), title: String, stages: [FoundationStageTemplate]) {
        self.id = id
        self.title = title
        self.stages = stages
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.stages = (try? c.decode([FoundationStageTemplate].self, forKey: .stages)) ?? []
    }
}

/// Этап фундамента с элементами (терпимо читает строки или объекты)
struct FoundationStageTemplate: Codable, Identifiable {
    var id: UUID = UUID()
    let title: String
    let items: [FoundationItemTemplate]

    enum CodingKeys: String, CodingKey {
        case title, items
    }

    init(id: UUID = UUID(), title: String, items: [FoundationItemTemplate]) {
        self.id = id
        self.title = title
        self.items = items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = (try? c.decode(String.self, forKey: .title)) ?? ""
        self.items = (try? c.decode([FoundationItemTemplate].self, forKey: .items)) ?? []
    }
}

/// Универсальный элемент этапа — строка или объект {text/title, infoSlug}
struct FoundationItemTemplate: Codable, Identifiable {
    var id: UUID = UUID()
    var text: String
    var infoSlug: String?

    enum CodingKeys: String, CodingKey {
        case text, title, infoSlug
    }

    init(id: UUID = UUID(), text: String, infoSlug: String? = nil) {
        self.id = id
        self.text = text
        self.infoSlug = infoSlug
    }

    init(from decoder: Decoder) throws {
        // вариант: просто строка
        let single = try? decoder.singleValueContainer()
        if let s = try? single?.decode(String.self) {
            self.id = UUID()
            self.text = s
            self.infoSlug = nil
            return
        }

        // вариант: объект
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        if let t = try? c.decode(String.self, forKey: .text) {
            self.text = t
        } else if let t = try? c.decode(String.self, forKey: .title) {
            self.text = t
        } else {
            self.text = ""
        }
        self.infoSlug = try? c.decodeIfPresent(String.self, forKey: .infoSlug)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(infoSlug, forKey: .infoSlug)
    }
}
