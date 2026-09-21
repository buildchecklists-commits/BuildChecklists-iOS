import Foundation

/// Умеет декодировать и простую строку, и объект { "text": "...", "infoSlug": "..." }
struct ItemTemplate: Codable {
    let text: String
    let infoSlug: String?

    init(text: String, infoSlug: String? = nil) {
        self.text = text
        self.infoSlug = infoSlug
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self.text = s
            self.infoSlug = nil
            return
        }
        struct Obj: Codable { let text: String; let infoSlug: String? }
        let o = try Obj(from: decoder)
        self.text = o.text
        self.infoSlug = o.infoSlug
    }

    func encode(to encoder: Encoder) throws {
        if infoSlug == nil {
            var c = encoder.singleValueContainer()
            try c.encode(text)
        } else {
            struct Obj: Codable { let text: String; let infoSlug: String? }
            try Obj(text: text, infoSlug: infoSlug).encode(to: encoder)
        }
    }
}
