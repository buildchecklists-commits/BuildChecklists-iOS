import SwiftUI

struct TasksCenterView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// `nil` = общий календарь (все проекты + без привязки). Dashboard передаёт id объекта.
    var initialProjectID: UUID? = nil

    @State private var projectFilterID: UUID?
    @State private var didApplyInitialProject = false

    @State private var query: String = ""
    /// Item-based sheet so create prefill is captured at presentation time (not a stale nil).
    @State private var createPresentation: CreatePresentation?
    @State private var editingTask: TaskItem?
    @State private var errorText: String?

    private struct CreatePresentation: Identifiable {
        let id = UUID()
        let prefill: TaskFormView.CreatePrefill?
    }

    /// Bridges training ↔ create sheet without losing ownership rules in `DemoTrainingFlagBridge`.
    private var showNewTaskFormBinding: Binding<Bool> {
        Binding(
            get: { createPresentation != nil },
            set: { isPresented in
                if isPresented {
                    if createPresentation == nil {
                        createPresentation = CreatePresentation(prefill: nil)
                    }
                } else {
                    createPresentation = nil
                }
            }
        )
    }

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isMonthExpanded: Bool = false
    /// Absolute month being browsed (not an offset from “today”, so midnight cannot shift it).
    @State private var visibleMonth: Date = TasksCenterView.monthStart(for: Date())

    /// `true` — список только за `selectedDate`; `false` — общий режим с разделами.
    @State private var filterBySelectedDate: Bool = false

    @State private var completedSectionExpanded: Bool = false

    /// Shared “today” for sections, counters, and calendar marks.
    @State private var calendarDayStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var dayBoundaryTask: Task<Void, Never>?

    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    private let calendar = Calendar.current

    fileprivate static func monthStart(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }

    private enum TaskFilter: Equatable {
        case all
        case today
        case overdue
        case completed
    }

    @State private var activeFilter: TaskFilter = .all

    var body: some View {
        NavigationStack {
            contentList
                .demoTrainingAnchor(.taskCalendarListOrEmpty)
            .background(Color("softBackground").ignoresSafeArea())
            .navigationTitle("Календарь и задачи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        openCreateForm(prefillDueForSelectedDay: filterBySelectedDate)
                    } label: {
                        Image(systemName: "plus")
                            .demoTrainingAnchor(.taskCalendarAddButton)
                    }
                    .accessibilityLabel("Добавить задачу")
                }
            }
            .searchable(text: $query, prompt: "Поиск по задачам…")
            .sheet(item: $createPresentation) { presentation in
                NavigationStack {
                    TaskFormView(mode: .create, prefill: presentation.prefill)
                        .environmentObject(store)
                }
                .demoTrainingSheetOverlay()
            }
            .demoTrainingTaskFormBridge(showNewTaskFormBinding)
            .sheet(item: $editingTask) { (task: TaskItem) in
                NavigationStack {
                    TaskFormView(mode: .edit(task))
                        .environmentObject(store)
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(store)
            }
            .alert("Режим только просмотр", isPresented: $showReadOnlyAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Разблокировать") {
                    Task {
                        _ = await store.refreshRoleForCurrentUser()
                        if store.isReadOnlyMode {
                            showPaywall = true
                        }
                    }
                }
            } message: {
                Text("Сейчас активен режим просмотра. Для создания и управления задачами нужна подписка USER или PRO.")
            }
            .alert("Ошибка", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
            .onAppear {
                if !didApplyInitialProject {
                    projectFilterID = initialProjectID
                    didApplyInitialProject = true
                }
                refreshCalendarDayIfNeeded()
                startDayBoundaryMonitoring()
            }
            .onDisappear {
                dayBoundaryTask?.cancel()
                dayBoundaryTask = nil
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshCalendarDayIfNeeded()
                    startDayBoundaryMonitoring()
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                syncVisibleMonth(to: newDate)
            }
            .onChange(of: visibleMonth) { _, newMonth in
                alignSelectedDateIfOutsideVisibleMonth(newMonth)
            }
        }
    }

    // MARK: - Project filter

    private var projectFilterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button {
                    projectFilterID = nil
                } label: {
                    labelWithCheck(title: "Все проекты", selected: projectFilterID == nil)
                }
                ForEach(store.projects) { project in
                    Button {
                        projectFilterID = project.id
                    } label: {
                        labelWithCheck(
                            title: project.name,
                            selected: projectFilterID == project.id
                        )
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "building.2")
                        .font(.caption.weight(.semibold))
                    Text(projectFilterTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .accessibilityLabel("Объект календаря")
            .accessibilityValue(projectFilterTitle)
        }
    }

    private func labelWithCheck(title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            if selected {
                Image(systemName: "checkmark")
            }
        }
    }

    private var projectFilterTitle: String {
        guard let id = projectFilterID else { return "Все проекты" }
        return store.project(by: id)?.name ?? "Все проекты"
    }

    // MARK: - Task scopes

    /// Tasks for list/stats after project filter (search applied later).
    private var projectScopedTasks: [TaskItem] {
        store.tasks.filter { taskMatchesProjectFilter($0) }
    }

    /// Calendar marks ignore search text; depend on object only.
    private var tasksForCalendarMarks: [TaskItem] {
        projectScopedTasks
    }

    private func taskMatchesProjectFilter(_ task: TaskItem) -> Bool {
        guard let filter = projectFilterID else { return true }
        return task.projectID == filter
    }

    private func refreshCalendarDayIfNeeded() {
        let start = calendar.startOfDay(for: Date())
        guard !calendar.isDate(start, inSameDayAs: calendarDayStart) else { return }
        calendarDayStart = start
        // Intentionally leave `visibleMonth` and `selectedDate` untouched on midnight rollover.
    }

    /// Sleeps until the next local midnight so open calendars refresh without backgrounding.
    private func startDayBoundaryMonitoring() {
        dayBoundaryTask?.cancel()
        dayBoundaryTask = Task { @MainActor in
            while !Task.isCancelled {
                refreshCalendarDayIfNeeded()
                let start = calendar.startOfDay(for: Date())
                guard let nextMidnight = calendar.date(byAdding: .day, value: 1, to: start) else { return }
                let delay = max(nextMidnight.timeIntervalSinceNow + 0.25, 1)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    private func syncVisibleMonth(to date: Date) {
        let month = Self.monthStart(for: date, calendar: calendar)
        if !calendar.isDate(visibleMonth, equalTo: month, toGranularity: .month) {
            visibleMonth = month
        }
    }

    /// When the user pages the month grid, keep the selected day inside that month.
    private func alignSelectedDateIfOutsideVisibleMonth(_ month: Date) {
        guard !calendar.isDate(selectedDate, equalTo: month, toGranularity: .month) else { return }
        let day = calendar.component(.day, from: selectedDate)
        var comps = calendar.dateComponents([.year, .month], from: month)
        let range = calendar.range(of: .day, in: .month, for: month)
        comps.day = min(day, range?.count ?? day)
        if let aligned = calendar.date(from: comps) {
            selectedDate = calendar.startOfDay(for: aligned)
        }
    }

    // MARK: - Date selection

    private func handleDateTap(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        syncVisibleMonth(to: selectedDate)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            activeFilter = calendar.isDate(selectedDate, inSameDayAs: calendarDayStart) ? .today : .all
            filterBySelectedDate = true
            completedSectionExpanded = false
        }
    }

    private func jumpToToday() {
        refreshCalendarDayIfNeeded()
        selectedDate = calendarDayStart
        syncVisibleMonth(to: calendarDayStart)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            activeFilter = .today
            filterBySelectedDate = true
            completedSectionExpanded = false
        }
    }

    private func showAllDates() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            filterBySelectedDate = false
            activeFilter = .all
            completedSectionExpanded = false
        }
    }

    private func openCreateForm(prefillDueForSelectedDay: Bool) {
        guard !store.isReadOnlyMode else {
            showReadOnlyAlert = true
            return
        }
        let prefill: TaskFormView.CreatePrefill
        if prefillDueForSelectedDay {
            prefill = TaskFormView.CreatePrefill(
                projectID: projectFilterID,
                dueDate: TaskFormView.defaultDueSuggestion(on: selectedDate),
                hasDueDate: true
            )
        } else {
            prefill = TaskFormView.CreatePrefill(
                projectID: projectFilterID,
                dueDate: nil,
                hasDueDate: false
            )
        }
        createPresentation = CreatePresentation(prefill: prefill)
    }

    // MARK: - List

    private var showsTasksLoadFailure: Bool {
        store.tasksLoadUnreadable && !store.isDemoMode
    }

    private var contentList: some View {
        List {
            // Calendar lives inside the list so SE / large Dynamic Type can scroll to tasks.
            Section {
                projectFilterBar
                CalendarHeader(
                    tasks: tasksForCalendarMarks,
                    todayStart: calendarDayStart,
                    selectedDate: $selectedDate,
                    isMonthExpanded: $isMonthExpanded,
                    visibleMonth: $visibleMonth,
                    onSelectDate: handleDateTap(_:)
                )
                .demoTrainingAnchor(.taskCalendarHeader)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color(.systemBackground))

            if showsTasksLoadFailure {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Не удалось прочитать задачи")
                            .font(.subheadline.weight(.semibold))
                        Text("Файл задач повреждён или недоступен. Это не означает, что задач нет — данные на диске не очищены. Перезапустите приложение. Не создавайте и не удаляйте задачи, пока ошибка не исчезнет.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("tasks.loadUnreadable")
                }
            } else {
                dayModeControls
                headerStats

                if filterBySelectedDate {
                    dayModeSections
                } else if activeFilter != .all {
                    filteredFlatSection
                } else {
                    generalModeSections
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var dayModeControls: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(filterBySelectedDate ? selectedDayTitle : "Все даты")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }

                dayModeActionButtons
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var dayModeActionButtons: some View {
        let todayButton = Button {
            jumpToToday()
        } label: {
            Text("Сегодня")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)

        let allDatesButton = Button {
            showAllDates()
        } label: {
            Text("Все даты")
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)

        if filterBySelectedDate {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    todayButton
                    allDatesButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    todayButton
                    allDatesButton
                }
            }
        } else {
            todayButton
        }
    }

    private var selectedDayTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMMM yyyy, EEEE"
        let text = df.string(from: selectedDate)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: - Stats

    private var headerStats: some View {
        let overdueCount = overdueActiveTasks.count
        let todayCount = todayActiveTasks.count
        let completedCount = projectScopedTasks.filter(\.isCompleted).count
        let totalCount = projectScopedTasks.count

        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ваша задача на стройке")
                    .font(.headline)

                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        statChip(
                            title: "Всего",
                            value: totalCount,
                            systemName: "checklist",
                            tint: Color(.systemGray4),
                            filter: .all
                        )
                        statChip(
                            title: "Сегодня",
                            value: todayCount,
                            systemName: "sun.max",
                            tint: Color.orange,
                            filter: .today
                        )
                    }
                    HStack(spacing: 12) {
                        statChip(
                            title: "Просрочено",
                            value: overdueCount,
                            systemName: "exclamationmark.triangle",
                            tint: Color.red,
                            filter: .overdue
                        )
                        statChip(
                            title: "Выполнено",
                            value: completedCount,
                            systemName: "checkmark.circle",
                            tint: Color.green,
                            filter: .completed
                        )
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func isStatChipSelected(_ filter: TaskFilter) -> Bool {
        switch filter {
        case .all:
            return activeFilter == .all && !filterBySelectedDate
        case .today:
            return activeFilter == .today
                && filterBySelectedDate
                && calendar.isDate(selectedDate, inSameDayAs: calendarDayStart)
        case .overdue, .completed:
            return activeFilter == filter && !filterBySelectedDate
        }
    }

    private func statChip(
        title: String,
        value: Int,
        systemName: String,
        tint: Color,
        filter: TaskFilter
    ) -> some View {
        let isActive = isStatChipSelected(filter)
        let baseOpacity: Double = isActive ? 0.35 : 0.15

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                if filter == .today {
                    jumpToToday()
                    return
                }
                activeFilter = filter
                filterBySelectedDate = false
                if filter == .completed {
                    completedSectionExpanded = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                        .lineLimit(1)
                    Text("\(value)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(tint.opacity(baseOpacity))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isActive ? tint.opacity(0.7) : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityValue(isActive ? "выбрано" : "не выбрано")
    }

    // MARK: - Sections (general)

    @ViewBuilder
    private var generalModeSections: some View {
        let overdue = sortedDated(overdueActiveTasks.filteredBySearch(query))
        let today = sortedDated(todayActiveTasks.filteredBySearch(query))
        let upcoming = sortedDated(upcomingActiveTasks.filteredBySearch(query))
        let noDue = sortedByTitle(noDueActiveTasks.filteredBySearch(query))
        let completed = sortedCompleted(completedTasksForScope.filteredBySearch(query))
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let anyVisible = !overdue.isEmpty || !today.isEmpty || !upcoming.isEmpty || !noDue.isEmpty || !completed.isEmpty

        if !anyVisible {
            emptyStateSection(searching: searching)
        } else {
            taskSection(title: "Просрочено", tasks: overdue)
            taskSection(title: "Сегодня", tasks: today)
            taskSection(title: "Предстоящие", tasks: upcoming)
            taskSection(title: "Без срока", tasks: noDue)
            completedDisclosureSection(tasks: completed, searching: searching)
        }
    }

    // MARK: - Day mode

    @ViewBuilder
    private var dayModeSections: some View {
        let dayTasks = projectScopedTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: selectedDate)
        }
        let active = sortedDated(dayTasks.filter { !$0.isCompleted }.filteredBySearch(query))
        let completed = sortedCompleted(dayTasks.filter(\.isCompleted).filteredBySearch(query))
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if active.isEmpty && completed.isEmpty {
            Section {
                VStack(spacing: 10) {
                    if searching {
                        Text("По запросу ничего не найдено")
                            .font(.subheadline.weight(.semibold))
                        Text("Попробуйте изменить текст поиска.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("На этот день задач нет")
                            .font(.subheadline.weight(.semibold))
                        Button("Добавить задачу") {
                            openCreateForm(prefillDueForSelectedDay: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        } else {
            if !active.isEmpty {
                Section("Задачи") {
                    ForEach(active) { task in
                        taskRow(task)
                    }
                }
            } else if !searching {
                Section {
                    Text("На этот день активных задач нет")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            completedDisclosureSection(tasks: completed, searching: searching)
        }
    }

    @ViewBuilder
    private var filteredFlatSection: some View {
        let tasks = flatFilteredTasks
        let searching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if tasks.isEmpty {
            emptyStateSection(searching: searching)
        } else {
            Section {
                ForEach(tasks) { task in
                    taskRow(task)
                }
            }
        }
    }

    private func taskSection(title: String, tasks: [TaskItem]) -> some View {
        Group {
            if !tasks.isEmpty {
                Section(title) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func completedDisclosureSection(tasks: [TaskItem], searching: Bool) -> some View {
        if !tasks.isEmpty {
            Section {
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { searching ? true : completedSectionExpanded },
                        set: { completedSectionExpanded = $0 }
                    )
                ) {
                    ForEach(tasks) { task in
                        taskRow(task)
                    }
                } label: {
                    HStack {
                        Text("Выполненные")
                        Spacer()
                        Text("\(tasks.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func emptyStateSection(searching: Bool) -> some View {
        Section {
            VStack(spacing: 8) {
                if searching {
                    Text("По запросу ничего не найдено")
                        .font(.subheadline.weight(.semibold))
                    Text("Попробуйте изменить текст поиска.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else if projectScopedTasks.isEmpty {
                    Text("Задач нет")
                        .font(.subheadline.weight(.semibold))
                    Text("Добавьте первую задачу, чтобы ничего не забыть.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("Задачи по выбранному фильтру не найдены")
                        .font(.subheadline.weight(.semibold))
                    Text("Попробуйте выбрать другой фильтр или добавить задачу.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Row

    private func taskRow(_ task: TaskItem) -> some View {
        let projectName: String? = task.projectID.flatMap { id in
            store.project(by: id)?.name
        }

        return HStack(alignment: .top, spacing: 10) {
            Button {
                guard !store.isReadOnlyMode else {
                    showReadOnlyAlert = true
                    return
                }
                toggleCompletion(task)
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .top)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .strikethrough(task.isCompleted)

                if let details = task.details, !details.isEmpty {
                    Text(details)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let projectName {
                        Label(projectName, systemImage: "house")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    if let dueDate = task.dueDate {
                        Label(
                            dateFormatter.string(from: dueDate),
                            systemImage: "calendar"
                        )
                        .font(.caption2)
                        .foregroundColor(isOverdue(task) ? .red : .secondary)
                    }
                }
            }

            Spacer(minLength: 0)

            Button {
                guard !store.isReadOnlyMode else {
                    showReadOnlyAlert = true
                    return
                }
                editingTask = task
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .contextMenu {
                Button {
                    guard !store.isReadOnlyMode else {
                        showReadOnlyAlert = true
                        return
                    }
                    editingTask = task
                } label: {
                    Label("Редактировать", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    guard !store.isReadOnlyMode else {
                        showReadOnlyAlert = true
                        return
                    }
                    delete(task)
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Buckets (depend on calendarDayStart)

    private var overdueActiveTasks: [TaskItem] {
        projectScopedTasks.filter { isOverdue($0) }
    }

    private var todayActiveTasks: [TaskItem] {
        projectScopedTasks.filter { !$0.isCompleted && isDueOnToday($0) }
    }

    private var upcomingActiveTasks: [TaskItem] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendarDayStart) ?? calendarDayStart
        return projectScopedTasks.filter { task in
            guard !task.isCompleted, let due = task.dueDate else { return false }
            return calendar.startOfDay(for: due) >= tomorrow
        }
    }

    private var noDueActiveTasks: [TaskItem] {
        projectScopedTasks.filter { !$0.isCompleted && $0.dueDate == nil }
    }

    private var completedTasksForScope: [TaskItem] {
        projectScopedTasks.filter(\.isCompleted)
    }

    private var flatFilteredTasks: [TaskItem] {
        var tasks = projectScopedTasks
        switch activeFilter {
        case .all:
            break
        case .today:
            tasks = tasks.filter { isDueOnToday($0) && !$0.isCompleted }
        case .overdue:
            tasks = tasks.filter { isOverdue($0) }
        case .completed:
            tasks = tasks.filter(\.isCompleted)
        }
        tasks = tasks.filteredBySearch(query)
        return sortedForFlatList(tasks)
    }

    private func isDueOnToday(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        return calendar.isDate(due, inSameDayAs: calendarDayStart)
    }

    private func isOverdue(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        return !task.isCompleted && calendar.startOfDay(for: due) < calendarDayStart
    }

    private func sortedDated(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?):
                if l != r { return l < r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortedByTitle(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.title != rhs.title { return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func sortedCompleted(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func sortedForFlatList(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            let lc = flatCategory(lhs)
            let rc = flatCategory(rhs)
            if lc != rc { return lc < rc }
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?):
                if l != r { return l < r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.title < rhs.title
        }
    }

    private func flatCategory(_ task: TaskItem) -> Int {
        if isOverdue(task) { return 0 }
        if !task.isCompleted, task.dueDate != nil { return 1 }
        if task.isCompleted { return 3 }
        return 2
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }

    // MARK: - Actions

    private func toggleCompletion(_ task: TaskItem) {
        do {
            try store.toggleTaskCompletion(task)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func delete(_ task: TaskItem) {
        do {
            try store.deleteTask(task)
        } catch {
            errorText = error.localizedDescription
        }
    }

}

// MARK: - Search helper

private extension Array where Element == TaskItem {
    func filteredBySearch(_ query: String) -> [TaskItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return self }
        return filter { task in
            task.title.lowercased().contains(trimmed)
                || (task.details?.lowercased().contains(trimmed) ?? false)
        }
    }
}

// MARK: - Day mark model

struct TaskDayMark: Equatable {
    var activeCount: Int
    var hasOverdueActive: Bool
    var hasCompletedOnly: Bool

    static let empty = TaskDayMark(activeCount: 0, hasOverdueActive: false, hasCompletedOnly: false)

    static func make(tasks: [TaskItem], on day: Date, calendar: Calendar, todayStart: Date) -> TaskDayMark {
        let dayTasks = tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: day)
        }
        guard !dayTasks.isEmpty else { return .empty }

        var active = 0
        var overdue = false
        var completed = 0
        for task in dayTasks {
            if task.isCompleted {
                completed += 1
            } else {
                active += 1
                if let due = task.dueDate, calendar.startOfDay(for: due) < todayStart {
                    overdue = true
                }
            }
        }
        return TaskDayMark(
            activeCount: active,
            hasOverdueActive: overdue,
            hasCompletedOnly: active == 0 && completed > 0
        )
    }

    var badgeText: String? {
        guard activeCount > 0 else { return nil }
        return activeCount > 99 ? "99+" : "\(activeCount)"
    }

    var badgeColor: Color {
        if hasOverdueActive { return .red }
        return .orange
    }

    func accessibilityStatus(exactActive: Int) -> String {
        if exactActive > 0 {
            let status = hasOverdueActive ? "есть просроченные" : "активные в срок или на будущее"
            return "\(exactActive) активных задач, \(status)"
        }
        if hasCompletedOnly {
            return "все задачи выполнены"
        }
        return "нет задач"
    }
}

// MARK: - Calendar header

struct CalendarHeader: View {
    let tasks: [TaskItem]
    let todayStart: Date

    @Binding var selectedDate: Date
    @Binding var isMonthExpanded: Bool
    @Binding var visibleMonth: Date

    let onSelectDate: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            weekToolbar
                .padding(.horizontal)
                .padding(.top, 8)

            DayStrip(
                selectedDate: $selectedDate,
                tasks: tasks,
                todayStart: todayStart,
                onSelectDate: onSelectDate
            )
            .padding(.bottom, isMonthExpanded ? 0 : 8)

            if isMonthExpanded {
                Divider()
                MonthCalendarView(
                    tasks: tasks,
                    todayStart: todayStart,
                    selectedDate: $selectedDate,
                    visibleMonth: $visibleMonth,
                    onSelectDate: onSelectDate
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private var weekToolbar: some View {
        let monthButton = Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isMonthExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Text(isMonthExpanded ? "Свернуть" : "Месяц")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isMonthExpanded ? 180 : 0))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: 36)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
        }
        .accessibilityLabel(isMonthExpanded ? "Свернуть месяц" : "Месяц")

        // Accessibility sizes: always stack — never squeeze “Месяц” onto one broken line.
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(weekHeading)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                monthButton
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 8) {
                Text(weekHeading)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                monthButton
            }
        }
    }

    private var weekHeading: String {
        let weekStart = startOfWeek(for: selectedDate)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let todayWeek = startOfWeek(for: todayStart)
        if calendar.isDate(weekStart, inSameDayAs: todayWeek) {
            return "Эта неделя"
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "d MMM"
        return "Неделя \(df.string(from: weekStart))–\(df.string(from: weekEnd))"
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

// MARK: - DayStrip

struct DayStrip: View {
    @Binding var selectedDate: Date
    let tasks: [TaskItem]
    let todayStart: Date
    let onSelectDate: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let calendar = Calendar.current

    var body: some View {
        let weekStart = startOfWeek(for: selectedDate)
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(days, id: \.self) { day in
                                dayChip(day, expands: false)
                                    .id(dayStartID(day))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .onAppear { scrollSelected(into: proxy) }
                    .onChange(of: selectedDate) { _, _ in
                        scrollSelected(into: proxy)
                    }
                }
            } else {
                // Seven equal cells in the available width — no horizontal clipping of Sunday.
                HStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in
                        dayChip(day, expands: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
    }

    private func scrollSelected(into proxy: ScrollViewProxy) {
        let id = dayStartID(selectedDate)
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
        // Second pass after layout settles (open / «Сегодня»).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func dayStartID(_ date: Date) -> TimeInterval {
        calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
    }

    private func dayChip(_ date: Date, expands: Bool) -> some View {
        let df = DateFormatter()
        df.dateFormat = "dd.MM"

        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDate(date, inSameDayAs: todayStart)
        let mark = TaskDayMark.make(tasks: tasks, on: date, calendar: calendar, todayStart: todayStart)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedDate = date
            }
            onSelectDate(date)
        } label: {
            VStack(spacing: 2) {
                Text(df.string(from: date))
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(expands ? 0.75 : 1)
                Text(shortWeekday(for: date))
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(expands ? 0.75 : 1)
                dayMarkBadge(mark)
                    .frame(height: 14)
            }
            .padding(.horizontal, expands ? 2 : 10)
            .padding(.vertical, 6)
            .frame(maxWidth: expands ? .infinity : nil)
            .frame(minHeight: 56)
            .background(
                isSelected
                ? Color.accentColor.opacity(0.2)
                : (isToday ? Color.accentColor.opacity(0.08)
                           : Color.secondary.opacity(0.08))
            )
            .foregroundColor(isSelected ? .accentColor : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dayAccessibilityLabel(date: date, mark: mark))
    }

    private func shortWeekday(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "EE"
        return df.string(from: date)
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}

// MARK: - Month calendar

struct MonthCalendarView: View {
    let tasks: [TaskItem]
    let todayStart: Date

    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date

    let onSelectDate: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let calendar = Calendar.current
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        let monthDate = TasksCenterView.monthStart(for: visibleMonth, calendar: calendar)
        let dates = gridDates(for: monthDate)

        VStack(spacing: 8) {
            monthPager(for: monthDate)
                .padding(.horizontal)
                .padding(.top, 4)

            HStack(spacing: 2) {
                ForEach(weekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.7 : 1)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    dayCell(date, in: monthDate)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }

    @ViewBuilder
    private func monthPager(for monthDate: Date) -> some View {
        let title = Text(monthTitle(for: monthDate))
            .font(.subheadline.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

        let prev = Button {
            shiftMonth(by: -1)
        } label: {
            Image(systemName: "chevron.left")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Предыдущий месяц")

        let next = Button {
            shiftMonth(by: 1)
        } label: {
            Image(systemName: "chevron.right")
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Следующий месяц")

        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 4) {
                title
                    .frame(maxWidth: .infinity)
                HStack {
                    prev
                    Spacer()
                    next
                }
            }
        } else {
            HStack {
                prev
                Spacer()
                title
                Spacer()
                next
            }
        }
    }

    private func shiftMonth(by value: Int) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            if let next = calendar.date(byAdding: .month, value: value, to: TasksCenterView.monthStart(for: visibleMonth, calendar: calendar)) {
                visibleMonth = next
            }
        }
    }

    private func gridDates(for month: Date) -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }
        let startOfGrid = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthStart)) ?? monthStart
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfGrid)
        }
    }

    private func dayCell(_ date: Date, in month: Date) -> some View {
        let isInCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let mark = TaskDayMark.make(tasks: tasks, on: date, calendar: calendar, todayStart: todayStart)
        let day = calendar.component(.day, from: date)

        return Button {
            guard isInCurrentMonth else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedDate = date
            }
            onSelectDate(date)
        } label: {
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.caption)
                    .lineLimit(1)
                dayMarkBadge(mark)
                    .frame(height: 12)
            }
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 44 : 36)
            .padding(.vertical, 4)
            .background(
                isSelected
                ? Color.accentColor.opacity(0.2)
                : Color.clear
            )
            .foregroundColor(
                isInCurrentMonth
                ? (isSelected ? .accentColor : .primary)
                : .secondary.opacity(0.4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isInCurrentMonth)
        .accessibilityLabel(dayAccessibilityLabel(date: date, mark: mark))
        .accessibilityHidden(!isInCurrentMonth)
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        // Keep month+year as one unbreakable phrase on narrow / large-text layouts.
        df.dateFormat = dynamicTypeSize.isAccessibilitySize ? "LLL yyyy" : "LLLL yyyy"
        let text = df.string(from: date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var weekdayHeaders: [String] {
        var symbols = calendar.shortStandaloneWeekdaySymbols
        let firstIndex = calendar.firstWeekday - 1
        if firstIndex > 0 {
            let head = symbols[firstIndex...]
            let tail = symbols[..<firstIndex]
            symbols = Array(head + tail)
        }
        return symbols.map { $0.uppercased() }
    }
}

// MARK: - Shared day badge + a11y

@ViewBuilder
private func dayMarkBadge(_ mark: TaskDayMark) -> some View {
    if let text = mark.badgeText {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(mark.badgeColor)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: 28)
    } else if mark.hasCompletedOnly {
        Circle()
            .fill(Color.green)
            .frame(width: 5, height: 5)
    } else {
        Color.clear
    }
}

private func dayAccessibilityLabel(date: Date, mark: TaskDayMark) -> String {
    let df = DateFormatter()
    df.locale = Locale(identifier: "ru_RU")
    df.dateStyle = .long
    df.timeStyle = .none
    let dateText = df.string(from: date)
    return "\(dateText). \(mark.accessibilityStatus(exactActive: mark.activeCount))"
}
