import Foundation

// MARK: - Project Models

struct Project: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var address: String
    var dateStart: Date?
    var dateEnd: Date?
    var budget: Decimal?
    var manager: String?
    var coverImagePath: String?
    var description: String?

    // Выбор пользователя (опционально)
    var foundationType: FoundationType?
    var wallType: WallType?
    var slabType: SlabType?
    var roofShapeType: RoofShapeType?
    var roofCoverType: RoofCoverType?

    // Новый функционал
    /// Цвет карточки (softYellow / softBlue / softGreen / softPink / softGray)
    var cardColor: String?

    /// Дата последнего обновления проекта (используется для сортировки)
    var lastUpdated: Date?

    /// Этапы проекта (чек-листы)
    var stages: [Stage]

    /// Важные контакты по проекту (заказчик, бригадир, поставщики и т.д.)
    var contacts: [ProjectContact] = []

    /// Фото проекта (общие, не по чек-листам)
    var photoPaths: [String] = []

    /// Документы проекта (сметы, договора, акты и пр.)
    var documentPaths: [String] = []

    /// Основной файл проекта (обычно PDF с планами/чертежами)
    var projectPDFPath: String? = nil

    /// Плановый бюджет по этапам (по глобальным категориям строительства).
    /// Ключ — GlobalStageCategory, значение — сумма в рублях.
    /// Для старых проектов по умолчанию будет пустой словарь.
    var plannedBudgetByStage: [GlobalStageCategory: Decimal] = [:]

    // MARK: - CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case dateStart
        case dateEnd
        case budget
        case manager
        case coverImagePath
        case description

        case foundationType
        case wallType
        case slabType
        case roofShapeType
        case roofCoverType

        case cardColor
        case lastUpdated

        case stages
        case contacts
        case photoPaths
        case documentPaths
        case projectPDFPath

        case plannedBudgetByStage
    }

    // MARK: - Custom Codable

    init(
        id: UUID,
        name: String,
        address: String,
        dateStart: Date? = nil,
        dateEnd: Date? = nil,
        budget: Decimal? = nil,
        manager: String? = nil,
        coverImagePath: String? = nil,
        description: String? = nil,
        foundationType: FoundationType? = nil,
        wallType: WallType? = nil,
        slabType: SlabType? = nil,
        roofShapeType: RoofShapeType? = nil,
        roofCoverType: RoofCoverType? = nil,
        cardColor: String? = nil,
        lastUpdated: Date? = nil,
        stages: [Stage],
        contacts: [ProjectContact] = [],
        photoPaths: [String] = [],
        documentPaths: [String] = [],
        projectPDFPath: String? = nil,
        plannedBudgetByStage: [GlobalStageCategory: Decimal] = [:]
    ) {
        self.id = id
        self.name = name
        self.address = address
        self.dateStart = dateStart
        self.dateEnd = dateEnd
        self.budget = budget
        self.manager = manager
        self.coverImagePath = coverImagePath
        self.description = description

        self.foundationType = foundationType
        self.wallType = wallType
        self.slabType = slabType
        self.roofShapeType = roofShapeType
        self.roofCoverType = roofCoverType

        self.cardColor = cardColor
        self.lastUpdated = lastUpdated

        self.stages = stages
        self.contacts = contacts
        self.photoPaths = photoPaths
        self.documentPaths = documentPaths
        self.projectPDFPath = projectPDFPath

        self.plannedBudgetByStage = plannedBudgetByStage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Обязательные поля (были всегда)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        address = try container.decode(String.self, forKey: .address)

        // Опциональные поля / могут отсутствовать в старых JSON
        dateStart = try container.decodeIfPresent(Date.self, forKey: .dateStart)
        dateEnd = try container.decodeIfPresent(Date.self, forKey: .dateEnd)
        budget = try container.decodeIfPresent(Decimal.self, forKey: .budget)
        manager = try container.decodeIfPresent(String.self, forKey: .manager)
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
        description = try container.decodeIfPresent(String.self, forKey: .description)

        foundationType = try container.decodeIfPresent(FoundationType.self, forKey: .foundationType)
        wallType = try container.decodeIfPresent(WallType.self, forKey: .wallType)
        slabType = try container.decodeIfPresent(SlabType.self, forKey: .slabType)
        roofShapeType = try container.decodeIfPresent(RoofShapeType.self, forKey: .roofShapeType)
        roofCoverType = try container.decodeIfPresent(RoofCoverType.self, forKey: .roofCoverType)

        cardColor = try container.decodeIfPresent(String.self, forKey: .cardColor)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated)

        // Коллекции — безопасно подставляем [] если ключа нет
        stages = try container.decodeIfPresent([Stage].self, forKey: .stages) ?? []
        contacts = try container.decodeIfPresent([ProjectContact].self, forKey: .contacts) ?? []
        photoPaths = try container.decodeIfPresent([String].self, forKey: .photoPaths) ?? []
        documentPaths = try container.decodeIfPresent([String].self, forKey: .documentPaths) ?? []
        projectPDFPath = try container.decodeIfPresent(String.self, forKey: .projectPDFPath)

        // Новое поле — по умолчанию пустой словарь,
        // если его нет в старых данных.
        plannedBudgetByStage = try container.decodeIfPresent(
            [GlobalStageCategory: Decimal].self,
            forKey: .plannedBudgetByStage
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(address, forKey: .address)

        try container.encodeIfPresent(dateStart, forKey: .dateStart)
        try container.encodeIfPresent(dateEnd, forKey: .dateEnd)
        try container.encodeIfPresent(budget, forKey: .budget)
        try container.encodeIfPresent(manager, forKey: .manager)
        try container.encodeIfPresent(coverImagePath, forKey: .coverImagePath)
        try container.encodeIfPresent(description, forKey: .description)

        try container.encodeIfPresent(foundationType, forKey: .foundationType)
        try container.encodeIfPresent(wallType, forKey: .wallType)
        try container.encodeIfPresent(slabType, forKey: .slabType)
        try container.encodeIfPresent(roofShapeType, forKey: .roofShapeType)
        try container.encodeIfPresent(roofCoverType, forKey: .roofCoverType)

        try container.encodeIfPresent(cardColor, forKey: .cardColor)
        try container.encodeIfPresent(lastUpdated, forKey: .lastUpdated)

        try container.encode(stages, forKey: .stages)
        try container.encode(contacts, forKey: .contacts)
        try container.encode(photoPaths, forKey: .photoPaths)
        try container.encode(documentPaths, forKey: .documentPaths)
        try container.encodeIfPresent(projectPDFPath, forKey: .projectPDFPath)

        try container.encode(plannedBudgetByStage, forKey: .plannedBudgetByStage)
    }

    // MARK: - Mutating updates helper

    /// Метод для безопасного обновления проекта с автоматическим обновлением lastUpdated.
    mutating func update(
        name: String? = nil,
        address: String? = nil,
        cardColor: String? = nil,
        description: String? = nil
    ) {
        if let name = name { self.name = name }
        if let address = address { self.address = address }
        if let cardColor = cardColor { self.cardColor = cardColor }
        if let description = description { self.description = description }
        self.lastUpdated = Date()
    }

    // MARK: - Плановый бюджет по этапам (helpers)

    /// Получить плановый бюджет по конкретному этапу.
    /// Если не задан — вернёт 0.
    func plannedBudget(for stage: GlobalStageCategory) -> Decimal {
        plannedBudgetByStage[stage] ?? 0
    }

    /// Установить / обновить плановый бюджет для этапа.
    /// Если value == nil или <= 0 — значение для этапа удаляется.
    /// Автоматически обновляет lastUpdated.
    mutating func setPlannedBudget(_ value: Decimal?, for stage: GlobalStageCategory) {
        if let value = value, value > 0 {
            plannedBudgetByStage[stage] = value
        } else {
            plannedBudgetByStage.removeValue(forKey: stage)
        }
        lastUpdated = Date()
    }
}

// MARK: - New Project Input

struct NewProjectInput {
    var name: String
    var address: String
    var dateStart: Date?
    var dateEnd: Date?
    var budget: Decimal?
    var manager: String?
    var description: String?

    // Опциональные параметры
    var foundationType: FoundationType? = nil
    var wallType: WallType? = nil
    var slabType: SlabType? = nil
    var roofShapeType: RoofShapeType? = nil
    var roofCoverType: RoofCoverType? = nil

    // Новые поля
    var cardColor: String? = nil
    var lastUpdated: Date? = Date()  // при создании проекта
}

// MARK: - Deadline Calculations

extension Project {
    /// Кол-во дней до дедлайна (может быть отрицательным, если срок прошёл)
    var deadlineWarningDays: Int? {
        guard let end = dateEnd else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: end).day ?? 0
        return days
    }
}
