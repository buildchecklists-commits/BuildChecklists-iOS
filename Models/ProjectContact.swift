import Foundation

struct ProjectContact: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var name: String           // Имя / название: "Иван Петров", "Бетонный завод №3"
    var role: String           // Роль: "Заказчик", "Бригадир", "Архитектор", "Поставщик бетона"
    var phone: String          // Телефон: +7...
    var note: String?          // Комментарий
    var isFavorite: Bool       // Важный контакт (звёздочка)
}
