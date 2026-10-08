import SwiftUI
import Combine

// MARK: - Root chrome (overlay + menu + arrive actions)

/// Overlay + menu sheet. Apply on the root `NavigationStack` so chrome stays above pushed screens.
/// Sheets presented by the tour draw their own overlay (`demoTrainingSheetOverlay`).
struct DemoTrainingChromeModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var training = DemoTrainingController.shared

    private var isActive: Bool {
        DemoTrainingPrototypeGate.isEnabled && store.isDemoMode
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isActive {
                    DemoTrainingOverlay(surface: .root)
                        .ignoresSafeArea()
                }
            }
            .sheet(isPresented: Binding(
                get: { isActive && training.showMenu },
                set: { if !$0 { training.dismissMenu() } }
            )) {
                DemoTrainingMenuView()
            }
            .onChange(of: training.pendingArrive) { _, action in
                guard isActive, let action else { return }
                handleArrive(action)
            }
            .onChange(of: store.isDemoMode) { _, demo in
                if !demo {
                    cancelDeferredNavigation()
                    training.handleDemoEnded()
                }
            }
            .onChange(of: store.selectedTab) { _, tab in
                guard isActive, training.activeTour != nil else { return }
                // Programmatic tab changes made by the tour must not end it.
                if let expected = training.expectedTabChange {
                    training.expectedTabChange = nil
                    if expected == tab { return }
                }
                cancelDeferredNavigation()
                training.handleTabChangedByUser()
            }
            .onChange(of: training.activeTour) { _, tour in
                if tour == nil {
                    cancelDeferredNavigation()
                }
            }
            .onAppear {
                training.photosAvailabilityProvider = { [store] in
                    DemoTrainingPhotosProbe.hasAnyVisiblePhoto(store: store)
                }
                if let action = training.pendingArrive, isActive {
                    handleArrive(action)
                }
            }
    }

    private func handleArrive(_ action: DemoTrainingArriveAction) {
        training.consumePendingArrive()
        let target = DemoTrainingRoute.make(for: action)
        let epoch = training.navigationEpoch
        training.routeTask?.cancel()
        training.routeTask = Task { @MainActor [store = store, training = training] in
            await DemoTrainingRouter.perform(target, store: store, training: training, epoch: epoch)
        }
    }

    private func cancelDeferredNavigation() {
        training.routeTask?.cancel()
        training.routeTask = nil
        training.clearRequestFlags()
        training.consumePendingArrive()
    }
}

// MARK: - Staged navigation

/// Moves the app to a `DemoTrainingRoute` using only existing screens.
/// Order: close sheets → pop pushes / switch tab → push → present sheets.
/// Each stage waits for the previous animation, and bails out as soon as the tour ends.
@MainActor
enum DemoTrainingRouter {
    static func perform(
        _ target: DemoTrainingRoute,
        store: AppStore,
        training: DemoTrainingController,
        epoch: UInt64
    ) async {
        func alive() -> Bool {
            !Task.isCancelled && training.navigationEpoch == epoch && training.activeTour != nil
        }
        func pause(_ seconds: Double) async -> Bool {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return alive()
        }
        guard alive() else { return }

        // The in-memory DEMO project must exist before plan / budget / dashboard pushes
        // (avoids «Проект не найден» on slow devices).
        if target.needsDemoProject {
            var attempts = 0
            while demoProjectID(store) == nil, attempts < 40 {
                guard await pause(0.1) else { return }
                attempts += 1
            }
            guard demoProjectID(store) != nil else { return }
        }

        // 1. Close sheets that are not part of the target.
        var closedSheet = false
        if training.requestPresentTaskForm && !target.taskForm {
            training.requestPresentTaskForm = false
            closedSheet = true
        }
        if training.requestPushConcreteCalculator && !target.concrete {
            training.requestPushConcreteCalculator = false
        }
        if training.requestPresentCalculator && !target.calculator {
            training.requestPresentCalculator = false
            closedSheet = true
        }
        if training.requestPresentPhotoViewer && !target.photoViewer {
            training.requestPresentPhotoViewer = false
            closedSheet = true
        }
        if training.requestExpandBudgetPlan && !target.expandBudgetPlan {
            training.requestExpandBudgetPlan = false
        }
        if closedSheet {
            guard await pause(0.5) else { return }
        }

        // 2. Pop pushes that are not part of the target, then switch tab.
        var popped = false
        if training.requestOpenDemoDashboard && !target.dashboard {
            training.requestOpenDemoDashboard = false
            popped = true
        }
        if training.requestOpenTasksCenter && !target.tasksCenter {
            training.requestOpenTasksCenter = false
            popped = true
        }
        if training.requestOpenDemoPlan && !target.plan {
            training.requestOpenDemoPlan = false
            popped = true
        }
        if training.requestOpenDemoBudget && !target.budget {
            training.requestOpenDemoBudget = false
            popped = true
        }
        let desiredTab = target.tab ?? store.selectedTab
        if store.selectedTab != desiredTab {
            training.expectedTabChange = desiredTab
            store.setSelectedTab(desiredTab)
        }
        if popped {
            guard await pause(0.45) else { return }
        }

        // 3. Push screens the target needs.
        var pushed = false
        if target.dashboard && !training.requestOpenDemoDashboard {
            training.requestOpenDemoDashboard = true
            pushed = true
        }
        if target.tasksCenter && !training.requestOpenTasksCenter {
            training.requestOpenTasksCenter = true
            pushed = true
        }
        if target.plan && !training.requestOpenDemoPlan {
            training.requestOpenDemoPlan = true
            pushed = true
        }
        if target.budget && !training.requestOpenDemoBudget {
            training.requestOpenDemoBudget = true
            pushed = true
        }
        if pushed && (target.expandBudgetPlan || target.taskForm) {
            guard await pause(0.55) else { return }
        }

        // 4. UI-only expansion and sheets.
        if target.expandBudgetPlan && !training.requestExpandBudgetPlan {
            training.requestExpandBudgetPlan = true
        }
        if target.calculator && !training.requestPresentCalculator {
            training.requestPresentCalculator = true
            if target.concrete {
                guard await pause(0.6) else { return }
            }
        }
        if target.concrete && !training.requestPushConcreteCalculator {
            training.requestPushConcreteCalculator = true
        }
        if target.taskForm && !training.requestPresentTaskForm {
            training.requestPresentTaskForm = true
        }
        if target.photoViewer && !training.requestPresentPhotoViewer {
            training.requestPresentPhotoViewer = true
        }
    }

    static func demoProjectID(_ store: AppStore) -> UUID? {
        if let id = store.sessionDemoProjectID,
           store.projects.contains(where: { $0.id == id }) {
            return id
        }
        return store.projects.first?.id
    }
}

// MARK: - Push destinations (must live inside the matching NavigationStack)

/// Projects stack (root `NavigationStack`): DEMO dashboard + task calendar.
struct DemoTrainingNavigationModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var training = DemoTrainingController.shared

    private var isActive: Bool {
        DemoTrainingPrototypeGate.isEnabled && store.isDemoMode
    }

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: { isActive && training.requestOpenDemoDashboard && DemoTrainingRouter.demoProjectID(store) != nil },
                set: { if !$0 { training.requestOpenDemoDashboard = false } }
            )) {
                if let id = DemoTrainingRouter.demoProjectID(store) {
                    ProjectDashboardView(projectID: id)
                        .environmentObject(store)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { isActive && training.requestOpenTasksCenter },
                set: { if !$0 { training.requestOpenTasksCenter = false } }
            )) {
                TasksCenterView()
                    .environmentObject(store)
            }
    }
}

/// «Сроки» tab stack: project plan for the DEMO project.
struct DemoTrainingPlanTabModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var training = DemoTrainingController.shared

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: {
                    store.isDemoMode && training.requestOpenDemoPlan
                        && DemoTrainingRouter.demoProjectID(store) != nil
                },
                set: { if !$0 { training.requestOpenDemoPlan = false } }
            )) {
                if let id = DemoTrainingRouter.demoProjectID(store) {
                    ProjectPlanView(projectID: id)
                        .environmentObject(store)
                }
            }
    }
}

/// «Бюджет» tab stack: budget detail for the DEMO project.
struct DemoTrainingBudgetTabModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var training = DemoTrainingController.shared

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: {
                    store.isDemoMode && training.requestOpenDemoBudget
                        && DemoTrainingRouter.demoProjectID(store) != nil
                },
                set: { if !$0 { training.requestOpenDemoBudget = false } }
            )) {
                if let id = DemoTrainingRouter.demoProjectID(store) {
                    BudgetProjectView(projectID: id)
                        .environmentObject(store)
                }
            }
    }
}

/// Calculator sheet stack: pushes the concrete calculator (real screen, nothing saved).
/// Tour instance gets an isolated training example; normal entry still uses empty fields.
struct DemoTrainingCalculatorNavigationModifier: ViewModifier {
    @ObservedObject private var training = DemoTrainingController.shared

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: Binding(
                get: { training.requestPushConcreteCalculator },
                set: { if !$0 { training.requestPushConcreteCalculator = false } }
            )) {
                ConcreteCalculatorView(trainingExample: true)
            }
    }
}

// MARK: - Sheet bridges and overlay

/// Keeps a view's own `@State` sheet / disclosure flag in sync with a controller request flag.
/// The controller flag drives the UI; closing the UI also clears the flag.
struct DemoTrainingFlagBridge: ViewModifier {
    @Binding var isOn: Bool
    let flag: AnyPublisher<Bool, Never>
    let clear: @MainActor () -> Void
    /// Swiping a tour sheet away ends the tour instead of leaving an invisible one behind.
    var endsTourWhenDismissedByUser = false

    func body(content: Content) -> some View {
        content
            .onReceive(flag.removeDuplicates().receive(on: DispatchQueue.main)) { requested in
                if requested != isOn { isOn = requested }
            }
            .onChange(of: isOn) { _, now in
                guard !now else { return }
                let training = DemoTrainingController.shared
                let wasRequested = training.activeTour != nil && training.currentSurface == .sheet
                clear()
                if endsTourWhenDismissedByUser && wasRequested {
                    training.exitTour()
                }
            }
    }
}

/// Sheets sit above the root overlay, so tour steps inside them draw their own coach chrome.
struct DemoTrainingSheetOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay {
            DemoTrainingOverlay(surface: .sheet)
                .ignoresSafeArea()
        }
    }
}

extension View {
    func demoTrainingChrome() -> some View {
        modifier(DemoTrainingChromeModifier())
    }

    /// Root (Projects) stack destinations: DEMO dashboard + task calendar.
    func demoTrainingNavigation() -> some View {
        modifier(DemoTrainingNavigationModifier())
    }

    func demoTrainingPlanTabNavigation() -> some View {
        modifier(DemoTrainingPlanTabModifier())
    }

    func demoTrainingBudgetTabNavigation() -> some View {
        modifier(DemoTrainingBudgetTabModifier())
    }

    func demoTrainingCalculatorNavigation() -> some View {
        modifier(DemoTrainingCalculatorNavigationModifier())
    }

    func demoTrainingSheetOverlay() -> some View {
        modifier(DemoTrainingSheetOverlayModifier())
    }

    /// «Новая задача» sheet inside the task calendar.
    func demoTrainingTaskFormBridge(_ isPresented: Binding<Bool>) -> some View {
        modifier(DemoTrainingFlagBridge(
            isOn: isPresented,
            flag: DemoTrainingController.shared.$requestPresentTaskForm.eraseToAnyPublisher(),
            clear: { DemoTrainingController.shared.requestPresentTaskForm = false },
            endsTourWhenDismissedByUser: true
        ))
    }

    /// Calculator sheet over the Projects tab.
    func demoTrainingCalculatorBridge(_ isPresented: Binding<Bool>) -> some View {
        modifier(DemoTrainingFlagBridge(
            isOn: isPresented,
            flag: DemoTrainingController.shared.$requestPresentCalculator.eraseToAnyPublisher(),
            clear: { DemoTrainingController.shared.requestPresentCalculator = false },
            endsTourWhenDismissedByUser: true
        ))
    }

    /// UI-only «План / факт по этапам» expansion in the budget detail.
    func demoTrainingBudgetPlanBridge(_ isExpanded: Binding<Bool>) -> some View {
        modifier(DemoTrainingFlagBridge(
            isOn: isExpanded,
            flag: DemoTrainingController.shared.$requestExpandBudgetPlan.eraseToAnyPublisher(),
            clear: { DemoTrainingController.shared.requestExpandBudgetPlan = false }
        ))
    }

    /// Fullscreen gallery over the Photos tab (existing viewer; no picker / permissions).
    func demoTrainingPhotoViewerBridge(_ isPresented: Binding<Bool>) -> some View {
        modifier(DemoTrainingFlagBridge(
            isOn: isPresented,
            flag: DemoTrainingController.shared.$requestPresentPhotoViewer.eraseToAnyPublisher(),
            clear: { DemoTrainingController.shared.requestPresentPhotoViewer = false },
            endsTourWhenDismissedByUser: true
        ))
    }

    /// Backward-compatible alias used by RootView / MainTabView wiring.
    func demoTrainingHost() -> some View {
        demoTrainingChrome()
    }
}
