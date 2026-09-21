import Foundation

/// Этап проекта.
/// Поддерживает плановые/фактические даты, причины просрочек и статус.
struct Stage: Identifiable, Codable, Equatable {

    // MARK: - Идентификаторы и базовая структура
    var id: UUID                       // уникальный ID этапа
    var title: String                  // название этапа
    var subtitle: String?              // подзаголовок
    var items: [StageItem]             // чек-лист этапа

    // MARK: - Новые поля (optional — старые проекты не ломаем)

    /// Плановая дата начала работ.
    var plannedStart: Date?

    /// Плановая дата окончания этапа.
    var plannedEnd: Date?

    /// Фактическое начало работы по этапу.
    var actualStart: Date?

    /// Фактическое завершение этапа.
    var actualEnd: Date?

    /// Причина просрочки (если есть).
    var delayReason: DelayReason?

    /// Дополнительный комментарий к причине просрочки.
    var delayComment: String?

    // MARK: - Вычисляемые свойства

    /// Этап завершен по факту?
    var isCompleted: Bool {
        actualEnd != nil
    }

    /// Этап просрочен сейчас или был завершён с опозданием.
    var isOverdue: Bool {
        switch status {
        case .delayed, .completedDelayed:
            return true
        default:
            return false
        }
    }

    /// Статус этапа:
    /// 1) Сначала смотрим на фактические даты (actualStart/actualEnd),
    /// 2) Если их нет — ориентируемся по плановым (plannedStart/plannedEnd) и текущей дате.
    var status: StageStatus {
        let now = Date()

        // 1. Фактические даты — важнее всего
        if let actualEnd = actualEnd {
            if let plannedEnd = plannedEnd, actualEnd > plannedEnd {
                // Завершён, но позже планового срока
                return .completedDelayed
            } else {
                // Завершён в срок (или без плана)
                return .completed
            }
        }

        if let _ = actualStart {
            // Этап реально начался, но по факту ещё не завершён
            if let plannedEnd = plannedEnd, now > plannedEnd {
                // Работаем после планового окончания → просрочка
                return .delayed
            } else {
                return .inProgress
            }
        }

        // 2. Фактических дат нет → используем плановые как ориентир

        if let plannedStart = plannedStart, let plannedEnd = plannedEnd {
            if now < plannedStart {
                // Ещё не наступило время начала
                return .notStarted
            } else if now >= plannedStart && now <= plannedEnd {
                // Сейчас между плановыми датами → этап "в работе" по календарю
                return .inProgress
            } else if now > plannedEnd {
                // Плановое окончание уже прошло, а факта нет → просрочка
                return .delayed
            }
        } else if let plannedEnd = plannedEnd {
            // Есть только плановый дедлайн
            if now <= plannedEnd {
                return .notStarted
            } else {
                return .delayed
            }
        }

        // Нет ни факта, ни плана — считаем не начатым
        return .notStarted
    }

    /// Готовность этапа по чек-листу (0…1)
    var progress: Double {
        guard !items.isEmpty else { return 0 }
        let ready = items.filter { $0.status == .ok }.count
        return Double(ready) / Double(items.count)
    }
}


// MARK: - Причины просрочки

enum DelayReason: String, Codable, CaseIterable {
    case weather      = "weather"       // погода
    case workers      = "workers"       // косяки/задержка рабочих
    case materials    = "materials"     // задержка/отсутствие материалов
    case customer     = "customer"      // задержка решений заказчика
    case docs         = "docs"          // документы / сети / согласования
    case planning     = "planning"      // ошибка планирования
    case other        = "other"         // другое

    var title: String {
        switch self {
        case .weather:   return "Погода"
        case .workers:   return "Рабочие"
        case .materials: return "Материалы"
        case .customer:  return "Заказчик"
        case .docs:      return "Документы/Сети"
        case .planning:  return "Планирование"
        case .other:     return "Другое"
        }
    }
}


// MARK: - Статус этапа

enum StageStatus: String, Codable {
    case notStarted        // не начат
    case inProgress        // в работе
    case completed         // завершён вовремя (или без плана)
    case completedDelayed  // завершён с просрочкой
    case delayed           // просрочен (ещё не завершён)
}
