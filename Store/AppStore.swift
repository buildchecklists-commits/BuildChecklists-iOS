import Foundation
import SwiftUI
import Combine
import PDFKit
import UniformTypeIdentifiers
import UIKit
import UserNotifications
import CoreText
import CoreFoundation

// MARK: - User role & errors

enum UserRole: String, CaseIterable {
    case demo      // демо-режим, без сохранения на диск
    case user      // подписка USER: до 2 проектов
    case pro       // подписка PRO: без ограничений
}

enum AppStoreError: Error {
    case projectLimitReached
    case subscriptionExpiredReadOnly
}

@MainActor
final class AppStore: ObservableObject {

    // MARK: - Keys

    private let userRoleKey = "bc.user.role"
    private let selectedTabKey = "bc.ui.selectedTab"
    /// Технический UUID последнего demo-проекта: нужен, чтобы удалить progress-файлы после kill до создания нового demo.
    private let lastDemoProjectIDKey = "bc_last_demo_project_id"
    private var didPrefillDemoProgressInSession = false
    private var didPrefillDemoProgressStoresInSession = false
    private var didPrefillDemoExpensesInSession = false
    private var didPrefillDemoPhotosInSession = false
    private var didPrefillDemoTimelineInSession = false
    private var didPrefillDemoPlannedBudgetByStageInSession = false

    // MARK: - Published state

    @Published private(set) var projects: [Project] = []
    @Published private(set) var expenses: [ExpenseItem] = []
    @Published private(set) var tasks: [TaskItem] = []

    @Published private(set) var isRegistered: Bool = false
    @Published private(set) var userRole: UserRole = .demo

    /// DEMO: всё можно, но данные не сохраняем.
    @Published private(set) var isDemoMode: Bool = false

    /// Read-only при истёкшей подписке (USER или PRO).
    @Published private(set) var isReadOnlyMode: Bool = false

    @Published private(set) var seeds: [SeedStage] = []
    @Published private(set) var selectedTab: MainTab = .projects

    /// Совместимость со старым UI: раньше это был “накопительный” счётчик.
    /// Теперь логика правильная: это текущее количество активных проектов.
    var createdProjectsCount: Int { projects.count }

    // MARK: - Derived state

    var canCreateNewProject: Bool {
        if isReadOnlyMode { return false }

        switch userRole {
        case .demo:
            return true
        case .pro:
            return true
        case .user:
            return projects.count < 2
        }
    }

    var canEditAnything: Bool {
        if isDemoMode { return true }
        return !isReadOnlyMode
    }

    // MARK: - Services

    private let storage = StorageService()
    private let auth = AuthService()
    private let markdown = MarkdownLoader()
    private let media = MediaService()
    private let seedLoader = SeedPackLoader()

    /// StoreKit подписки
    let subscription = SubscriptionService()

    init() {
        BCTiming.log("AppStore init end (все сервисы созданы)")
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        BCTiming.log("bootstrap start")
        // 1) регистрация
        isRegistered = auth.loadRegistrationFlag()
        BCTiming.log("bootstrap: loadRegistrationFlag done")

        // 2) локальная роль
        loadUserRole()
        loadSelectedTab()
        BCTiming.log("bootstrap: loadUserRole/loadSelectedTab done")

        // 3) DEMO НЕ должен включаться автоматически на холодном старте.
        // DEMO включается только по нажатию кнопки "Попробовать демо".
        isDemoMode = false

        // 4) StoreKit -> применяем правила подписки
        if !isDemoMode {
            BCTiming.log("bootstrap: refreshEntitlements start")
            await subscription.refreshEntitlements()
            BCTiming.log("bootstrap: refreshEntitlements end")
            applySubscriptionToRoleAndAccess()
        } else {
            isReadOnlyMode = false
            userRole = .demo
        }

        // 5) seeds
        BCTiming.log("bootstrap: loadSeedStages start")
        do {
            seeds = try markdown.loadSeedStages()
            BCTiming.log("bootstrap: loadSeedStages end (\(seeds.count) stages)")
            debugPrint("🌱 Seeds loaded:", seeds.count)
        } catch {
            seeds = []
            BCTiming.log("bootstrap: loadSeedStages error - \(error.localizedDescription)")
            debugPrint("❌ Seeds load error:", error.localizedDescription)
        }

        // DEMO → не грузим и не сохраняем
        guard !isDemoMode else {
            BCTiming.log("bootstrap end (demo, skip storage)")
            debugPrint("🔸 Demo mode active — skip loading projects/expenses/tasks")
            projects = []
            expenses = []
            tasks = []
            return
        }

        // 6) load projects/expenses/tasks (даже если read-only — загрузка разрешена)
        BCTiming.log("bootstrap: loadProjects start")
        do {
            projects = try storage.loadProjects()
            BCTiming.log("bootstrap: loadProjects end (\(projects.count))")
            debugPrint("📁 Projects loaded:", projects.count)
            BCTiming.log("bootstrap: migrateStagesIfNeeded start")
            migrateStagesIfNeededAfterSeedUpdate()
            BCTiming.log("bootstrap: migrateStagesIfNeeded end")
        } catch {
            projects = []
            BCTiming.log("bootstrap: loadProjects error")
            debugPrint("❌ Load projects error:", error.localizedDescription)
        }

        BCTiming.log("bootstrap: loadExpenses start")
        do {
            expenses = try storage.loadExpenses()
            BCTiming.log("bootstrap: loadExpenses end (\(expenses.count))")
            debugPrint("💰 Expenses loaded:", expenses.count)
        } catch {
            expenses = []
            BCTiming.log("bootstrap: loadExpenses error")
            debugPrint("❌ Load expenses error:", error.localizedDescription)
        }

        BCTiming.log("bootstrap: loadTasks start")
        do {
            tasks = try storage.loadTasks()
            BCTiming.log("bootstrap: loadTasks end (\(tasks.count))")
            debugPrint("✅ Tasks loaded:", tasks.count)
        } catch {
            tasks = []
            BCTiming.log("bootstrap: loadTasks error")
            debugPrint("❌ Load tasks error:", error.localizedDescription)
        }

        TaskNotificationService.shared.rescheduleAllNotifications(tasks: tasks)
        BCTiming.log("bootstrap end")
    }

    private func applySubscriptionToRoleAndAccess() {
        // если подписка закончилась -> read-only
        if subscription.isReadOnlyExpired {
            isReadOnlyMode = true

            // роль "demo" тут не используем
            if userRole == .demo {
                // если по какой-то причине demo сохранён, а подписки нет — считаем как USER для UI.
                userRole = .user
            }

            persistUserRole()
            return
        }

        // Active подписка: редактирование разрешено
        isReadOnlyMode = false

        switch subscription.tier {
        case .pro:
            userRole = .pro
        case .user:
            userRole = .user
        case .none:
            userRole = .user
        }

        persistUserRole()
    }

    // MARK: - Tabs

    func setSelectedTab(_ tab: MainTab) {
        selectedTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: selectedTabKey)
    }

    private func loadSelectedTab() {
        if let raw = UserDefaults.standard.string(forKey: selectedTabKey),
           let tab = MainTab(rawValue: raw) {
            selectedTab = tab
        } else {
            selectedTab = .projects
        }
    }

    // MARK: - Subscription hook

    func refreshRoleForCurrentUser() async -> Bool {
        await subscription.refreshEntitlements()
        applySubscriptionToRoleAndAccess()
        return !subscription.isReadOnlyExpired
    }

    // MARK: - User role persistence

    private func loadUserRole() {
        if let raw = UserDefaults.standard.string(forKey: userRoleKey),
           let role = UserRole(rawValue: raw) {
            userRole = role
        } else {
            userRole = .demo
        }
    }

    private func persistUserRole() {
        UserDefaults.standard.set(userRole.rawValue, forKey: userRoleKey)
    }

    func setUserRole(_ role: UserRole) {
        userRole = role
        persistUserRole()
    }

    // MARK: - Guards

    private func ensureCanMutate() throws {
        // DEMO можно (всё в памяти)
        if isDemoMode { return }
        if isReadOnlyMode { throw AppStoreError.subscriptionExpiredReadOnly }
    }

    // MARK: - Stage migration

    private func migrateStagesIfNeededAfterSeedUpdate() {
        guard !seeds.isEmpty else { return }

        let seedTitles = seeds.map { $0.title }
        var changed = false

        for index in projects.indices {
            let projectStageTitles = projects[index].stages.map { $0.title }

            if projectStageTitles != seedTitles {
                var project = projects[index]
                project.stages = seeds.map { $0.materialize(using: project, loader: seedLoader) }
                projects[index] = project
                changed = true
            }
        }

        if changed {
            do {
                try persistProjects()
                debugPrint("✅ Stage migration applied for some projects")
            } catch {
                debugPrint("❌ Stage migration persist error:", error.localizedDescription)
            }
        }
    }

    // MARK: - Demo mode

    func enterDemoMode() {
        userRole = .demo
        isDemoMode = true
        isReadOnlyMode = false
        didPrefillDemoProgressInSession = false
        didPrefillDemoProgressStoresInSession = false
        didPrefillDemoExpensesInSession = false
        didPrefillDemoPhotosInSession = false
        didPrefillDemoTimelineInSession = false
        didPrefillDemoPlannedBudgetByStageInSession = false

        // ⚠️ DEMO — сессионный режим: НЕ сохраняем demo-роль в UserDefaults.
        // persistUserRole() — намеренно не вызываем.

        // Эфемерность: перед новым demo убрать артефакты прошлой demo-сессии (после kill и т.п.)
        if let oldString = UserDefaults.standard.string(forKey: lastDemoProjectIDKey),
           let oldID = UUID(uuidString: oldString) {
            removeDemoProgressArtifacts(for: oldID)
        }
        UserDefaults.standard.removeObject(forKey: lastDemoProjectIDKey)

        projects = []
        expenses = []
        tasks = []

        createDemoProjectIfNeeded()
        prefillDemoTimelineIfNeeded()
        prefillDemoPlannedBudgetByStageIfNeeded()
        prefillDemoProgressIfNeeded()
        prefillDemoProgressStoresIfNeeded()
        prefillDemoPhotosIfNeeded()
        prefillDemoExpensesIfNeeded()

        if let newID = projects.first?.id {
            UserDefaults.standard.set(newID.uuidString, forKey: lastDemoProjectIDKey)
        }
    }

    func exitDemoMode() {
        // Выход из demo: подчистить progress по текущим проектам в памяти и по сохранённому UUID.
        // (register/login выставляют isDemoMode = false до exitDemoMode — проверка isDemoMode здесь не надёжна.)
        for project in projects {
            removeDemoProgressArtifacts(for: project.id)
        }
        if let s = UserDefaults.standard.string(forKey: lastDemoProjectIDKey),
           let id = UUID(uuidString: s) {
            removeDemoProgressArtifacts(for: id)
        }
        UserDefaults.standard.removeObject(forKey: lastDemoProjectIDKey)

        isDemoMode = false

        // после демо мы НЕ даём автоматом доступ — роль определит подписка
        Task { [weak self] in
            guard let self else { return }
            await self.subscription.refreshEntitlements()
            self.applySubscriptionToRoleAndAccess()

            do { self.projects = try self.storage.loadProjects() } catch { self.projects = [] }
            do { self.expenses = try self.storage.loadExpenses() } catch { self.expenses = [] }
            do { self.tasks = try self.storage.loadTasks() } catch { self.tasks = [] }
        }
    }

    // MARK: - Registration

    func register(
        name: String,
        email: String?,
        secret: String?,
        role: UserRole = .user
    ) throws {
        try auth.register(name: name, email: email, secret: secret)
        isRegistered = true

        // роль и доступ потом уточним через StoreKit refresh
        userRole = role
        persistUserRole()

        isDemoMode = false
        isReadOnlyMode = false
        exitDemoMode()
    }

    func login(email: String, password: String) throws {
        isRegistered = true

        // роль потом уточним через StoreKit refresh
        if userRole == .demo {
            userRole = .user
        }

        persistUserRole()
        isDemoMode = false
        isReadOnlyMode = false

        exitDemoMode()
    }

    func logout() throws {
        try auth.clear()
        isRegistered = false
        userRole = .demo
        isDemoMode = false
        isReadOnlyMode = false
        UserDefaults.standard.removeObject(forKey: userRoleKey)

        projects = []
        expenses = []
        tasks = []
        try persistAll()
    }

    // MARK: - Account deletion (App Review 5.1.1(v))

    /// Полное удаление "аккаунта" в полностью локальном приложении:
    /// - удаляет email/флаг регистрации (через AuthService)
    /// - удаляет ВСЕ локальные файлы из Documents (проекты/чек-листы/бюджеты/вложения)
    /// - очищает состояние в памяти (projects/expenses/tasks), чтобы UI сразу стал пустым
    /// - возвращает на состояние "как после установки"
    ///
    /// Важно: метод НЕ пересоздаёт пустые файлы после wipe.
    func deleteAccountAndWipeLocalData() throws {
        // 1) очистить локальную "учётку"
        try auth.clear()
        isRegistered = false

        // 2) удалить ВСЕ файлы из Documents
        try storage.wipeAllUserData()

        // 3) сбросить локальные ключи UI/роли
        UserDefaults.standard.removeObject(forKey: userRoleKey)
        UserDefaults.standard.removeObject(forKey: selectedTabKey)

        // 4) сбросить доступ/режимы
        userRole = .demo
        isDemoMode = false
        isReadOnlyMode = false

        // 5) очистить состояние в памяти (чтобы проекты исчезли сразу, без перезапуска)
        projects = []
        expenses = []
        tasks = []

        // 6) вернуть вкладку по умолчанию
        selectedTab = .projects

        // 7) уведомления по задачам — пересчитать (станет пусто)
        TaskNotificationService.shared.rescheduleAllNotifications(tasks: [])
    }

    // MARK: - Expenses

    func addExpense(_ input: NewExpenseInput) throws {
        try ensureCanMutate()
        guard let amount = input.amount else { return }

        let expense = ExpenseItem(
            projectID: input.projectID,
            category: input.category,
            subCategory: input.subCategory,
            stageCategory: input.stageCategory,
            stageItemID: input.stageItemID,
            amount: amount,
            date: input.date,
            note: input.note
        )

        expenses.insert(expense, at: 0)
        try persistExpenses()
    }

    func deleteExpense(_ expense: ExpenseItem) throws {
        try ensureCanMutate()
        expenses.removeAll { $0.id == expense.id }
        try persistExpenses()
    }

    func updateExpense(_ expense: ExpenseItem, with input: NewExpenseInput) throws {
        try ensureCanMutate()
        guard let amount = input.amount else { return }
        guard let idx = expenses.firstIndex(where: { $0.id == expense.id }) else { return }

        let updated = ExpenseItem(
            id: expense.id,
            projectID: input.projectID,
            category: input.category,
            subCategory: input.subCategory,
            stageCategory: input.stageCategory,
            stageItemID: input.stageItemID,
            amount: amount,
            date: input.date,
            note: input.note
        )

        expenses[idx] = updated
        try persistExpenses()
    }

    func expenses(for projectID: UUID) -> [ExpenseItem] {
        expenses.filter { $0.projectID == projectID }
    }

    func totalAmount(for projectID: UUID) -> Decimal {
        expenses(for: projectID).reduce(0) { $0 + $1.amount }
    }

    func totalsByCategory(for projectID: UUID) -> [ExpenseCategory: Decimal] {
        var result: [ExpenseCategory: Decimal] = [:]
        for c in ExpenseCategory.allCases { result[c] = 0 }
        expenses(for: projectID).forEach { exp in
            result[exp.category, default: 0] += exp.amount
        }
        return result
    }

    // MARK: - Budget analytics

    func totalsByStageCategory(for projectID: UUID) -> [GlobalStageCategory: Decimal] {
        var result: [GlobalStageCategory: Decimal] = [:]
        for stage in GlobalStageCategory.allCases { result[stage] = 0 }

        for exp in expenses(for: projectID) {
            let stage: GlobalStageCategory
            if let s = exp.stageCategory {
                stage = s
            } else {
                switch exp.category {
                case .geologyAndPrep: stage = .geologyAndPrep
                case .foundation:     stage = .foundation
                case .walls:          stage = .walls
                case .slabs:          stage = .slabs
                case .roof:           stage = .roof
                case .engineering:    stage = .engineering
                case .windows:        stage = .windows
                case .doors:          stage = .doors
                case .finishing:      stage = .finishing
                case .landscaping:    stage = .landscaping
                }
            }
            result[stage, default: 0] += exp.amount
        }

        return result
    }

    func totalsBySubCategory(for projectID: UUID) -> [ExpenseSubCategory: Decimal] {
        var result: [ExpenseSubCategory: Decimal] = [:]
        for sub in ExpenseSubCategory.allCases { result[sub] = 0 }
        for exp in expenses(for: projectID) {
            result[exp.subCategory, default: 0] += exp.amount
        }
        return result
    }

    func filteredExpenses(
        for projectID: UUID,
        stageCategory: GlobalStageCategory?,
        subCategory: ExpenseSubCategory?,
        dateFrom: Date?,
        dateTo: Date?
    ) -> [ExpenseItem] {
        var result = expenses(for: projectID)

        if let stageCategory {
            result = result.filter { exp in
                if let s = exp.stageCategory { return s == stageCategory }
                let catStage: GlobalStageCategory
                switch exp.category {
                case .geologyAndPrep: catStage = .geologyAndPrep
                case .foundation:     catStage = .foundation
                case .walls:          catStage = .walls
                case .slabs:          catStage = .slabs
                case .roof:           catStage = .roof
                case .engineering:    catStage = .engineering
                case .windows:        catStage = .windows
                case .doors:          catStage = .doors
                case .finishing:      catStage = .finishing
                case .landscaping:    catStage = .landscaping
                }
                return catStage == stageCategory
            }
        }

        if let subCategory { result = result.filter { $0.subCategory == subCategory } }
        if let from = dateFrom { result = result.filter { $0.date >= from } }
        if let to = dateTo { result = result.filter { $0.date <= to } }

        return result
    }

    // MARK: - Plan/Fact

    func plannedBudget(for projectID: UUID, stage: GlobalStageCategory) -> Decimal {
        guard let project = project(by: projectID) else { return 0 }
        return project.plannedBudget(for: stage)
    }

    func plannedBudgetTotalsByStage(for projectID: UUID) -> [GlobalStageCategory: Decimal] {
        guard let project = project(by: projectID) else {
            var empty: [GlobalStageCategory: Decimal] = [:]
            GlobalStageCategory.allCases.forEach { empty[$0] = 0 }
            return empty
        }

        var result: [GlobalStageCategory: Decimal] = [:]
        for stage in GlobalStageCategory.allCases {
            result[stage] = project.plannedBudget(for: stage)
        }
        return result
    }

    func factAmount(for projectID: UUID, stage: GlobalStageCategory) -> Decimal {
        let facts = totalsByStageCategory(for: projectID)
        return facts[stage] ?? 0
    }

    func planFactForStage(projectID: UUID, stage: GlobalStageCategory) -> (plan: Decimal, fact: Decimal, diff: Decimal) {
        let plan = plannedBudget(for: projectID, stage: stage)
        let fact = factAmount(for: projectID, stage: stage)
        let diff = fact - plan
        return (plan, fact, diff)
    }

    func planFactByStage(for projectID: UUID) -> [(stage: GlobalStageCategory, plan: Decimal, fact: Decimal, diff: Decimal)] {
        GlobalStageCategory.allCases.map { stage in
            let plan = plannedBudget(for: projectID, stage: stage)
            let fact = factAmount(for: projectID, stage: stage)
            let diff = fact - plan
            return (stage, plan, fact, diff)
        }
    }

    // MARK: - Projects

    func createProject(_ input: NewProjectInput) throws {
        try ensureCanMutate()

        if userRole == .user, !canCreateNewProject {
            throw AppStoreError.projectLimitReached
        }

        if seeds.isEmpty {
            do { seeds = try markdown.loadSeedStages() } catch { seeds = [] }
        }

        var project = Project(
            id: UUID(),
            name: input.name,
            address: input.address,
            dateStart: input.dateStart,
            dateEnd: input.dateEnd,
            budget: input.budget,
            manager: input.manager,
            coverImagePath: nil,
            description: input.description,
            foundationType: input.foundationType,
            wallType: input.wallType,
            slabType: input.slabType,
            roofShapeType: input.roofShapeType,
            roofCoverType: input.roofCoverType,
            cardColor: input.cardColor,
            lastUpdated: input.lastUpdated ?? Date(),
            stages: []
        )

        project.stages = seeds.map { $0.materialize(using: project, loader: seedLoader) }

        projects.insert(project, at: 0)

        // ✅ DEMO: проект создаётся, но ничего не сохраняем
        if isDemoMode {
            return
        }

        // ✅ USER/PRO: сохраняем как обычно
        try persistProjects()
    }

    func updateProjectMeta(_ id: UUID, change: (inout Project) -> Void) throws {
        try ensureCanMutate()
        guard let idx = projects.firstIndex(where: { $0.id == id }) else { return }

        change(&projects[idx])
        projects[idx].stages = seeds.map { $0.materialize(using: projects[idx], loader: seedLoader) }

        try persistProjects()
    }

    func updateProject(_ project: Project) throws {
        try ensureCanMutate()
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[idx] = project
        try persistProjects()
    }

    func deleteProject(_ project: Project) throws {
        try ensureCanMutate()
        guard let existing = projects.first(where: { $0.id == project.id }) else { return }

        var allPaths: [String] = []
        allPaths.append(contentsOf: existing.photoPaths)
        allPaths.append(contentsOf: existing.documentPaths)
        if let pdfPath = existing.projectPDFPath { allPaths.append(pdfPath) }

        for stage in existing.stages {
            for item in stage.items {
                allPaths.append(contentsOf: item.photoPaths)
                allPaths.append(contentsOf: item.pdfPaths)
            }
        }

        for path in allPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { debugPrint("❌ File remove error for \(url.lastPathComponent):", error.localizedDescription) }
            }
        }

        CoverImageStore.shared.deleteCover(for: existing.id)

        projects.removeAll { $0.id == project.id }
        expenses.removeAll { $0.projectID == project.id }

        try persistAll()
    }

    func project(by id: UUID) -> Project? { projects.first { $0.id == id } }
    func stage(projectID: UUID, stageID: UUID) -> Stage? { project(by: projectID)?.stages.first { $0.id == stageID } }

    // MARK: - Stage updates

    func updateStagePlannedDates(projectID: UUID, stageID: UUID, plannedStart: Date?, plannedEnd: Date?) throws {
        try ensureCanMutate()
        try mutateStage(projectID: projectID, stageID: stageID) { stage in
            stage.plannedStart = plannedStart
            stage.plannedEnd = plannedEnd
        }
    }

    func updateStageActualDates(projectID: UUID, stageID: UUID, actualStart: Date?, actualEnd: Date?) throws {
        try ensureCanMutate()
        try mutateStage(projectID: projectID, stageID: stageID) { stage in
            stage.actualStart = actualStart
            stage.actualEnd = actualEnd
        }
    }

    func updateStageDelay(projectID: UUID, stageID: UUID, reason: DelayReason?, comment: String?) throws {
        try ensureCanMutate()
        try mutateStage(projectID: projectID, stageID: stageID) { stage in
            stage.delayReason = reason
            stage.delayComment = comment
        }
    }

    // MARK: - StageItem updates

    func setStatus(projectID: UUID, stageID: UUID, itemID: UUID, status: ItemStatus) throws {
        try ensureCanMutate()
        try mutate(projectID: projectID, stageID: stageID, itemID: itemID) { $0.status = status }
    }

    func setSeverity(projectID: UUID, stageID: UUID, itemID: UUID, severity: Severity) throws {
        try ensureCanMutate()
        try mutate(projectID: projectID, stageID: stageID, itemID: itemID) { $0.severity = severity }
    }

    func setNote(projectID: UUID, stageID: UUID, itemID: UUID, note: String?) throws {
        try ensureCanMutate()
        try mutate(projectID: projectID, stageID: stageID, itemID: itemID) { $0.note = note }
    }

    func addPhoto(projectID: UUID, stageID: UUID, itemID: UUID, image: UIImage) throws {
        try ensureCanMutate()
        let path = try media.save(image: image)
        try mutate(projectID: projectID, stageID: stageID, itemID: itemID) { $0.photoPaths.append(path) }
    }

    func addPDF(projectID: UUID, stageID: UUID, itemID: UUID, data: Data, suggestedName: String?) throws {
        try ensureCanMutate()
        let path = try media.save(pdfData: data, name: suggestedName)
        try mutate(projectID: projectID, stageID: stageID, itemID: itemID) { $0.pdfPaths.append(path) }
    }

    // MARK: - Helper mutators

    private func mutateStage(projectID: UUID, stageID: UUID, _ change: (inout Stage) -> Void) throws {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let s = projects[p].stages.firstIndex(where: { $0.id == stageID }) else { return }

        change(&projects[p].stages[s])
        try persistProjects()

        self.objectWillChange.send()
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    private func mutate(projectID: UUID, stageID: UUID, itemID: UUID, _ change: (inout StageItem) -> Void) throws {
        guard let p = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let s = projects[p].stages.firstIndex(where: { $0.id == stageID }) else { return }
        guard let i = projects[p].stages[s].items.firstIndex(where: { $0.id == itemID }) else { return }

        change(&projects[p].stages[s].items[i])
        try persistProjects()

        self.objectWillChange.send()
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    // MARK: - Contacts

    func contacts(for projectID: UUID) -> [ProjectContact] {
        guard let project = project(by: projectID) else { return [] }
        return project.contacts
    }

    func addContact(_ contact: ProjectContact, to projectID: UUID) throws {
        try ensureCanMutate()
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].contacts.insert(contact, at: 0)
        try persistProjects()
    }

    func updateContact(_ contact: ProjectContact, in projectID: UUID) throws {
        try ensureCanMutate()
        guard let pIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        guard let cIndex = projects[pIndex].contacts.firstIndex(where: { $0.id == contact.id }) else { return }
        projects[pIndex].contacts[cIndex] = contact
        try persistProjects()
    }

    func deleteContact(_ contact: ProjectContact, from projectID: UUID) throws {
        try ensureCanMutate()
        guard let pIndex = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[pIndex].contacts.removeAll { $0.id == contact.id }
        try persistProjects()
    }

    // MARK: - Tasks

    private func addTaskInternal(title: String, details: String?, projectID: UUID?, dueDate: Date?) throws {
        try ensureCanMutate()

        let task = TaskItem(
            id: UUID(),
            title: title,
            details: details,
            projectID: projectID,
            dueDate: dueDate,
            isCompleted: false
        )

        tasks.insert(task, at: 0)
        try persistTasks()

        TaskNotificationService.shared.rescheduleNotification(for: task)
    }

    func addTask(title: String, details: String?, projectID: UUID?, dueDate: Date?) throws {
        try addTaskInternal(title: title, details: details, projectID: projectID, dueDate: dueDate)
    }

    func addTask(title: String, details: String?, dueDate: Date?, projectID: UUID?) throws {
        try addTaskInternal(title: title, details: details, projectID: projectID, dueDate: dueDate)
    }

    func addTask(_ input: NewTaskInput) throws {
        try addTaskInternal(title: input.title, details: input.details, projectID: input.projectID, dueDate: input.dueDate)
    }

    private func updateTaskInternal(
        _ task: TaskItem,
        title: String,
        details: String?,
        projectID: UUID?,
        dueDate: Date?,
        isCompleted: Bool
    ) throws {
        try ensureCanMutate()
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        var updated = tasks[index]
        updated.title = title
        updated.details = details
        updated.projectID = projectID
        updated.dueDate = dueDate
        updated.isCompleted = isCompleted

        tasks[index] = updated
        try persistTasks()

        TaskNotificationService.shared.rescheduleNotification(for: updated)
    }

    func updateTask(_ task: TaskItem, title: String, details: String?, projectID: UUID?, dueDate: Date?, isCompleted: Bool) throws {
        try updateTaskInternal(task, title: title, details: details, projectID: projectID, dueDate: dueDate, isCompleted: isCompleted)
    }

    func updateTask(_ task: TaskItem, title: String, details: String?, dueDate: Date?, projectID: UUID?, isCompleted: Bool) throws {
        try updateTaskInternal(task, title: title, details: details, projectID: projectID, dueDate: dueDate, isCompleted: isCompleted)
    }

    func updateTask(_ task: TaskItem, with input: NewTaskInput) throws {
        try updateTaskInternal(task, title: input.title, details: input.details, projectID: input.projectID, dueDate: input.dueDate, isCompleted: task.isCompleted)
    }

    func toggleTaskCompletion(_ task: TaskItem) throws {
        try ensureCanMutate()
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }

        var updated = task
        updated.isCompleted.toggle()

        tasks[index] = updated
        try persistTasks()

        if updated.isCompleted {
            TaskNotificationService.shared.cancelNotification(for: updated.id)
        } else {
            TaskNotificationService.shared.rescheduleNotification(for: updated)
        }
    }

    func deleteTask(_ task: TaskItem) throws {
        try ensureCanMutate()
        tasks.removeAll { $0.id == task.id }
        try persistTasks()

        TaskNotificationService.shared.cancelNotification(for: task.id)
    }

    func tasks(for projectID: UUID) -> [TaskItem] {
        tasks.filter { $0.projectID == projectID }
    }

    // MARK: - Persistence

    private func persistProjects() throws {
        guard !isDemoMode else { return }
        try storage.saveProjects(projects)
    }

    private func persistExpenses() throws {
        guard !isDemoMode else { return }
        try storage.saveExpenses(expenses)
    }

    private func persistTasks() throws {
        guard !isDemoMode else { return }
        try storage.saveTasks(tasks)
    }

    private func persistAll() throws {
        try persistProjects()
        try persistExpenses()
        try persistTasks()
    }

    // MARK: - Demo progress cleanup (эфемерность)

    /// Удаляет только артефакты progress для конкретного projectID (не трогает остальные проекты).
    private func removeDemoProgressArtifacts(for projectID: UUID) {
        let fm = FileManager.default
        guard let root = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let folders = ["BC_Geology", "BC_Foundation", "BC_Walls", "BC_Slab"]
        for folder in folders {
            let url = root.appendingPathComponent(folder, isDirectory: true)
                .appendingPathComponent("\(projectID.uuidString).json", isDirectory: false)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }

        UserDefaults.standard.removeObject(forKey: "roofcover_progress_\(projectID.uuidString)")
        UserDefaults.standard.removeObject(forKey: "doors_progress_\(projectID.uuidString)")
    }

    // MARK: - Demo project bootstrap

    /// Создаёт базовый demo-проект только для текущей DEMO-сессии.
    /// Использует штатный путь createProject(...) для полной совместимости модели.
    private func createDemoProjectIfNeeded() {
        guard isDemoMode else { return }
        guard projects.isEmpty else { return }

        let input = NewProjectInput(
            name: "Дом 160 м² (пример)",
            address: "Московская область, Наро-Фоминский г.о., д. Хлопово",
            dateStart: nil,
            dateEnd: nil,
            budget: Decimal(12_000_000),
            manager: "Прораб Олег",
            description: "Демонстрационный проект загородного дома",
            foundationType: .strip,
            wallType: .aac,
            slabType: .mono,
            roofShapeType: nil,
            roofCoverType: .metal,
            cardColor: "softGray",
            lastUpdated: Date()
        )

        do {
            try createProject(input)
            applyDemoProjectDatesIfNeeded()
        } catch {
            debugPrint("❌ Demo project create error:", error.localizedDescription)
        }
    }

    /// DEMO-only: заполняет даты demo-проекта, если они отсутствуют.
    private func applyDemoProjectDatesIfNeeded() {
        guard isDemoMode else { return }
        guard !projects.isEmpty else { return }

        let calendar = Calendar.current
        let demoStartDate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? Date()
        let demoEndDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30)) ?? Date()

        guard let idx = projects.indices.first else { return }
        var project = projects[idx]

        if project.dateStart == nil {
            project.dateStart = demoStartDate
        }
        if project.dateEnd == nil {
            project.dateEnd = demoEndDate
        }

        projects[idx] = project
    }

    /// DEMO-only: предзаполняет сроки этапов demo-проекта для правдоподобного таймлайна.
    private func prefillDemoTimelineIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoTimelineInSession else { return }
        guard let idx = projects.indices.first else { return }

        func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date? {
            Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
        }

        var project = projects[idx]
        guard !project.stages.isEmpty else { return }

        if project.stages.indices.contains(0) {
            project.stages[0].plannedStart = makeDate(2026, 2, 1)
            project.stages[0].plannedEnd = makeDate(2026, 2, 28)
            project.stages[0].actualStart = makeDate(2026, 2, 1)
            project.stages[0].actualEnd = makeDate(2026, 2, 28)
            project.stages[0].delayReason = nil
            project.stages[0].delayComment = nil
        }

        if project.stages.indices.contains(1) {
            project.stages[1].plannedStart = makeDate(2026, 3, 1)
            project.stages[1].plannedEnd = makeDate(2026, 4, 10)
            project.stages[1].actualStart = makeDate(2026, 3, 1)
            project.stages[1].actualEnd = makeDate(2026, 4, 18)
            project.stages[1].delayReason = .weather
            project.stages[1].delayComment = "Погодные условия"
        }

        if project.stages.indices.contains(2) {
            project.stages[2].plannedStart = makeDate(2026, 4, 20)
            project.stages[2].plannedEnd = makeDate(2026, 5, 25)
            project.stages[2].actualStart = nil
            project.stages[2].actualEnd = nil
            project.stages[2].delayReason = nil
            project.stages[2].delayComment = nil
        }

        if project.stages.indices.contains(3) {
            project.stages[3].plannedStart = makeDate(2026, 5, 26)
            project.stages[3].plannedEnd = makeDate(2026, 6, 20)
            project.stages[3].actualStart = nil
            project.stages[3].actualEnd = nil
            project.stages[3].delayReason = nil
            project.stages[3].delayComment = nil
        }

        if project.stages.indices.contains(4) {
            project.stages[4].plannedStart = makeDate(2026, 6, 21)
            project.stages[4].plannedEnd = makeDate(2026, 7, 20)
            project.stages[4].actualStart = nil
            project.stages[4].actualEnd = nil
            project.stages[4].delayReason = nil
            project.stages[4].delayComment = nil
        }

        for i in 5..<project.stages.count {
            project.stages[i].actualStart = nil
            project.stages[i].actualEnd = nil
            project.stages[i].delayReason = nil
            project.stages[i].delayComment = nil
        }

        projects[idx] = project
        didPrefillDemoTimelineInSession = true
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    /// DEMO-only: плановый бюджет по глобальным этапам (для «План / факт по этапам»).
    private func prefillDemoPlannedBudgetByStageIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoPlannedBudgetByStageInSession else { return }
        guard let idx = projects.indices.first else { return }

        didPrefillDemoPlannedBudgetByStageInSession = true

        var project = projects[idx]
        project.plannedBudgetByStage = [
            .geologyAndPrep: Decimal(100_000),
            .foundation: Decimal(400_000),
            .walls: Decimal(2_700_000),
            .slabs: Decimal(300_000),
            .roof: Decimal(1_300_000),
            .engineering: Decimal(500_000),
            .windows: Decimal(400_000),
            .doors: Decimal(300_000),
            .finishing: Decimal(4_800_000),
            .landscaping: Decimal(1_200_000)
        ]
        projects[idx] = project
    }

    /// DEMO-only: добавляет набор расходов в demo-проект.
    /// Использует штатный addExpense(...) и не пишет в постоянное хранилище в DEMO.
    private func prefillDemoExpensesIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoExpensesInSession else { return }
        guard let projectID = projects.first?.id else { return }

        didPrefillDemoExpensesInSession = true

        struct DemoExpenseSeed {
            let amount: Int
            let note: String
            let category: ExpenseCategory
            let subCategory: ExpenseSubCategory
            let stageCategory: GlobalStageCategory
        }

        let seeds: [DemoExpenseSeed] = [
            // Геология
            .init(amount: 80_000, note: "Отчёт геологии", category: .geologyAndPrep, subCategory: .labor, stageCategory: .geologyAndPrep),
            .init(amount: 12_000, note: "Выезд инженера", category: .geologyAndPrep, subCategory: .labor, stageCategory: .geologyAndPrep),
            .init(amount: 35_000, note: "Бурение скважин", category: .geologyAndPrep, subCategory: .rent, stageCategory: .geologyAndPrep),

            // Подготовка участка
            .init(amount: 45_000, note: "Расчистка участка", category: .geologyAndPrep, subCategory: .labor, stageCategory: .geologyAndPrep),
            .init(amount: 40_000, note: "Аренда экскаватора", category: .geologyAndPrep, subCategory: .rent, stageCategory: .geologyAndPrep),
            .init(amount: 55_000, note: "Вывоз грунта", category: .geologyAndPrep, subCategory: .rent, stageCategory: .geologyAndPrep),
            .init(amount: 18_000, note: "Геодезическая разбивка", category: .geologyAndPrep, subCategory: .labor, stageCategory: .geologyAndPrep),

            // Фундамент
            .init(amount: 280_000, note: "Бетон", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 95_000, note: "Арматура", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 36_000, note: "Песок", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 48_000, note: "Щебень", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 60_000, note: "Опалубка", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 22_000, note: "Гидроизоляция", category: .foundation, subCategory: .materials, stageCategory: .foundation),
            .init(amount: 180_000, note: "Работы по фундаменту", category: .foundation, subCategory: .labor, stageCategory: .foundation),
            .init(amount: 55_000, note: "Вязка арматуры", category: .foundation, subCategory: .labor, stageCategory: .foundation),
            .init(amount: 38_000, note: "Аренда бетононасоса", category: .foundation, subCategory: .rent, stageCategory: .foundation),
            .init(amount: 12_000, note: "Аренда виброплиты", category: .foundation, subCategory: .rent, stageCategory: .foundation),

            // Стены
            .init(amount: 410_000, note: "Газоблок", category: .walls, subCategory: .materials, stageCategory: .walls),
            .init(amount: 38_000, note: "Клей для газоблока", category: .walls, subCategory: .materials, stageCategory: .walls),
            .init(amount: 54_000, note: "Армопояс", category: .walls, subCategory: .materials, stageCategory: .walls),
            .init(amount: 32_000, note: "Перемычки", category: .walls, subCategory: .materials, stageCategory: .walls),
            .init(amount: 14_000, note: "Сетка кладочная", category: .walls, subCategory: .materials, stageCategory: .walls),
            .init(amount: 220_000, note: "Кладочные работы", category: .walls, subCategory: .labor, stageCategory: .walls),
            .init(amount: 28_000, note: "Монтаж перемычек", category: .walls, subCategory: .labor, stageCategory: .walls),
            .init(amount: 35_000, note: "Доставка блока", category: .walls, subCategory: .rent, stageCategory: .walls),

            // Перекрытия
            .init(amount: 160_000, note: "Бетон на перекрытия", category: .slabs, subCategory: .materials, stageCategory: .slabs),
            .init(amount: 75_000, note: "Арматура на перекрытия", category: .slabs, subCategory: .materials, stageCategory: .slabs),
            .init(amount: 52_000, note: "Опалубка перекрытия", category: .slabs, subCategory: .materials, stageCategory: .slabs),
            .init(amount: 140_000, note: "Монтаж перекрытия", category: .slabs, subCategory: .labor, stageCategory: .slabs),
            .init(amount: 36_000, note: "Подготовка армирования", category: .slabs, subCategory: .labor, stageCategory: .slabs),
            .init(amount: 40_000, note: "Аренда бетононасоса", category: .slabs, subCategory: .rent, stageCategory: .slabs),

            // Крыша
            .init(amount: 95_000, note: "Стропильная доска", category: .roof, subCategory: .materials, stageCategory: .roof),
            .init(amount: 28_000, note: "Мембрана", category: .roof, subCategory: .materials, stageCategory: .roof),
            .init(amount: 110_000, note: "Утеплитель", category: .roof, subCategory: .materials, stageCategory: .roof),
            .init(amount: 160_000, note: "Монтаж стропил", category: .roof, subCategory: .labor, stageCategory: .roof),
            .init(amount: 145_000, note: "Монтаж кровельного покрытия", category: .roof, subCategory: .labor, stageCategory: .roof),

            // Окна
            .init(amount: 320_000, note: "Окна ПВХ", category: .windows, subCategory: .materials, stageCategory: .windows),
            .init(amount: 48_000, note: "Монтаж окон", category: .windows, subCategory: .labor, stageCategory: .windows),

            // Двери
            .init(amount: 45_000, note: "Входная дверь", category: .doors, subCategory: .materials, stageCategory: .doors),
            .init(amount: 8_000, note: "Монтаж двери", category: .doors, subCategory: .labor, stageCategory: .doors),

            // Инженерия
            .init(amount: 120_000, note: "Электрика материалы", category: .engineering, subCategory: .materials, stageCategory: .engineering),
            .init(amount: 68_000, note: "Кабель", category: .engineering, subCategory: .materials, stageCategory: .engineering),
            .init(amount: 74_000, note: "Трубы водоснабжения", category: .engineering, subCategory: .materials, stageCategory: .engineering),
            .init(amount: 85_000, note: "Электромонтаж", category: .engineering, subCategory: .labor, stageCategory: .engineering),
            .init(amount: 74_000, note: "Монтаж водоснабжения", category: .engineering, subCategory: .labor, stageCategory: .engineering),
            .init(amount: 58_000, note: "Монтаж канализации", category: .engineering, subCategory: .labor, stageCategory: .engineering),

            // Отделка
            .init(amount: 95_000, note: "Штукатурка материалы", category: .finishing, subCategory: .materials, stageCategory: .finishing),
            .init(amount: 52_000, note: "Шпаклёвка", category: .finishing, subCategory: .materials, stageCategory: .finishing),
            .init(amount: 130_000, note: "Штукатурные работы", category: .finishing, subCategory: .labor, stageCategory: .finishing),
            .init(amount: 110_000, note: "Стяжка пола", category: .finishing, subCategory: .labor, stageCategory: .finishing),

            // Благоустройство
            .init(amount: 55_000, note: "Планировка участка", category: .landscaping, subCategory: .labor, stageCategory: .landscaping),
            .init(amount: 22_000, note: "Песок на дорожки", category: .landscaping, subCategory: .materials, stageCategory: .landscaping),
            .init(amount: 18_000, note: "Щебень на дорожки", category: .landscaping, subCategory: .materials, stageCategory: .landscaping),
        ]

        for seed in seeds {
            let input = NewExpenseInput(
                projectID: projectID,
                category: seed.category,
                subCategory: seed.subCategory,
                stageCategory: seed.stageCategory,
                stageItemID: nil,
                amount: Decimal(seed.amount),
                date: Date(),
                note: seed.note
            )
            do {
                try addExpense(input)
            } catch {
                debugPrint("❌ Demo expense create error (\(seed.note)):", error.localizedDescription)
            }
        }
    }

    /// Частично заполняет прогресс demo-проекта только в памяти:
    /// - Геология: завершена
    /// - Фундамент: завершён
    /// - Стены: частично
    /// - Перекрытия: начат (issue)
    /// - Остальные: не начаты
    private func prefillDemoProgressIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoProgressInSession else { return }
        guard let idx = projects.firstIndex(where: { !$0.stages.isEmpty }) else { return }

        didPrefillDemoProgressInSession = true

        var project = projects[idx]

        for sIdx in project.stages.indices {
            let title = project.stages[sIdx].title.lowercased()

            if title.contains("геология") {
                setStageItemsStatus(&project.stages[sIdx], mode: .allDone)
            } else if title.contains("фундамент") {
                setStageItemsStatus(&project.stages[sIdx], mode: .allDone)
            } else if title.contains("стен") {
                setStageItemsStatus(&project.stages[sIdx], mode: .partiallyDone)
            } else if title.contains("перекрыт") {
                setStageItemsStatus(&project.stages[sIdx], mode: .started)
            } else {
                setStageItemsStatus(&project.stages[sIdx], mode: .notStarted)
            }
        }

        projects[idx] = project
    }

    private enum DemoStageFillMode {
        case allDone
        case partiallyDone
        case started
        case notStarted
    }

    private func setStageItemsStatus(_ stage: inout Stage, mode: DemoStageFillMode) {
        guard !stage.items.isEmpty else { return }

        switch mode {
        case .allDone:
            for i in stage.items.indices {
                stage.items[i].status = .ok
            }
        case .partiallyDone:
            let completedCount = max(1, Int(Double(stage.items.count) * 0.6))
            for i in stage.items.indices {
                stage.items[i].status = i < completedCount ? .ok : .na
            }
        case .started:
            // "Начат" без завершения: помечаем первый пункт как issue
            // (progress > 0 не гарантируется и не требуется на этом шаге).
            for i in stage.items.indices {
                stage.items[i].status = .na
            }
            stage.items[0].status = .issue
        case .notStarted:
            for i in stage.items.indices {
                stage.items[i].status = .na
            }
        }
    }

    /// Предзаполняет ProgressStore для ключевых этапов (геология, фундамент, стены, перекрытия),
    /// чтобы карточка проекта, дашборд и экран фундамента видели ненулевой прогресс.
    private func prefillDemoProgressStoresIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoProgressStoresInSession else { return }
        guard let project = projects.first else { return }

        didPrefillDemoProgressStoresInSession = true

        let pid = project.id

        var geology = GeologyStagesProvider.loadStages()
        applyAllOK(to: &geology)
        if !geology.isEmpty {
            GeologyProgressStore.save(projectID: pid, stages: geology)
        }

        let foundationPackName = demoFoundationPackID(project.foundationType)
        var foundation = FoundationStagesProvider.loadStages(named: foundationPackName)
        applyAllOK(to: &foundation)
        if !foundation.isEmpty {
            FoundationProgressStore.save(projectID: pid, stages: foundation)
        }

        let wallsTypeID = demoWallsPackTypeID(project)
        var walls = WallsStagesProvider.loadStages(for: wallsTypeID)
        applyPartialOK(to: &walls, fraction: 0.55)
        if !walls.isEmpty {
            WallsProgressStore.save(projectID: pid, stages: walls)
        }

        let slabTypeID = demoSlabPackTypeID(project.slabType)
        var slabs = SlabStagesProvider.loadStages(for: slabTypeID)
        applyPartialOK(to: &slabs, fraction: 0.32)
        if !slabs.isEmpty {
            SlabProgressStore.save(projectID: pid, stages: slabs)
        }

        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    /// DEMO-only: добавляет по одному демо-фото в
    /// фундамент / стены / перекрытия (первый этап -> первый пункт).
    private func prefillDemoPhotosIfNeeded() {
        guard isDemoMode else { return }
        guard !didPrefillDemoPhotosInSession else { return }
        guard let projectID = projects.first?.id else { return }

        var didSaveAtLeastOnePhoto = false

        if let image = UIImage(named: "foundation_demo_1"),
           var stages = FoundationProgressStore.load(projectID: projectID),
           !stages.isEmpty,
           !stages[0].items.isEmpty {
            do {
                let savedPath = try media.save(image: image)
                if !stages[0].items[0].photoPaths.contains(savedPath) {
                    stages[0].items[0].photoPaths.append(savedPath)
                }
                FoundationProgressStore.save(projectID: projectID, stages: stages)
                didSaveAtLeastOnePhoto = true
            } catch {
                debugPrint("❌ Demo foundation photo save error:", error.localizedDescription)
            }
        }

        if let image = UIImage(named: "walls_demo_1"),
           var stages = WallsProgressStore.load(projectID: projectID),
           !stages.isEmpty,
           !stages[0].items.isEmpty {
            do {
                let savedPath = try media.save(image: image)
                if !stages[0].items[0].photoPaths.contains(savedPath) {
                    stages[0].items[0].photoPaths.append(savedPath)
                }
                WallsProgressStore.save(projectID: projectID, stages: stages)
                didSaveAtLeastOnePhoto = true
            } catch {
                debugPrint("❌ Demo walls photo save error:", error.localizedDescription)
            }
        }

        if let image = UIImage(named: "slab_demo_1"),
           var stages = SlabProgressStore.load(projectID: projectID),
           !stages.isEmpty,
           !stages[0].items.isEmpty {
            do {
                let savedPath = try media.save(image: image)
                if !stages[0].items[0].photoPaths.contains(savedPath) {
                    stages[0].items[0].photoPaths.append(savedPath)
                }
                SlabProgressStore.save(projectID: projectID, stages: stages)
                didSaveAtLeastOnePhoto = true
            } catch {
                debugPrint("❌ Demo slab photo save error:", error.localizedDescription)
            }
        }

        if didSaveAtLeastOnePhoto {
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
            didPrefillDemoPhotosInSession = true
        }
    }

    private func demoFoundationPackID(_ type: FoundationType?) -> String {
        switch type {
        case .some(.strip): return "foundation_strip"
        case .some(.slab): return "foundation_slab"
        case .some(.pile): return "foundation_pile"
        case .some(.tise): return "foundation_tise"
        case .some(.combo): return "foundation_combo"
        case .none: return "foundation_slab"
        }
    }

    private func demoWallsPackTypeID(_ project: Project) -> String {
        switch project.wallType {
        case .some(.aac): return "aac"
        case .some(.keramBlock): return "keramblock"
        case .some(.brick): return "brick"
        case .some(.woodcrete): return "woodcrete"
        case .some(.monolithic): return "monolithic"
        case .some(.keramzit): return "keramzit"
        case .some(.combo): return "combo"
        case .none: return "aac"
        }
    }

    private func demoSlabPackTypeID(_ type: SlabType?) -> String {
        switch type {
        case .some(.mono): return "monolithic"
        case .some(.pb): return "pb"
        case .some(.pc): return "pc"
        case .some(.steel): return "steel"
        case .some(.wood): return "wood"
        case .none: return "monolithic"
        }
    }

    private func applyAllOK(to stages: inout [Stage]) {
        for si in stages.indices {
            for ii in stages[si].items.indices {
                stages[si].items[ii].status = .ok
            }
        }
    }

    /// Доля `ok` внутри каждого подэтапа (минимум 1 пункт, если он есть).
    private func applyPartialOK(to stages: inout [Stage], fraction: Double) {
        let f = min(1, max(0, fraction))
        for si in stages.indices {
            let c = stages[si].items.count
            guard c > 0 else { continue }
            let done = min(c, max(1, Int((Double(c) * f).rounded(.down))))
            for ii in stages[si].items.indices {
                stages[si].items[ii].status = ii < done ? .ok : .na
            }
        }
    }

    // MARK: - Progress

    func stageProgress(_ stage: Stage) -> Double {
        guard !stage.items.isEmpty else { return 0 }
        let ok = stage.items.filter { $0.status == .ok }.count
        return Double(ok) / Double(stage.items.count)
    }

    func projectProgress(_ project: Project) -> Double {
        guard !project.stages.isEmpty else { return 0 }
        let sum = project.stages.map(stageProgress).reduce(0, +)
        return sum / Double(project.stages.count)
    }

    // MARK: - Export helpers

    func exportExpensesCSV(for projectID: UUID) -> URL? {
        let rows = expenses(for: projectID).sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return nil }

        let projectName = project(by: projectID)?.name ?? "Project"
        let sanitizedName = projectName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let fileName = "Expenses-\(sanitizedName).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.maximumFractionDigits = 0

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var csv = "Дата;Этап;Тип;Сумма;Комментарий\n"

        for exp in rows {
            let dateString = dateFormatter.string(from: exp.date)
            let category = exp.category.title.replacingOccurrences(of: ";", with: ",")
            let sub = exp.subCategory.title.replacingOccurrences(of: ";", with: ",")
            let amountString = formatter.string(from: exp.amount as NSDecimalNumber) ?? "\(exp.amount)"
            let note = (exp.note ?? "")
                .replacingOccurrences(of: ";", with: ",")
                .replacingOccurrences(of: "\n", with: " ")

            csv += "\(dateString);\(category);\(sub);\(amountString);\(note)\n"
        }

        do {
            try csv.data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            debugPrint("❌ CSV export error:", error.localizedDescription)
            return nil
        }
    }

    func exportExpensesPDF(for projectID: UUID) -> URL? {
        let rows = expenses(for: projectID).sorted { $0.date < $1.date }
        guard !rows.isEmpty else { return nil }

        let project = project(by: projectID)
        let projectName = project?.name ?? "Project"

        let sanitizedName = projectName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let fileName = "Expenses-\(sanitizedName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd.MM.yyyy"

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.groupingSeparator = " "
        numberFormatter.maximumFractionDigits = 0

        do {
            try renderer.writePDF(to: url, withActions: { context in
                var y: CGFloat = 40

                func newPage() {
                    context.beginPage()
                    y = 40
                }

                newPage()

                let title = "Отчёт по расходам"
                let attrsTitle: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold)
                ]
                (title as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrsTitle)
                y += 28

                let projectLine = "Проект: \(projectName)"
                let attrsSub: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14)
                ]
                (projectLine as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrsSub)
                y += 20

                y += 10
                let header = "Дата       Этап; Тип                           Сумма        Комментарий"
                let attrsHeader: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12, weight: .medium)
                ]
                (header as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrsHeader)
                y += 18

                context.cgContext.move(to: CGPoint(x: 40, y: y))
                context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: y))
                context.cgContext.setLineWidth(0.5)
                context.cgContext.strokePath()
                y += 8

                for exp in rows {
                    if y > pageHeight - 60 {
                        newPage()
                    }

                    let dateString = dateFormatter.string(from: exp.date)
                    let cat = exp.category.shortTitle
                    let sub = exp.subCategory.title
                    let amountString = numberFormatter.string(from: exp.amount as NSDecimalNumber) ?? "\(exp.amount)"
                    let note = exp.note ?? ""

                    let lineLeft = "\(dateString)  \(cat) / \(sub)"
                    (lineLeft as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 11)]
                    )

                    let amountX = pageWidth - 40 - 80
                    (amountString as NSString).draw(
                        at: CGPoint(x: amountX, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 11, weight: .medium)]
                    )
                    y += 14

                    if !note.isEmpty {
                        let noteAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 10),
                        ]
                        let noteRect = CGRect(x: 40, y: y, width: pageWidth - 80, height: 1000)
                        let noteStr = NSAttributedString(string: note, attributes: noteAttrs)
                        let framesetter = CTFramesetterCreateWithAttributedString(noteStr)
                        let path = CGMutablePath()
                        path.addRect(noteRect)
                        let frame = CTFramesetterCreateFrame(
                            framesetter,
                            CFRange(location: 0, length: noteStr.length),
                            path,
                            nil
                        )

                        let ctx = UIGraphicsGetCurrentContext()!
                        ctx.saveGState()
                        ctx.textMatrix = .identity
                        ctx.translateBy(x: 0, y: pageHeight)
                        ctx.scaleBy(x: 1.0, y: -1.0)
                        ctx.translateBy(x: 0, y: -noteRect.origin.y * 2 - noteRect.height)
                        CTFrameDraw(frame, ctx)
                        ctx.restoreGState()

                        y += 24
                    } else {
                        y += 4
                    }
                }
            })

            return url
        } catch {
            debugPrint("❌ PDF export error:", error.localizedDescription)
            return nil
        }
    }

    func exportCustomerExpensesPDF(
        for projectID: UUID,
        dateFrom: Date?,
        dateTo: Date?
    ) -> URL? {

        var rows = expenses(for: projectID)

        var from = dateFrom
        var to = dateTo
        if let f = from, let t = to, f > t {
            swap(&from, &to)
        }

        if let f = from { rows = rows.filter { $0.date >= f } }
        if let t = to { rows = rows.filter { $0.date <= t } }

        guard !rows.isEmpty else { return nil }

        let project = project(by: projectID)
        let projectName = project?.name ?? "Project"

        let sanitizedName = projectName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let fileName = "Expenses-Customer-\(sanitizedName).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        let pageWidth: CGFloat = 595.2
        let pageHeight: CGFloat = 841.8
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let dateFormatter2 = DateFormatter()
        dateFormatter2.dateFormat = "dd.MM.yyyy"

        let numberFormatter2 = NumberFormatter()
        numberFormatter2.numberStyle = .decimal
        numberFormatter2.groupingSeparator = " "
        numberFormatter2.maximumFractionDigits = 0

        let groupedByCategory = Dictionary(grouping: rows, by: { $0.category })

        do {
            try renderer.writePDF(to: url, withActions: { context in
                var y: CGFloat = 40

                func newPage() {
                    context.beginPage()
                    y = 40
                }

                newPage()

                let title = "Отчёт по расходам для заказчика"
                let attrsTitle: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 20, weight: .bold)
                ]
                (title as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrsTitle)
                y += 28

                let projectLine = "Проект: \(projectName)"
                let attrsSub: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 14)
                ]
                (projectLine as NSString).draw(at: CGPoint(x: 40, y: y), withAttributes: attrsSub)
                y += 20

                if from != nil || to != nil {
                    var period = "Период: "
                    if let f = from, let t = to {
                        period += "\(dateFormatter2.string(from: f)) – \(dateFormatter2.string(from: t))"
                    } else if let f = from {
                        period += "с \(dateFormatter2.string(from: f))"
                    } else if let t = to {
                        period += "по \(dateFormatter2.string(from: t))"
                    }

                    (period as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                    )
                    y += 20
                }

                let totalAmount = rows.reduce(Decimal.zero) { $0 + $1.amount }
                let totalLine = "Итого по отчёту: \(numberFormatter2.string(from: totalAmount as NSDecimalNumber) ?? "\(totalAmount)")"
                (totalLine as NSString).draw(
                    at: CGPoint(x: 40, y: y),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 13, weight: .medium)]
                )
                y += 24

                context.cgContext.move(to: CGPoint(x: 40, y: y))
                context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: y))
                context.cgContext.setLineWidth(0.5)
                context.cgContext.strokePath()
                y += 12

                let sortedCategories = groupedByCategory.keys.sorted { $0.title < $1.title }

                for category in sortedCategories {
                    guard let catRows = groupedByCategory[category] else { continue }

                    if y > pageHeight - 80 {
                        newPage()
                    }

                    let stageTitle = category.title
                    (stageTitle as NSString).draw(
                        at: CGPoint(x: 40, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
                    )
                    y += 20

                    let groupedBySub = Dictionary(grouping: catRows, by: { $0.subCategory })
                    let subSums: [(ExpenseSubCategory, Decimal)] = groupedBySub
                        .map { sub, items in
                            let sum = items.reduce(Decimal.zero) { $0 + $1.amount }
                            return (sub, sum)
                        }
                        .sorted { $0.0.title < $1.0.title }

                    var stageTotal: Decimal = 0

                    for (sub, sum) in subSums {
                        if y > pageHeight - 60 {
                            newPage()
                        }

                        stageTotal += sum

                        let lineLeft = "• \(sub.title)"
                        let amountString = numberFormatter2.string(from: sum as NSDecimalNumber) ?? "\(sum)"

                        (lineLeft as NSString).draw(
                            at: CGPoint(x: 52, y: y),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 12)]
                        )

                        let amountX = pageWidth - 40 - 80
                        (amountString as NSString).draw(
                            at: CGPoint(x: amountX, y: y),
                            withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .medium)]
                        )

                        y += 16
                    }

                    if y > pageHeight - 60 {
                        newPage()
                    }

                    let stageTotalString = numberFormatter2.string(from: stageTotal as NSDecimalNumber) ?? "\(stageTotal)"
                    let stageTotalLine = "Итого по этапу: \(stageTotalString)"

                    (stageTotalLine as NSString).draw(
                        at: CGPoint(x: 52, y: y),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 12, weight: .semibold)]
                    )

                    y += 24

                    context.cgContext.move(to: CGPoint(x: 40, y: y))
                    context.cgContext.addLine(to: CGPoint(x: pageWidth - 40, y: y))
                    context.cgContext.setLineWidth(0.25)
                    context.cgContext.strokePath()
                    y += 16
                }
            })

            return url
        } catch {
            debugPrint("❌ Customer PDF export error:", error.localizedDescription)
            return nil
        }
    }
}
