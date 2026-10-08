import Foundation
import SwiftUI
import Combine

/// In-memory tour state for DEMO training (product feature; DEMO session only).
@MainActor
final class DemoTrainingController: ObservableObject {
    static let shared = DemoTrainingController()

    @Published var showMenu = false
    @Published private(set) var activeTour: DemoTrainingTourID?
    @Published private(set) var stepIndex = 0
    @Published var anchorFrames: [DemoTrainingAnchorID: CGRect] = [:]
    @Published var visibleBounds: CGRect = .null
    @Published var safeInsets: EdgeInsets = EdgeInsets()
    @Published var pendingArrive: DemoTrainingArriveAction?
    @Published var skipMissingStepAvailable = false
    /// Observed inside NavigationStack content to push the DEMO project dashboard.
    @Published var requestOpenDemoDashboard = false
    /// Plan tab stack: push `ProjectPlanView` for the DEMO project.
    @Published var requestOpenDemoPlan = false
    /// Budget tab stack: push `BudgetProjectView` for the DEMO project.
    @Published var requestOpenDemoBudget = false
    /// Projects stack: push `TasksCenterView`.
    @Published var requestOpenTasksCenter = false
    /// Calculator sheet over the Projects tab.
    @Published var requestPresentCalculator = false
    /// «Новая задача» sheet over the task calendar (never saves).
    @Published var requestPresentTaskForm = false
    /// Concrete calculator pushed inside the calculator sheet.
    @Published var requestPushConcreteCalculator = false
    /// Fullscreen photo gallery over the Photos tab (existing viewer only).
    @Published var requestPresentPhotoViewer = false
    /// UI-only expansion of the «План / факт по этапам» block.
    @Published var requestExpandBudgetPlan = false
    /// Measured coach stack height (card + pointer) from the overlay — drives focus switching.
    @Published private(set) var coachStackHeight: CGFloat = 0
    /// Locked when the photos tour starts so the step counter matches the chosen route.
    @Published private(set) var photosTourHasPhotos = false

    /// Bumped on every tour end so delayed arrive work is ignored.
    private(set) var navigationEpoch: UInt64 = 0

    private var missingTargetTask: Task<Void, Never>?
    /// In-flight staged navigation (dismiss sheets → pop → push → present). Cancelled on end / new step.
    var routeTask: Task<Void, Never>?
    /// Tab the router is about to select; lets the root chrome tell tour navigation from a user tap.
    var expectedTabChange: MainTab?
    /// Set by root chrome from `AppStore` — used only to pick the photos tour route.
    var photosAvailabilityProvider: (() -> Bool)?

    private init() {}

    var steps: [DemoTrainingStep] {
        guard let activeTour else { return [] }
        return Self.steps(for: activeTour, photosAvailable: photosTourHasPhotos)
    }

    var currentStep: DemoTrainingStep? {
        let list = steps
        guard list.indices.contains(stepIndex) else { return nil }
        return list[stepIndex]
    }

    var stepCounterText: String {
        guard !steps.isEmpty else { return "" }
        return "\(stepIndex + 1) из \(steps.count)"
    }

    /// Which overlay draws the coach for the current step (root vs presented sheet).
    var currentSurface: DemoTrainingSurface {
        currentStep?.surface ?? .root
    }

    /// Steps shown on a bare tab root keep the tab bar tappable so the user can leave the tour.
    var leavesTabBarHittable: Bool {
        guard let step = currentStep, step.surface == .root else { return false }
        guard let action = step.arriveAction else { return false }
        return DemoTrainingRoute.make(for: action).isTabRoot
    }

    var isLastStep: Bool { stepIndex >= steps.count - 1 && !steps.isEmpty }
    var canGoBack: Bool { stepIndex > 0 }

    var scrollHint: DemoTrainingScrollHint {
        guard let step = currentStep else { return .none }
        guard let rect = resolvedTargetRect(for: step), rect.width > 1, rect.height > 1 else {
            return .missingTarget
        }
        guard visibleBounds.width > 1, visibleBounds.height > 1 else { return .none }

        let top = visibleBounds.minY + max(safeInsets.top, 0) + 8
        let bottom = visibleBounds.maxY - max(safeInsets.bottom, 0) - 10
        let visible = CGRect(
            x: visibleBounds.minX,
            y: top,
            width: visibleBounds.width,
            height: max(0, bottom - top)
        )

        let intersection = rect.intersection(visible)
        // Scroll hints only care about the target being on-screen — never about room for the coach.
        if isTargetContentVisible(target: rect, intersection: intersection) {
            return .none
        }

        // Sticky chrome (filters / segmented header) does not move with list scroll.
        if isScrollPinnedAnchor(step.anchor) {
            if !intersection.isNull, intersection.width > 1, intersection.height > 1 {
                return .none
            }
            return .missingTarget
        }

        if rect.maxY <= visible.minY {
            return edgeScrollHint(wanting: .scrollUp, target: rect, visible: visible)
        }
        if rect.minY >= visible.maxY {
            return edgeScrollHint(wanting: .scrollDown, target: rect, visible: visible)
        }
        // Partially visible but not enough: move toward the missing portion.
        if intersection.minY <= visible.minY + 1, rect.minY < visible.minY {
            return edgeScrollHint(wanting: .scrollUp, target: rect, visible: visible)
        }
        if intersection.maxY >= visible.maxY - 1, rect.maxY > visible.maxY {
            return edgeScrollHint(wanting: .scrollDown, target: rect, visible: visible)
        }
        if rect.midY < visible.midY {
            return edgeScrollHint(wanting: .scrollUp, target: rect, visible: visible)
        }
        return edgeScrollHint(wanting: .scrollDown, target: rect, visible: visible)
    }

    var highlightedRect: CGRect? {
        guard scrollHint == .none, let step = currentStep else { return nil }
        guard let rect = resolvedTargetRect(for: step), rect.width > 1 else { return nil }
        return rect.insetBy(dx: -6, dy: -6)
    }

    /// Overlay reports the laid-out coach stack (card body + pointer) for the current text size.
    func updateCoachStackHeight(_ height: CGFloat) {
        guard height > 1 else { return }
        if abs(height - coachStackHeight) > 0.5 {
            coachStackHeight = height
        }
    }

    /// Prefer a compact focus subset when the full target leaves no room for the measured card.
    private func resolvedTargetRect(for step: DemoTrainingStep) -> CGRect? {
        guard let full = anchorFrames[step.anchor], full.width > 1, full.height > 1 else { return nil }
        guard visibleBounds.width > 1, visibleBounds.height > 1 else { return full }

        let top = visibleBounds.minY + max(safeInsets.top, 0) + 8
        let bottom = visibleBounds.maxY - max(safeInsets.bottom, 0) - 10
        let gap: CGFloat = 10
        // Actual stack height for current Dynamic Type; fall back only before first measure.
        let stack = max(coachStackHeight > 1 ? coachStackHeight : 140, 118)
        let neededSide = stack + gap
        let usable = max(0, bottom - top)
        let spaceAbove = full.minY - top
        let spaceBelow = bottom - full.maxY
        // Full summary and coach card must both fit in the usable band (stacked with a gap).
        let fullPlusCardFit = full.height + gap + stack <= usable
            && max(spaceAbove, spaceBelow) >= neededSide

        if let focusID = focusAnchorID(for: step.anchor),
           let focus = anchorFrames[focusID],
           focus.width > 1,
           focus.height > 1 {
            if fullPlusCardFit {
                return full
            }
            // Full summary + card do not fit — spotlight progress + bar only.
            return focus
        }

        if fullPlusCardFit {
            return full
        }

        // Photo viewer: keep the snapshot lit; the coach sits in the band under the image
        // (metadata / letterbox). Only shrink the lit band if even a compact card cannot fit.
        if step.anchor == .photosViewer {
            let minCard: CGFloat = 118
            if spaceBelow >= minCard || spaceAbove >= minCard {
                return full
            }
            // Extremely tight: keep a meaningful middle/upper slice of the photo.
            let need = minCard + gap
            let maxH = max(96, (bottom - need) - full.minY)
            let h = min(full.height, maxH)
            if h >= 96 {
                return CGRect(x: full.minX, y: full.minY, width: full.width, height: h)
            }
            let band = min(full.height, max(96, usable * 0.34))
            let y = min(max(full.minY, full.midY - band / 2), full.maxY - band)
            return CGRect(x: full.minX, y: y, width: full.width, height: band)
        }

        // Last resort: keep the top band of the target (progress-like).
        let band = min(full.height, max(96, (bottom - top) * 0.26))
        return CGRect(x: full.minX, y: full.minY, width: full.width, height: band)
    }

    private func focusAnchorID(for anchor: DemoTrainingAnchorID) -> DemoTrainingAnchorID? {
        switch anchor {
        case .projectsDashboardProgress: return .projectsDashboardProgressFocus
        default: return nil
        }
    }

    func openMenu() {
        endTour(clearPending: true)
        showMenu = true
    }

    func dismissMenu() {
        showMenu = false
    }

    func startTour(_ id: DemoTrainingTourID) {
        guard id.isImplemented else { return }
        showMenu = false
        photosTourHasPhotos = (id == .photos) ? (photosAvailabilityProvider?() ?? false) : false
        activeTour = id
        stepIndex = 0
        skipMissingStepAvailable = false
        visibleBounds = .null
        safeInsets = EdgeInsets()
        coachStackHeight = 0
        applyArriveIfNeeded(for: steps.first)
    }

    func next() {
        guard !steps.isEmpty else { return }
        if isLastStep {
            endTour(clearPending: true)
            return
        }
        let previousSurface = currentSurface
        stepIndex += 1
        skipMissingStepAvailable = false
        cancelMissingTargetTimer()
        invalidateVisibleBoundsIfNeeded(from: previousSurface, to: currentSurface)
        applyArriveIfNeeded(for: currentStep)
    }

    func back() {
        guard canGoBack else { return }
        let previousSurface = currentSurface
        stepIndex -= 1
        skipMissingStepAvailable = false
        cancelMissingTargetTimer()
        invalidateVisibleBoundsIfNeeded(from: previousSurface, to: currentSurface)
        applyArriveIfNeeded(for: currentStep)
    }

    /// Leaving a sheet step must not keep the sheet's visible band for root scroll math.
    private func invalidateVisibleBoundsIfNeeded(
        from previous: DemoTrainingSurface,
        to next: DemoTrainingSurface
    ) {
        guard previous != next else { return }
        visibleBounds = .null
        safeInsets = EdgeInsets()
        coachStackHeight = 0
    }

    func skipMissingStep() {
        next()
    }

    func exitTour() {
        endTour(clearPending: true)
    }

    #if DEBUG
    /// Preview/gallery/capture helper — not used by production tour flow.
    func debugJumpToStep(_ index: Int) {
        guard steps.indices.contains(index) else { return }
        stepIndex = index
        skipMissingStepAvailable = false
        pendingArrive = nil
        cancelMissingTargetTimer()
    }
    #endif

    func handleDemoEnded() {
        showMenu = false
        endTour(clearPending: true)
    }

    /// User switched tabs outside tour navigation — end training.
    func handleTabChangedByUser() {
        endTour(clearPending: true)
    }

    func updateAnchor(_ id: DemoTrainingAnchorID, rect: CGRect) {
        let previous = anchorFrames[id]
        if previous == nil || previous?.integral != rect.integral {
            anchorFrames[id] = rect
        }
        if currentStep?.anchor == id, rect.width > 1 {
            skipMissingStepAvailable = false
            cancelMissingTargetTimer()
        }
    }

    func clearAnchor(_ id: DemoTrainingAnchorID) {
        anchorFrames[id] = nil
        scheduleMissingTargetIfNeeded()
    }

    /// Only the overlay for the active surface may publish bounds (sheet must not overwrite root).
    func updateVisibleBounds(
        _ rect: CGRect,
        safeInsets: EdgeInsets = EdgeInsets(),
        surface: DemoTrainingSurface
    ) {
        guard currentSurface == surface else { return }
        visibleBounds = rect
        self.safeInsets = safeInsets
        scheduleMissingTargetIfNeeded()
    }

    func consumePendingArrive() {
        pendingArrive = nil
    }

    /// Sticky header / filter chrome that list scrolling cannot move.
    private func isScrollPinnedAnchor(_ id: DemoTrainingAnchorID) -> Bool {
        switch id {
        case .photosSourceFilter, .photosFilterSort:
            return true
        default:
            return false
        }
    }

    /// Enough of the target is on-screen to teach — ignores room for the coach card.
    private func isTargetContentVisible(target: CGRect, intersection: CGRect) -> Bool {
        guard !intersection.isNull, intersection.width > 1, intersection.height > 1 else { return false }
        // Compact targets: most of the measured rect. Tall targets: a meaningful band is enough.
        let required = min(max(target.height * 0.75, 80), 168)
        return intersection.height >= min(required, target.height)
    }

    /// Drop unfulfillable scroll prompts at content edges (already as far as scrolling can go).
    private func edgeScrollHint(
        wanting: DemoTrainingScrollHint,
        target: CGRect,
        visible: CGRect
    ) -> DemoTrainingScrollHint {
        switch wanting {
        case .scrollUp:
            // Target already starts at/above the visible top — scrolling up cannot reveal more.
            if target.minY >= visible.minY - 2 {
                return .none
            }
            return .scrollUp
        case .scrollDown:
            if target.maxY <= visible.maxY + 2 {
                return .none
            }
            return .scrollDown
        default:
            return wanting
        }
    }

    private func applyArriveIfNeeded(for step: DemoTrainingStep?) {
        guard let action = step?.arriveAction else { return }
        pendingArrive = action
    }

    private func endTour(clearPending: Bool) {
        navigationEpoch &+= 1
        activeTour = nil
        stepIndex = 0
        skipMissingStepAvailable = false
        routeTask?.cancel()
        routeTask = nil
        expectedTabChange = nil
        clearRequestFlags()
        coachStackHeight = 0
        cancelMissingTargetTimer()
        if clearPending { pendingArrive = nil }
    }

    /// Closes tour sheets and pops tour-pushed screens (bridges observe these flags).
    func clearRequestFlags() {
        requestPushConcreteCalculator = false
        requestPresentTaskForm = false
        requestPresentCalculator = false
        requestPresentPhotoViewer = false
        requestOpenDemoDashboard = false
        requestOpenDemoPlan = false
        requestOpenDemoBudget = false
        requestOpenTasksCenter = false
        requestExpandBudgetPlan = false
    }

    private func scheduleMissingTargetIfNeeded() {
        guard currentStep != nil, scrollHint == .missingTarget else {
            cancelMissingTargetTimer()
            skipMissingStepAvailable = false
            return
        }
        guard missingTargetTask == nil else { return }
        missingTargetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            if self.scrollHint == .missingTarget {
                self.skipMissingStepAvailable = true
            }
            self.missingTargetTask = nil
        }
    }

    private func cancelMissingTargetTimer() {
        missingTargetTask?.cancel()
        missingTargetTask = nil
    }

    /// Tour scripts. «Далее» only navigates: tabs, pushes and sheets that already exist in the app.
    /// Nothing here saves a task, expense, checklist item, PDF, purchase or permission.
    static func steps(for tour: DemoTrainingTourID, photosAvailable: Bool = false) -> [DemoTrainingStep] {
        switch tour {
        case .projects:
            return [
                DemoTrainingStep(
                    id: "p1",
                    anchor: .projectsListHeader,
                    title: "Ваши стройки здесь",
                    body: "В списке — учебные объекты. Фильтры сверху помогают смотреть текущие и завершённые.",
                    arriveAction: .selectTab(.projects)
                ),
                DemoTrainingStep(
                    id: "p2",
                    anchor: .projectsDemoCard,
                    title: "Карточка объекта",
                    body: "На карточке видны прогресс и срок. Дальше откроем объект и посмотрим сводку внутри.",
                    arriveAction: .popToProjectsRoot
                ),
                DemoTrainingStep(
                    id: "p3",
                    anchor: .projectsDashboardProgress,
                    title: "Сводка по проекту",
                    body: "Сверху — прогресс и даты. Это быстрый взгляд на состояние стройки.",
                    arriveAction: .openDemoProjectDashboard
                ),
                DemoTrainingStep(
                    id: "p4",
                    anchor: .projectsDashboardStages,
                    title: "Ход строительства",
                    body: "Здесь этапы проекта. Этап открывает чек-листы для работы с проверками. Первый этап — «Геология и подготовка участка».",
                    arriveAction: .openDemoProjectDashboard
                ),
                DemoTrainingStep(
                    id: "p5",
                    anchor: .projectsQuickActions,
                    title: "Быстрые действия",
                    body: "Кнопки ведут в рабочие инструменты: план, расходы, файлы, замечания, PDF и отчёты. Нужный раздел открывается отсюда в одно нажатие.",
                    arriveAction: .openDemoProjectDashboard
                )
            ]

        case .deadlines:
            return [
                DemoTrainingStep(
                    id: "d1",
                    anchor: .deadlinesListHeader,
                    title: "Вкладка «Сроки»",
                    body: "Здесь объекты со сроками. Фильтр и сортировка сверху помогают найти нужную стройку.",
                    arriveAction: .selectTab(.plan)
                ),
                DemoTrainingStep(
                    id: "d2",
                    anchor: .deadlinesDemoCard,
                    title: "Даты на карточке",
                    body: "На карточке видны даты начала и окончания проекта. Дальше откроем план со сроками по этапам.",
                    arriveAction: .selectTab(.plan)
                ),
                DemoTrainingStep(
                    id: "d3",
                    anchor: .deadlinesPlanHeader,
                    title: "План проекта",
                    body: "Вверху — название, адрес и даты стройки. Ниже начинается таймлайн этапов.",
                    arriveAction: .openDemoProjectPlan
                ),
                DemoTrainingStep(
                    id: "d4",
                    anchor: .deadlinesTimelineIntro,
                    title: "Этапы и сроки",
                    body: "Карточка этапа показывает плановые сроки; «Завершить» фиксирует факт, а для просроченного этапа можно указать причину задержки. Тур даты не меняет.",
                    arriveAction: .openDemoProjectPlan
                ),
                DemoTrainingStep(
                    id: "d5",
                    anchor: .deadlinesFirstStage,
                    title: "План и факт по этапу",
                    body: "На карточке этапа рядом видны плановые и фактические даты и статус. Даты вы меняете сами, тур их не трогает.",
                    arriveAction: .openDemoProjectPlan
                )
            ]

        case .budget:
            return [
                DemoTrainingStep(
                    id: "b1",
                    anchor: .budgetListHeader,
                    title: "Вкладка «Бюджет»",
                    body: "Объекты с краткой бюджетной сводкой. Фильтр и сортировка работают так же, как в «Проектах».",
                    arriveAction: .selectTab(.budget)
                ),
                DemoTrainingStep(
                    id: "b2",
                    anchor: .budgetDemoCard,
                    title: "Деньги на карточке",
                    body: "На карточке — сколько потрачено, общий бюджет, а также перерасход или экономия. Дальше откроем подробности по объекту.",
                    arriveAction: .selectTab(.budget)
                ),
                DemoTrainingStep(
                    id: "b3",
                    anchor: .budgetDetailHeader,
                    title: "Сводка бюджета",
                    body: "Сверху — бюджет, потрачено, остаток и отклонение. Это главные цифры по проекту.",
                    arriveAction: .openDemoBudgetDetail
                ),
                DemoTrainingStep(
                    id: "b4",
                    anchor: .budgetPlanFact,
                    title: "План и факт по этапам",
                    body: "План — сколько вы заложили на этап, факт — сколько уже потрачено. По сравнению видно, где расходы выходят за план.",
                    arriveAction: .expandBudgetPlanFact
                ),
                DemoTrainingStep(
                    id: "b5",
                    anchor: .budgetOperations,
                    title: "Операции",
                    body: "Здесь список расходов проекта с поиском и фильтрами. Тур расходов не добавляет — новые вы вносите сами в «Расходах» проекта.",
                    arriveAction: .openDemoBudgetDetail
                )
            ]

        case .photos:
            var list: [DemoTrainingStep] = [
                DemoTrainingStep(
                    id: "f1",
                    anchor: .photosSourceFilter,
                    title: "Источник фото",
                    body: "«Все», «Проект» и «Чек-листы»: фото объекта показываются отдельно от снимков, прикреплённых к пунктам чек-листов.",
                    arriveAction: .selectTab(.photos)
                ),
                DemoTrainingStep(
                    id: "f2",
                    anchor: .photosFilterSort,
                    title: "Порядок и фильтр",
                    body: "Сортировка по дате и фильтр по проекту и этапу. Меню сортировки и фильтра открывается здесь же — тур его не трогает.",
                    arriveAction: .selectTab(.photos)
                )
            ]
            if photosAvailable {
                list.append(contentsOf: [
                    DemoTrainingStep(
                        id: "f3",
                        anchor: .photosFirstGroupOrEmpty,
                        title: "Фото по времени",
                        body: "Снимки сгруппированы по давности: сегодня, неделя, месяц. Дальше откроем просмотр существующего снимка.",
                        arriveAction: .selectTab(.photos)
                    ),
                    DemoTrainingStep(
                        id: "f4",
                        anchor: .photosViewer,
                        title: "Просмотр фото",
                        body: "Крупный снимок. Закрыть — крестиком, «Назад» или «Завершить». Снимок не меняется.",
                        arriveAction: .presentPhotoViewer,
                        surface: .sheet
                    )
                ])
            } else {
                list.append(
                    DemoTrainingStep(
                        id: "f3",
                        anchor: .photosFirstGroupOrEmpty,
                        title: "Пока нет фото",
                        body: "Здесь появится пустое состояние, пока снимков нет. Тур не открывает выбор фото и не запрашивает разрешения.",
                        arriveAction: .selectTab(.photos)
                    )
                )
            }
            return list

        case .profile:
            return [
                DemoTrainingStep(
                    id: "r1",
                    anchor: .profileAccountDemo,
                    title: "Аккаунт и тариф",
                    body: "В демо-режиме указан тариф «Демо». После перезапуска учебного проекта нет в списке. Демо можно открыть заново. Тур ничего не покупает и не меняет.",
                    arriveAction: .selectTab(.profile)
                ),
                DemoTrainingStep(
                    id: "r2",
                    anchor: .profileTheme,
                    title: "Тема оформления",
                    body: "Системная, светлая или тёмная. Тему можно сменить здесь позже — тур её не переключает.",
                    arriveAction: .selectTab(.profile)
                ),
                DemoTrainingStep(
                    id: "r3",
                    anchor: .profileCreateProfileHint,
                    title: "Как сохранять стройки",
                    body: "Чтобы сохранять данные между запусками, создайте профиль: кнопка «Создать профиль» — в демо-блоке внизу списка проектов. Доступные возможности зависят от тарифа. Тур регистрацию не запускает.",
                    arriveAction: .selectTab(.projects)
                )
            ]

        case .taskCalendar:
            return [
                DemoTrainingStep(
                    id: "t1",
                    anchor: .taskCalendarEntryBanner,
                    title: "Календарь задач",
                    body: "Этот блок на экране «Проекты» ведёт в календарь с напоминаниями: купить материалы, заказать бетон и другие дела. Дальше откроем его.",
                    arriveAction: .popToProjectsRoot
                ),
                DemoTrainingStep(
                    id: "t2",
                    anchor: .taskCalendarHeader,
                    title: "Неделя и месяц",
                    body: "Полоса дней показывает текущую неделю, кнопка «Месяц» разворачивает весь месяц. День без задач открывает форму новой задачи — в туре форму покажем кнопкой «Далее».",
                    arriveAction: .openTasksCenter
                ),
                DemoTrainingStep(
                    id: "t3",
                    anchor: .taskCalendarListOrEmpty,
                    title: "Список задач",
                    body: "Сверху — счётчики «Всего», «Сегодня», «Просрочено», «Выполнено». Ниже — сами задачи; если их нет, показано пустое состояние.",
                    arriveAction: .openTasksCenter
                ),
                DemoTrainingStep(
                    id: "t4",
                    anchor: .taskCalendarAddButton,
                    title: "Новая задача",
                    body: "Кнопка «+» открывает форму создания. Дальше покажем её — без сохранения.",
                    arriveAction: .openTasksCenter
                ),
                DemoTrainingStep(
                    id: "t5",
                    anchor: .taskCalendarFormDescription,
                    title: "Форма задачи",
                    body: "Здесь задаются название, детали, срок и проект. После обучения можно создать свою задачу. Просмотр формы ничего не сохраняет.",
                    arriveAction: .presentNewTaskForm,
                    surface: .sheet
                )
            ]

        case .calculator:
            return [
                DemoTrainingStep(
                    id: "c1",
                    anchor: .calculatorEntryButton,
                    title: "Калькулятор",
                    body: "Кнопка «Калькулятор» рядом с сортировкой открывает расчёты материалов. Результаты считаются на экране и в проект не сохраняются.",
                    arriveAction: .popToProjectsRoot
                ),
                DemoTrainingStep(
                    id: "c2",
                    anchor: .calculatorHomeList,
                    title: "Выбор расчёта",
                    body: "Бетон, арматура, доска, блоки, штукатурка, шпаклёвка, утеплитель. Дальше откроем учебный пример по бетону.",
                    arriveAction: .presentCalculatorSheet,
                    surface: .sheet
                ),
                DemoTrainingStep(
                    id: "c3",
                    anchor: .calculatorConcreteParams,
                    title: "Учебный пример",
                    body: "Это учебный пример только для тура: длина 10 м, ширина 6 м, толщина 0,2 м, запас 5%. Обычный калькулятор и ваши проекты не меняются. Поля на время тура не редактируются.",
                    arriveAction: .pushConcreteCalculator,
                    surface: .sheet
                ),
                DemoTrainingStep(
                    id: "c4",
                    anchor: .calculatorConcreteResult,
                    title: "Результат примера",
                    body: "Учебный расчёт: 12 м³ бетона, с запасом 5% — 12,6 м³. Пример временный и не сохраняется в проект.",
                    arriveAction: .pushConcreteCalculator,
                    surface: .sheet
                )
            ]
        }
    }
}

// MARK: - Photos availability (route picker only)

/// Lightweight probe matching `GlobalPhotosView` visibility rules — no mutations, no picker.
enum DemoTrainingPhotosProbe {
    static func hasAnyVisiblePhoto(store: AppStore) -> Bool {
        for project in store.projects {
            for path in project.photoPaths {
                if existingFileURL(path) != nil { return true }
            }
            let stagesArrays: [[Stage]?] = [
                GeologyProgressStore.load(projectID: project.id),
                FoundationProgressStore.load(projectID: project.id),
                WallsProgressStore.load(projectID: project.id),
                SlabProgressStore.load(projectID: project.id),
                RoofProgressStore.load(projectID: project.id),
                RoofCoverProgressStore.load(projectID: project.id),
                EngineeringProgressStore.load(projectID: project.id),
                WindowsProgressStore.load(projectID: project.id),
                DoorsProgressStore.load(projectID: project.id),
                FinishingProgressStore.load(projectID: project.id),
                LandscapingProgressStore.load(projectID: project.id)
            ]
            for stagesOpt in stagesArrays {
                guard let stages = stagesOpt else { continue }
                for stage in stages {
                    for item in stage.items {
                        for path in item.photoPaths {
                            if existingFileURL(path) != nil { return true }
                        }
                    }
                }
            }
        }
        return false
    }
}
