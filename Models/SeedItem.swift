import Foundation

/// Универсальный элемент стадии (чек-листа / seed JSON).
/// Поддерживает разные форматы JSON:
/// - "Просто строка"
/// - {"text": "..."} или {"title": "..."}
/// - {"code": "...", "title": "...", "infoSlug": "..."}
struct SeedItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var code: String
    var title: String
    var infoSlug: String?

    enum CodingKeys: String, CodingKey {
        case id, code, title, text, infoSlug
    }

    init(id: UUID = UUID(), code: String = "", title: String, infoSlug: String? = nil) {
        self.id = id
        self.code = code
        self.title = title
        self.infoSlug = infoSlug
    }

    init(from decoder: Decoder) throws {
        // Попробуем сначала как простую строку
        let single = try? decoder.singleValueContainer()
        if let s = try? single?.decode(String.self) {
            self.id = UUID()
            self.code = ""
            self.title = s
            self.infoSlug = nil
            return
        }

        // Иначе — объект
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.code = (try? c.decode(String.self, forKey: .code)) ?? ""

        // поддержка text / title
        if let t = try? c.decode(String.self, forKey: .title) {
            self.title = t
        } else if let t = try? c.decode(String.self, forKey: .text) {
            self.title = t
        } else {
            self.title = ""
        }

        self.infoSlug = try? c.decodeIfPresent(String.self, forKey: .infoSlug)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(code, forKey: .code)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(infoSlug, forKey: .infoSlug)
    }
}
