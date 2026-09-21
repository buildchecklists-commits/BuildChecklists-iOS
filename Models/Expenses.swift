import Foundation

// MARK: - Expense Category (этап строительства)

enum ExpenseCategory: String, Codable, CaseIterable, Identifiable {
    case geologyAndPrep      // Геология и подготовка участка
    case foundation          // Фундамент
    case walls               // Стены
    case slabs               // Перекрытия
    case roof                // Крыша (включая покрытие)
    case engineering         // Инженерия
    case windows             // Окна
    case doors               // Двери
    case finishing           // Отделка
    case landscaping         // Благоустройство

    var id: String { rawValue }

    var title: String {
        switch self {
        case .geologyAndPrep: return "Геология и подготовка участка"
        case .foundation:     return "Фундамент"
        case .walls:          return "Стены"
        case .slabs:          return "Перекрытия"
        case .roof:           return "Крыша"
        case .engineering:    return "Инженерия"
        case .windows:        return "Окна"
        case .doors:          return "Двери"
        case .finishing:      return "Отделка"
        case .landscaping:    return "Благоустройство"
        }
    }

    var shortTitle: String {
        switch self {
        case .geologyAndPrep: return "Геология"
        case .foundation:     return "Фундамент"
        case .walls:          return "Стены"
        case .slabs:          return "Перекрытия"
        case .roof:           return "Крыша"
        case .engineering:    return "Инженерия"
        case .windows:        return "Окна"
        case .doors:          return "Двери"
        case .finishing:      return "Отделка"
        case .landscaping:    return "Благоустро."
        }
    }
}

// MARK: - Подкатегория

enum ExpenseSubCategory: String, Codable, CaseIterable, Identifiable {
    case materials   // Материалы
    case labor       // Работа
    case rent        // Аренда техники

    var id: String { rawValue }

    var title: String {
        switch self {
        case .materials: return "Материалы"
        case .labor:     return "Работа"
        case .rent:      return "Аренда техники"
        }
    }
}

// MARK: - Expense Item

struct ExpenseItem: Identifiable, Codable, Equatable {
    var id: UUID
    var projectID: UUID

    /// Основная категория расходов (для финансовых диаграмм)
    var category: ExpenseCategory

    /// Подкатегория (материалы / работа / аренда)
    var subCategory: ExpenseSubCategory

    /// Привязка к этапу прогресса (опционально!)
    var stageCategory: GlobalStageCategory?      // ← НОВОЕ
    var stageItemID: UUID?                       // ← НОВОЕ

    /// Сумма
    var amount: Decimal

    /// Дата
    var date: Date

    /// Комментарий
    var note: String?

    // MARK: Init

    init(
        id: UUID = UUID(),
        projectID: UUID,
        category: ExpenseCategory,
        subCategory: ExpenseSubCategory = .materials,
        stageCategory: GlobalStageCategory? = nil,
        stageItemID: UUID? = nil,
        amount: Decimal,
        date: Date = Date(),
        note: String? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.category = category
        self.subCategory = subCategory
        self.stageCategory = stageCategory
        self.stageItemID = stageItemID
        self.amount = amount
        self.date = date
        self.note = note
    }

    // MARK: - Migration-safe decoding

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        id          = try c.decode(UUID.self, forKey: .id)
        projectID   = try c.decode(UUID.self, forKey: .projectID)
        category    = try c.decode(ExpenseCategory.self, forKey: .category)
        amount      = try c.decode(Decimal.self, forKey: .amount)
        date        = try c.decode(Date.self, forKey: .date)
        note        = try c.decodeIfPresent(String.self, forKey: .note)

        // subCategory существовал не всегда — старые данные = materials
        subCategory = (try? c.decode(ExpenseSubCategory.self, forKey: .subCategory)) ?? .materials

        // stageCategory / stageItemID — оба новые, старые данные = nil
        stageCategory = try? c.decodeIfPresent(GlobalStageCategory.self, forKey: .stageCategory)
        stageItemID   = try? c.decodeIfPresent(UUID.self, forKey: .stageItemID)
    }
}

// MARK: - New Expense Input

struct NewExpenseInput {
    var projectID: UUID
    var category: ExpenseCategory
    var subCategory: ExpenseSubCategory

    /// Новое: привязка к этапу/чек-листу (опциональные)
    var stageCategory: GlobalStageCategory? = nil
    var stageItemID: UUID? = nil

    var amount: Decimal?
    var date: Date = Date()
    var note: String? = nil
}
