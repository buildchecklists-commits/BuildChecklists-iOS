import Foundation

/// Главные вкладки приложения.
/// Должен быть Hashable для TabView(selection:).
enum MainTab: String, CaseIterable, Hashable {
    case projects
    case plan
    case budget
    case photos
    case profile
}
