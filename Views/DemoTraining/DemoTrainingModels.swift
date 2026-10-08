import Foundation
import CoreGraphics

enum DemoTrainingTourID: String, CaseIterable, Identifiable, Hashable {
    case projects
    case deadlines
    case budget
    case photos
    case profile
    case taskCalendar
    case calculator

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projects: return "Проекты"
        case .deadlines: return "Сроки"
        case .budget: return "Бюджет"
        case .photos: return "Фото"
        case .profile: return "Профиль"
        case .taskCalendar: return "Календарь задач"
        case .calculator: return "Калькулятор"
        }
    }

    var blurb: String {
        switch self {
        case .projects:
            return "Список объектов, карточка стройки, прогресс, этапы и быстрые действия."
        case .deadlines:
            return "Плановые и фактические даты, просрочки и детали по проекту."
        case .budget:
            return "План и факт расходов, детализация по этапам."
        case .photos:
            return "Общая лента, фильтры и просмотр снимков."
        case .profile:
            return "Настройки и особенности демо-режима."
        case .taskCalendar:
            return "Даты, список задач и вход в создание."
        case .calculator:
            return "Выбор расчёта, параметры и результат."
        }
    }

    var systemImage: String {
        switch self {
        case .projects: return "square.grid.2x2"
        case .deadlines: return "calendar.badge.clock"
        case .budget: return "chart.pie"
        case .photos: return "photo.on.rectangle"
        case .profile: return "person.crop.circle"
        case .taskCalendar: return "checklist"
        case .calculator: return "function"
        }
    }

    var isTool: Bool {
        switch self {
        case .taskCalendar, .calculator: return true
        default: return false
        }
    }

    /// All seven tours are interactive in the product build.
    var isImplemented: Bool { true }
}

enum DemoTrainingAnchorID: String, Hashable {
    // Projects
    case projectsListHeader
    case projectsDemoCard
    case projectsDashboardProgress
    /// Compact subset of the dashboard summary (progress + bar) when the full card is too tall.
    case projectsDashboardProgressFocus
    case projectsDashboardStages
    case projectsQuickActions

    // Deadlines («Сроки»)
    case deadlinesListHeader
    case deadlinesDemoCard
    case deadlinesPlanHeader
    case deadlinesTimelineIntro
    case deadlinesFirstStage

    // Budget («Бюджет»)
    case budgetListHeader
    case budgetDemoCard
    case budgetDetailHeader
    case budgetPlanFact
    case budgetOperations

    // Photos («Фото»)
    case photosSourceFilter
    case photosFilterSort
    case photosFirstGroupOrEmpty
    /// Fullscreen gallery opened by the photos tour (only when a real photo exists).
    case photosViewer

    // Profile («Профиль»)
    case profileAccountDemo
    case profileTheme
    /// «Создать профиль» lives in the DEMO banner on the Projects tab (explain only).
    case profileCreateProfileHint

    // Task calendar
    case taskCalendarEntryBanner
    case taskCalendarHeader
    case taskCalendarListOrEmpty
    case taskCalendarAddButton
    case taskCalendarFormDescription

    // Calculator
    case calculatorEntryButton
    case calculatorHomeList
    case calculatorConcreteParams
    case calculatorConcreteResult
}

/// Where the coach chrome is drawn for a step. Sheets sit above the root overlay,
/// so sheet steps draw their own overlay inside the presented content.
enum DemoTrainingSurface: Equatable {
    case root
    case sheet
}

struct DemoTrainingStep: Equatable, Identifiable {
    var id: String
    var anchor: DemoTrainingAnchorID
    var title: String
    var body: String
    /// Safe navigation before showing this step (open tab / push screen / present a sheet).
    /// Always navigation only — never a save, purchase or permission request.
    var arriveAction: DemoTrainingArriveAction?
    var surface: DemoTrainingSurface = .root
}

/// Navigation-only arrive actions. Each one describes the full target route
/// (see `DemoTrainingRoute`), so Next/Back are idempotent.
enum DemoTrainingArriveAction: Equatable {
    case selectTab(MainTab)
    case popToProjectsRoot
    /// Pop everything pushed on the currently selected tab and close tour sheets.
    case popToRootForCurrentTab
    case openDemoProjectDashboard
    case openDemoProjectPlan
    case openDemoBudgetDetail
    /// Budget detail with the «План / факт по этапам» block expanded (UI only).
    case expandBudgetPlanFact
    case openTasksCenter
    /// «Новая задача» sheet over the task calendar — closing it never saves.
    case presentNewTaskForm
    case presentCalculatorSheet
    /// Concrete calculator pushed inside the calculator sheet.
    case pushConcreteCalculator
    /// Fullscreen photo gallery over the Photos tab (existing viewer only).
    case presentPhotoViewer
}

/// Declarative navigation target for a tour step.
struct DemoTrainingRoute: Equatable {
    /// `nil` keeps the currently selected tab.
    var tab: MainTab?
    var dashboard = false
    var plan = false
    var budget = false
    var tasksCenter = false
    var taskForm = false
    var calculator = false
    var concrete = false
    var expandBudgetPlan = false
    var photoViewer = false

    var needsDemoProject: Bool { dashboard || plan || budget }

    /// Tab bar is visible and nothing is pushed or presented (root of a tab).
    var isTabRoot: Bool {
        !dashboard && !plan && !budget && !tasksCenter && !taskForm
            && !calculator && !concrete && !photoViewer
    }

    static func make(for action: DemoTrainingArriveAction) -> DemoTrainingRoute {
        switch action {
        case .selectTab(let tab):
            return DemoTrainingRoute(tab: tab)
        case .popToProjectsRoot:
            return DemoTrainingRoute(tab: .projects)
        case .popToRootForCurrentTab:
            return DemoTrainingRoute(tab: nil)
        case .openDemoProjectDashboard:
            return DemoTrainingRoute(tab: .projects, dashboard: true)
        case .openDemoProjectPlan:
            return DemoTrainingRoute(tab: .plan, plan: true)
        case .openDemoBudgetDetail:
            return DemoTrainingRoute(tab: .budget, budget: true)
        case .expandBudgetPlanFact:
            return DemoTrainingRoute(tab: .budget, budget: true, expandBudgetPlan: true)
        case .openTasksCenter:
            return DemoTrainingRoute(tab: .projects, tasksCenter: true)
        case .presentNewTaskForm:
            return DemoTrainingRoute(tab: .projects, tasksCenter: true, taskForm: true)
        case .presentCalculatorSheet:
            return DemoTrainingRoute(tab: .projects, calculator: true)
        case .pushConcreteCalculator:
            return DemoTrainingRoute(tab: .projects, calculator: true, concrete: true)
        case .presentPhotoViewer:
            return DemoTrainingRoute(tab: .photos, photoViewer: true)
        }
    }
}

enum DemoTrainingScrollHint: Equatable {
    case none
    case scrollDown
    case scrollUp
    case missingTarget
}

struct DemoTrainingAnchorFrame: Equatable {
    var id: DemoTrainingAnchorID
    var rect: CGRect
}
