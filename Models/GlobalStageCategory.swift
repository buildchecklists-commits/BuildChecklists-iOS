//  GlobalStageCategory.swift
//  BuildChecklists
//

import Foundation
import SwiftUI

/// Глобальные категории этапов строительства.
/// Используются для привязки расходов и фото к стадиям.
enum GlobalStageCategory: String, CaseIterable, Identifiable, Codable {

    case geologyAndPrep      // Геология и подготовка участка
    case foundation          // Фундамент
    case walls               // Стены
    case slabs               // Перекрытия
    case roof                // Крыша (стропильная часть)
    case roofCover           // Покрытие крыши (кровля, доборы)
    case engineering         // Инженерия
    case windows             // Окна
    case doors               // Двери
    case finishing           // Отделка
    case landscaping         // Благоустройство

    var id: String { rawValue }

    /// Название этапа (отображение в UI)
    var title: String {
        switch self {
        case .geologyAndPrep: return "Геология и подготовка участка"
        case .foundation:     return "Фундамент"
        case .walls:          return "Стены"
        case .slabs:          return "Перекрытия"
        case .roof:           return "Крыша"
        case .roofCover:      return "Покрытие крыши"
        case .engineering:    return "Инженерия"
        case .windows:        return "Окна"
        case .doors:          return "Двери"
        case .finishing:      return "Отделка"
        case .landscaping:    return "Благоустройство"
        }
    }

    /// Цвет маркеров/границ в GlobalPhotoView и других местах
    var color: Color {
        switch self {
        case .geologyAndPrep: return .brown
        case .foundation:     return .blue
        case .walls:          return .green
        case .slabs:          return .orange
        case .roof:           return .red
        case .roofCover:      return .cyan   // можешь поменять на любой другой
        case .engineering:    return .teal
        case .windows:        return .indigo
        case .doors:          return .mint
        case .finishing:      return .pink
        case .landscaping:    return .purple
        }
    }
}
