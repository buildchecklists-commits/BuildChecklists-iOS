import Foundation

enum ItemStatus: String, Codable, CaseIterable, Identifiable {
    case ok, issue, na
    var id: String { rawValue }
    var title: String {
        switch self {
        case .ok: return "ОК"
        case .issue: return "Проблема"
        case .na: return "Н/Д"   // не применяется / нет данных — считаем как 0% прогресса
        }
    }
}

enum Severity: String, Codable, CaseIterable, Identifiable {
    case low, medium, high
    var id: String { rawValue }
    var title: String {
        switch self {
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }
}
import Foundation

// MARK: - Типы фундамента
enum FoundationType: String, Codable, CaseIterable, Identifiable {
    case strip, slab, pile, tise, combo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strip: return "Ленточный"
        case .slab:  return "Плита"
        case .pile:  return "Свайно-ростверк"
        case .tise:  return "ТИСЭ"
        case .combo: return "Комбинированный"
        }
    }

    // имя набора в Assets/FoundationTypes
    var iconName: String {
        switch self {
        case .strip: return "v_found_strip"
        case .slab:  return "v_found_slab"
        case .pile:  return "v_found_pile"
        case .tise:  return "v_found_tise"
        case .combo: return "v_found_combo"
        }
    }
}

// MARK: - Материал стен
enum WallType: String, Codable, CaseIterable, Identifiable {
    case aac, keramBlock, brick, woodcrete, monolithic, keramzit, combo
    var id: String { rawValue }

    var title: String {
        switch self {
        case .aac:         return "Газобетон"
        case .keramBlock:  return "Керамоблок"
        case .brick:       return "Кирпич"
        case .woodcrete:   return "Арболит"
        case .monolithic:  return "Монолит"
        case .keramzit:    return "Керамзитобетон"
        case .combo:       return "Комбинированные"
        }
    }

    // имя набора в Assets/WallTypes
    var iconName: String {
        switch self {
        case .aac:         return "v_wall_aac"
        case .keramBlock:  return "v_wall_keramblock"
        case .brick:       return "v_wall_brick"
        case .woodcrete:   return "v_wall_woodcrete"
        case .monolithic:  return "v_wall_monolithic"
        case .keramzit:    return "v_wall_keramzit"
        case .combo:       return "v_wall_combo"
        }
    }
}

// MARK: - Перекрытия
enum SlabType: String, Codable, CaseIterable, Identifiable {
    case mono, pb, pc, steel, wood
    var id: String { rawValue }

    var title: String {
        switch self {
        case .mono:  return "Монолит"
        case .pb:    return "ПБ плита"
        case .pc:    return "ПК плита"
        case .steel: return "Плита перекрытия"
        case .wood:  return "Деревянное"
        }
    }

    // имя набора в Assets/SlabTypes
    var iconName: String {
        switch self {
        case .mono:  return "v_slab_mono"
        case .pb:    return "v_slab_pb"
        case .pc:    return "v_slab_pc"
        case .steel: return "v_slab_steel"      // фикс названия
        case .wood:  return "v_slab_wood"
        }
    }
}

// MARK: - Форма крыши
enum RoofShapeType: String, Codable, CaseIterable, Identifiable {
    case flat, gable, hip, mansard, shed, multi, tent, halfhip
    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat:    return "Плоская"
        case .gable:   return "Двускатная"
        case .hip:     return "Вальмовая"
        case .mansard: return "Мансардная"
        case .shed:    return "Односкатная"
        case .multi:   return "Многощипцовая"
        case .tent:    return "Шатровая"
        case .halfhip: return "Полувальмовая"
        }
    }

    // имя набора в Assets/RoofShapeTypes
    var iconName: String {
        switch self {
        case .flat:    return "v_roofshape_flat"
        case .gable:   return "v_roofshape_gable"
        case .hip:     return "v_roofshape_hip"
        case .mansard: return "v_roofshape_mansard"
        case .shed:    return "v_roofshape_shed"
        case .multi:   return "v_roofshape_multi"
        case .tent:    return "v_roofshape_tent"
        case .halfhip: return "v_roofshape_halfhip"
        }
    }
}

// MARK: - Покрытие крыши
enum RoofCoverType: String, Codable, CaseIterable, Identifiable {
    case metal, prof, seam, shingle, ceramic, composite, membrane
    var id: String { rawValue }

    var title: String {
        switch self {
        case .metal:     return "Металлочерепица"
        case .prof:      return "Профнастил"
        case .seam:      return "Фальцевая"
        case .shingle:   return "Гибкая черепица"
        case .ceramic:   return "Керамическая"
        case .composite: return "Композитная"
        case .membrane:  return "Мембрана/рулонная"
        }
    }

    // имя набора в Assets/RoofCoverTypes
    var iconName: String {
        switch self {
        case .metal:     return "v_roofcov_metal"
        case .prof:      return "v_roofcov_prof"
        case .seam:      return "v_roofcov_seam"
        case .shingle:   return "v_roofcover_shingle" // фикс: 'roofcover'
        case .ceramic:   return "v_roofcov_ceramic"
        case .composite: return "v_roofcov_composite"
        case .membrane:  return "v_roofcov_membrane"
        }
    }
}

