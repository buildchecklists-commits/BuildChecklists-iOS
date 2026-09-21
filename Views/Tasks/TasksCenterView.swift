import SwiftUI

struct TasksCenterView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var showNewTaskForm: Bool = false
    @State private var editingTask: TaskItem?
    @State private var errorText: String?

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var isMonthExpanded: Bool = false
    @State private var currentMonthOffset: Int = 0

    /// Флаг: показывать задачи только за выбранную дату
    @State private var filterBySelectedDate: Bool = false

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    private let calendar = Calendar.current

    // Фильтры блока "Ваша задача на стройке"
    private enum TaskFilter {
        case all
        case today
        case overdue
        case completed
    }

    @State private var activeFilter: TaskFilter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                CalendarHeader(
                    tasks: store.tasks,
                    selectedDate: $selectedDate,
                    isMonthExpanded: $isMonthExpanded,
                    currentMonthOffset: $currentMonthOffset,
                    onSelectDate: handleDateTap(_:)
                )

                contentList
            }
            .background(Color("softBackground").ignoresSafeArea())
            .navigationTitle("Календарь и задачи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        guard !store.isReadOnlyMode else {
                            showReadOnlyAlert = true
                            return
                        }
                        showNewTaskForm = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .searchable(text: $query, prompt: "Поиск по задачам…")

            // New Task
            .sheet(isPresented: $showNewTaskForm) {
                NavigationStack {
                    TaskFormView(mode: .create)
                        .environmentObject(store)
                }
            }

            // Edit Task
            .sheet(item: $editingTask) { (task: TaskItem) in
                NavigationStack {
                    TaskFormView(mode: .edit(task))
                        .environmentObject(store)
                }
            }

            // Paywall
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(store)
            }

            // Read-only alert
            .alert("Режим только просмотр", isPresented: $showReadOnlyAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Разблокировать") {
                    Task {
                        // На случай если подписка уже активна/восстановлена — сначала обновим доступ
                        _ = await store.refreshRoleForCurrentUser()
                        if store.isReadOnlyMode {
                            showPaywall = true
                        }
                    }
                }
            } message: {
                Text("Сейчас активен режим просмотра. Для создания и управления задачами нужна подписка USER или PRO.")
            }

            // Generic error
            .alert("Ошибка", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - Обработка выбора даты в календарях

    private func tasks(on date: Date) -> [TaskItem] {
        store.tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: date)
        }
    }

    private func handleDateTap(_ date: Date) {
        selectedDate = date
        let dayTasks = tasks(on: date)

        if dayTasks.isEmpty {
            // На этот день задач нет — сразу предлагаем создать новую
            filterBySelectedDate = false

            guard !store.isReadOnlyMode else {
                showReadOnlyAlert = true
                return
            }

            showNewTaskForm = true
        } else {
            // На этот день уже есть задачи — показываем только их
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                activeFilter = .all
                filterBySelectedDate = true
            }
        }
    }

    // MARK: - Список задач

    private var contentList: some View {
        List {
            headerStats

            if filteredTasks.isEmpty {
                Section {
                    VStack(spacing: 8) {
                        if store.tasks.isEmpty {
                            Text("Задач нет")
                                .font(.subheadline.weight(.semibold))
                            Text("Добавьте первую задачу, чтобы ничего не забыть.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("По запросу ничего не найдено")
                                .font(.subheadline.weight(.semibold))
                            Text("Попробуйте изменить текст поиска.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else if filterBySelectedDate {
                            Text("На выбранную дату задач нет")
                                .font(.subheadline.weight(.semibold))
                            Text("Нажмите «+», чтобы добавить задачу на этот день.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else {
                            switch activeFilter {
                            case .all:
                                Text("Задачи по выбранному фильтру не найдены")
                                    .font(.subheadline.weight(.semibold))
                            case .today:
                                Text("На сегодня задач нет")
                                    .font(.subheadline.weight(.semibold))
                            case .overdue:
                                Text("Просроченных задач нет")
                                    .font(.subheadline.weight(.semibold))
                            case .completed:
                                Text("Выполненных задач нет")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text("Попробуйте выбрать другой фильтр или добавить задачу.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
                Section {
                    ForEach(filteredTasks) { task in
                        taskRow(task)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Верхний блок статистики

    private var headerStats: some View {
        let total = store.tasks.count
        let overdueCount = overdueTasks.count
        let todayCount = tasksForToday.count
        let completedCount = completedTasks.count

        return VStack(alignment: .leading, spacing: 8) {
            Text("Ваша задача на стройке")
                .font(.headline)

            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    statChip(
                        title: "Всего",
                        value: total,
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
    }

    private func statChip(
        title: String,
        value: Int,
        systemName: String,
        tint: Color,
        filter: TaskFilter
    ) -> some View {
        let isActive = activeFilter == filter
        let baseOpacity: Double = isActive ? 0.35 : 0.15

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                activeFilter = filter
                // При переключении фильтра сбрасываем фильтр по конкретной дате
                filterBySelectedDate = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption2)
                    Text("\(value)")
                        .font(.subheadline.weight(.semibold))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(tint.opacity(baseOpacity))
            .foregroundColor(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ряды задач

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
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

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

            Spacer()

            Button {
                guard !store.isReadOnlyMode else {
                    showReadOnlyAlert = true
                    return
                }
                editingTask = task
            } label: {
                Image(systemName: "ellipsis")
                    .rotationEffect(.degrees(90))
                    .padding(6)
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
        .padding(.vertical, 4)
    }

    // MARK: - Фильтрация + сортировка

    private var filteredTasks: [TaskItem] {
        var tasks = store.tasks

        // Фильтр по выбранной дате (если активен)
        if filterBySelectedDate {
            tasks = tasks.filter { task in
                guard let due = task.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: selectedDate)
            }
        }

        // Фильтр блока статистики
        switch activeFilter {
        case .all:
            break
        case .today:
            tasks = tasks.filter { isToday($0) }
        case .overdue:
            tasks = tasks.filter { isOverdue($0) }
        case .completed:
            tasks = tasks.filter { $0.isCompleted }
        }

        // Поиск
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedQuery.isEmpty {
            tasks = tasks.filter { task in
                task.title.lowercased().contains(trimmedQuery) ||
                (task.details?.lowercased().contains(trimmedQuery) ?? false)
            }
        }

        // Сортировка:
        // 1. Просроченные
        // 2. Предстоящие (с датой в будущем/сегодня, не выполненные)
        // 3. Остальные (без даты)
        // 4. Выполненные (без даты или с датой)
        func category(for task: TaskItem) -> Int {
            if isOverdue(task) { return 0 }
            if !task.isCompleted, let due = task.dueDate {
                if due >= calendar.startOfDay(for: Date()) { return 1 }
            }
            if task.isCompleted { return 3 }
            return 2
        }

        return tasks.sorted { lhs, rhs in
            let lc = category(for: lhs)
            let rc = category(for: rhs)
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

    private var tasksForToday: [TaskItem] {
        store.tasks.filter { isToday($0) }
    }

    private var overdueTasks: [TaskItem] {
        store.tasks.filter { isOverdue($0) }
    }

    private var completedTasks: [TaskItem] {
        store.tasks.filter { $0.isCompleted }
    }

    // MARK: - Даты и статусы

    private func isToday(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        return calendar.isDateInToday(due)
    }

    private func isOverdue(_ task: TaskItem) -> Bool {
        guard let due = task.dueDate else { return false }
        return !task.isCompleted && due < calendar.startOfDay(for: Date())
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short   // Показываем и дату, и время
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

// MARK: - Шапка календаря: неделя + разворачиваемый месяц

struct CalendarHeader: View {
    let tasks: [TaskItem]

    @Binding var selectedDate: Date
    @Binding var isMonthExpanded: Bool
    @Binding var currentMonthOffset: Int

    /// Колбэк при выборе даты (из недельного и месячного календаря)
    let onSelectDate: (Date) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Текущая неделя")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        isMonthExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(isMonthExpanded ? "Свернуть" : "Месяц")
                            .font(.caption)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .rotationEffect(.degrees(isMonthExpanded ? 180 : 0))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray6))
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            DayStrip(selectedDate: $selectedDate, tasks: tasks, onSelectDate: onSelectDate)
                .padding(.bottom, isMonthExpanded ? 0 : 8)

            if isMonthExpanded {
                Divider()
                MonthCalendarView(
                    tasks: tasks,
                    selectedDate: $selectedDate,
                    currentMonthOffset: $currentMonthOffset,
                    onSelectDate: onSelectDate
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - DayStrip (неделя)

struct DayStrip: View {
    @Binding var selectedDate: Date
    let tasks: [TaskItem]
    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current

    init(selectedDate: Binding<Date>, tasks: [TaskItem], onSelectDate: @escaping (Date) -> Void) {
        _selectedDate = selectedDate
        self.tasks = tasks
        self.onSelectDate = onSelectDate
    }

    var body: some View {
        let weekStart = startOfWeek(for: selectedDate)
        let days = (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: weekStart)
        }

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(days, id: \.self) { day in
                    dayChip(day)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private enum DayStatus {
        case none
        case overdue
        case inProgress
        case completed
    }

    private func status(for date: Date) -> DayStatus {
        let dayTasks = tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: date)
        }

        if dayTasks.isEmpty { return .none }

        let todayStart = calendar.startOfDay(for: Date())

        var hasCompleted = false
        var hasInProgress = false
        var hasOverdue = false

        for task in dayTasks {
            if task.isCompleted {
                hasCompleted = true
            } else if let due = task.dueDate {
                if due < todayStart {
                    hasOverdue = true
                } else {
                    hasInProgress = true
                }
            }
        }

        if hasOverdue { return .overdue }
        if hasInProgress { return .inProgress }
        if hasCompleted { return .completed }
        return .none
    }

    private func dotColor(for status: DayStatus) -> Color {
        switch status {
        case .none: return .clear
        case .overdue: return .red
        case .inProgress: return .orange
        case .completed: return .green
        }
    }

    private func dayChip(_ date: Date) -> some View {
        let df = DateFormatter()
        df.dateFormat = "dd.MM"

        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let status = status(for: date)
        let color = dotColor(for: status)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedDate = date
            }
            onSelectDate(date)
        } label: {
            VStack(spacing: 4) {
                Text(df.string(from: date))
                    .font(.caption)

                Text(shortWeekday(for: date))
                    .font(.caption2)

                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .opacity(status == .none ? 0 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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

// MARK: - MonthCalendarView (разворачиваемый месяц)

struct MonthCalendarView: View {
    let tasks: [TaskItem]

    @Binding var selectedDate: Date
    @Binding var currentMonthOffset: Int

    let onSelectDate: (Date) -> Void

    private let calendar = Calendar.current
    private let columns: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    init(
        tasks: [TaskItem],
        selectedDate: Binding<Date>,
        currentMonthOffset: Binding<Int>,
        onSelectDate: @escaping (Date) -> Void
    ) {
        self.tasks = tasks
        _selectedDate = selectedDate
        _currentMonthOffset = currentMonthOffset
        self.onSelectDate = onSelectDate
    }

    private enum DayStatus {
        case none
        case overdue
        case inProgress
        case completed
    }

    var body: some View {
        let monthDate = currentMonthDate
        let dates = gridDates(for: monthDate)

        VStack(spacing: 8) {
            HStack {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        currentMonthOffset -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .padding(6)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(monthTitle(for: monthDate))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                        currentMonthOffset += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            // Заголовки дней недели
            HStack {
                ForEach(weekdayHeaders, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    dayCell(date, in: monthDate)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Helpers

    private var currentMonthDate: Date {
        let today = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .month, value: currentMonthOffset, to: today) ?? today
    }

    private func gridDates(for month: Date) -> [Date] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) else {
            return []
        }

        // Начало сетки — понедельник недели, в которую попадает 1-е число
        let startOfGrid = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: monthStart)) ?? monthStart

        // 6 недель по 7 дней
        return (0..<42).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: startOfGrid)
        }
    }

    private func dayStatus(for date: Date) -> DayStatus {
        let dayTasks = tasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDate(due, inSameDayAs: date)
        }

        if dayTasks.isEmpty { return .none }

        let todayStart = calendar.startOfDay(for: Date())

        var hasCompleted = false
        var hasInProgress = false
        var hasOverdue = false

        for task in dayTasks {
            if task.isCompleted {
                hasCompleted = true
            } else if let due = task.dueDate {
                if due < todayStart {
                    hasOverdue = true
                } else {
                    hasInProgress = true
                }
            }
        }

        if hasOverdue { return .overdue }
        if hasInProgress { return .inProgress }
        if hasCompleted { return .completed }
        return .none
    }

    private func dotColor(for status: DayStatus) -> Color {
        switch status {
        case .none: return .clear
        case .overdue: return .red
        case .inProgress: return .orange
        case .completed: return .green
        }
    }

    private func dayCell(_ date: Date, in month: Date) -> some View {
        let isInCurrentMonth = calendar.isDate(date, equalTo: month, toGranularity: .month)
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let status = dayStatus(for: date)
        let color = dotColor(for: status)

        let day = calendar.component(.day, from: date)

        return Button {
            guard isInCurrentMonth else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
                selectedDate = date
            }
            onSelectDate(date)
        } label: {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(.caption)

                Circle()
                    .fill(color)
                    .frame(width: 5, height: 5)
                    .opacity(status == .none ? 0 : 1)
            }
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(6)
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
    }

    private func monthTitle(for date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ru_RU")
        df.dateFormat = "LLLL yyyy"
        let text = df.string(from: date)
        // Первая буква с заглавной
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private var weekdayHeaders: [String] {
        var symbols = calendar.shortStandaloneWeekdaySymbols // зависит от локали
        let firstIndex = calendar.firstWeekday - 1
        if firstIndex > 0 {
            let head = symbols[firstIndex...]
            let tail = symbols[..<firstIndex]
            symbols = Array(head + tail)
        }
        return symbols.map { $0.uppercased() }
    }
}
