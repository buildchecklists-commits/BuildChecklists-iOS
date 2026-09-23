import SwiftUI
import UIKit

// Единое имя нотификации о смене прогресса (используется во всех экранах)
extension Notification.Name {
    static let bcProgressDidChange = Notification.Name("BCProgressDidChange")
}

@MainActor
struct ProjectDashboardView: View {

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var showShareSheet = false
    @State private var reportURL: URL?
    @State private var showChecklistReport = false

    @State private var showProjectFilesSheet = false
    @State private var showContactsList = false

    @State private var isFilesExpanded = false
    @State private var areContactsExpanded = false

    // sheet для быстрой формы задачи
    @State private var showQuickTaskForm = false

    // Триггер для перерисовки прогресса по нотификации
    @State private var progressVersion: Int = 0

    @State private var issues: [ChecklistIssueRef] = []
    @State private var issuesLoadGeneration = 0
    @Environment(\.scenePhase) private var scenePhase

    private var project: Project? {
        store.projects.first(where: { $0.id == projectID })
    }

    // MARK: - BODY

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(spacing: 26) {

                        headerCard(project)

                        if !issues.isEmpty {
                            issuesSection(project)
                        }

                        tasksSection(project)

                        quickActions(project)

                        stagesSection(project)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .background(ProjectUXColors.screenBackground)
                .navigationTitle(project.name)
                .navigationBarTitleDisplayMode(.inline)

                .sheet(isPresented: $showShareSheet) {
                    if let url = reportURL {
                        ShareSheet(activityItems: [url])
                    }
                }
                .sheet(isPresented: $showChecklistReport) {
                    NavigationStack {
                        ChecklistReportExportView(projectID: project.id)
                            .environmentObject(store)
                    }
                }
                .sheet(isPresented: $showProjectFilesSheet) {
                    NavigationStack {
                        ProjectFilesView(projectID: project.id)
                            .environmentObject(store)
                    }
                }
                .sheet(isPresented: $showContactsList) {
                    NavigationStack {
                        ProjectContactsListView(projectID: project.id)
                            .environmentObject(store)
                    }
                }
                // Быстрая форма задачи, привязанная к этому проекту
                .sheet(isPresented: $showQuickTaskForm) {
                    NavigationStack {
                        ProjectQuickTaskForm(projectID: project.id)
                            .environmentObject(store)
                    }
                }

                .onAppear {
                    reloadIssues()
                }

                // Любое изменение прогресса этапов перерисовывает дашборд
                .onReceive(NotificationCenter.default.publisher(for: .bcProgressDidChange)) { _ in
                    progressVersion &+= 1
                    reloadIssues()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        reloadIssues()
                    }
                }

            } else {
                Text("Проект не найден")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - ВЕРХНЯЯ КАРТОЧКА ПРОЕКТА

    private func headerCard(_ project: Project) -> some View {

        let projectProgress = overallProgress(for: project)
        let percentage = Int((projectProgress * 100).rounded())
        let progressColor = colorForProjectProgress(projectProgress)
        let isComplete = projectProgress >= 1.0
        let clamped = min(max(projectProgress, 0), 1)

        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    progressNumber(percentage, color: progressColor)
                    Spacer(minLength: 12)
                    if let end = project.dateEnd {
                        deadlineLabel(deadlineStatus(end, isComplete: isComplete), alignment: .trailing)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    progressNumber(percentage, color: progressColor)
                    if let end = project.dateEnd {
                        deadlineLabel(deadlineStatus(end, isComplete: isComplete), alignment: .leading)
                    }
                }
            }

            summaryProgressBar(fraction: clamped, color: progressColor)

            if !project.address.isEmpty {
                Text(project.address)
                    .font(.subheadline)
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let manager = project.manager?.trimmingCharacters(in: .whitespacesAndNewlines),
               !manager.isEmpty {
                Label("Ответственный: \(manager)", systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            projectDateRow(project)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ProjectUXColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func progressNumber(_ percentage: Int, color: Color) -> some View {
        Text("\(percentage)%")
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(color)
            .monospacedDigit()
            .accessibilityLabel("Прогресс \(percentage) процентов")
    }

    private func deadlineLabel(
        _ status: (text: String, color: Color),
        alignment: TextAlignment
    ) -> some View {
        Text(status.text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(status.color)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func summaryProgressBar(fraction: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ProjectUXColors.progressTrack)
                if fraction > 0 {
                    Capsule()
                        .fill(color)
                        .frame(width: max(0, proxy.size.width * fraction))
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func projectDateRow(_ project: Project) -> some View {
        if project.dateStart != nil || project.dateEnd != nil {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    if let start = project.dateStart {
                        datePill(text: dateString(start), icon: "calendar")
                    }
                    if let end = project.dateEnd {
                        datePill(text: dateString(end), icon: "calendar.badge.clock")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let start = project.dateStart {
                        datePill(text: dateString(start), icon: "calendar")
                    }
                    if let end = project.dateEnd {
                        datePill(text: dateString(end), icon: "calendar.badge.clock")
                    }
                }
            }
        }
    }

    // MARK: - Даты / статус

    private func datePill(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(ProjectUXColors.primaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ProjectUXColors.secondarySurface)
            .clipShape(Capsule())
    }

    /// Same start-of-day difference as before. Red is only a past end date on an unfinished project.
    private func deadlineStatus(_ endDate: Date, isComplete: Bool) -> (text: String, color: Color) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: endDate)
        let diff = cal.dateComponents([.day], from: today, to: target).day ?? 0

        if isComplete, diff < 0 {
            return ("Завершён", ProjectUXColors.progressComplete)
        }
        if diff > 0 {
            return ("Осталось \(diff) дн.", ProjectUXColors.secondaryText)
        } else if diff == 0 {
            return ("Сегодня", ProjectUXColors.progressActive)
        } else {
            return ("Просрочено на \(abs(diff)) дн.", ProjectUXColors.overdue)
        }
    }

    // MARK: - Цвет прогресса проекта

    /// Green only when the unrounded ten-pack average is complete, same as the project list.
    /// A label that rounds to 100% stays yellow while the fraction is below 1.
    private func colorForProjectProgress(_ value: Double) -> Color {
        if value >= 1.0 {
            return ProjectUXColors.progressComplete
        }
        return ProjectUXColors.progressActive
    }

    // MARK: - Общий прогресс проекта (ИДЕНТИЧЕН ProjectsListView.overallProgress)

    private func overallProgress(for project: Project) -> Double {
        func percent(_ stages: [Stage]?) -> Double {
            guard let stages, !stages.isEmpty else { return 0 }
            let items = stages.flatMap { $0.items }
            guard !items.isEmpty else { return 0 }
            let done = items.filter { $0.status == .ok }.count
            return Double(done) / Double(items.count)
        }

        let vals: [Double] = [
            percent(GeologyProgressStore.load(projectID: project.id)),
            percent(FoundationProgressStore.load(projectID: project.id)),
            percent(WallsProgressStore.load(projectID: project.id)),
            percent(SlabProgressStore.load(projectID: project.id)),
            percent(RoofProgressStore.load(projectID: project.id)),
            percent(RoofCoverProgressStore.load(projectID: project.id)),
            percent(EngineeringProgressStore.load(projectID: project.id)),
            percent(WindowsProgressStore.load(projectID: project.id)),
            percent(FinishingProgressStore.load(projectID: project.id)),
            percent(LandscapingProgressStore.load(projectID: project.id))
        ]

        guard !vals.isEmpty else { return 0 }
        return vals.reduce(0, +) / Double(vals.count)
    }

    private func quickActions(_ project: Project) -> some View {
        ProjectQuickActions(
            openFiles: { showProjectFilesSheet = true },
            openContacts: { showContactsList = true },
            exportProjectPDF: { exportPDF(for: project) },
            openChecklistReport: { showChecklistReport = true },
            planDestination: {
                ProjectPlanView(projectID: project.id)
                    .environmentObject(store)
            },
            expensesDestination: {
                ProjectExpensesView(projectID: project.id)
                    .environmentObject(store)
            },
            issuesDestination: {
                ProjectIssuesListView(projectID: project.id)
            }
        )
    }

    // MARK: - Файлы проекта (мини-секция)

    private func filesMiniSection(_ project: Project) -> some View {

        let photos = project.photoPaths.count
        let docs = project.documentPaths.count
        let hasPDF = project.projectPDFPath != nil

        return VStack(alignment: .leading, spacing: 6) {

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    isFilesExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(ProjectUXColors.accentAction)
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Файлы проекта")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(ProjectUXColors.primaryText)
                        Text("Фото: \(photos) • Документы: \(docs) • PDF: \(hasPDF ? "есть" : "нет")")
                            .font(.caption)
                            .foregroundStyle(ProjectUXColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isFilesExpanded ? 180 : 0))
                        .foregroundStyle(ProjectUXColors.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isFilesExpanded {

                Divider()
                    .padding(.leading, 32)
                    .padding(.vertical, 4)

                Button {
                    showProjectFilesSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(ProjectUXColors.accentAction)
                        Text("Открыть файлы проекта")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(ProjectUXColors.primaryText)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(ProjectUXColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Секция задач проекта

    private func tasksSection(_ project: Project) -> some View {

        let allTasks = store.tasks(for: project.id)
        let activeTasks = allTasks.filter { !$0.isCompleted }

        let nearest = activeTasks.sorted { lhs, rhs in
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?):
                return l < r
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }.first

        return dashboardGlass(title: "Задачи проекта") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    taskSummary(nearest, hasAnyTasks: !allTasks.isEmpty)
                    Spacer(minLength: 8)
                    newTaskButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    taskSummary(nearest, hasAnyTasks: !allTasks.isEmpty)
                    newTaskButton
                }
            }
        }
    }

    @ViewBuilder
    private func taskSummary(_ task: TaskItem?, hasAnyTasks: Bool) -> some View {
        if let task {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = task.dueDate {
                    Text(taskDateState(date))
                        .font(.caption)
                        .foregroundStyle(taskDateColor(date))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(hasAnyTasks ? "Нет активных задач" : "Задач пока нет")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(ProjectUXColors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var newTaskButton: some View {
        Button {
            showQuickTaskForm = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                Text("Новая задача")
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(ProjectUXColors.accentAction.opacity(0.16))
            .foregroundStyle(ProjectUXColors.accentAction)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Новая задача")
    }

    private func taskDateState(_ date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: date)
        if due < today {
            return "Просрочена · \(dateString(date))"
        }
        if due == today {
            return "Сегодня · \(dateString(date))"
        }
        return dateString(date)
    }

    private func taskDateColor(_ date: Date) -> Color {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let due = cal.startOfDay(for: date)
        if due < today {
            return ProjectUXColors.overdue
        }
        return ProjectUXColors.secondaryText
    }

    // MARK: - Управление проектом

    private func managementSection(_ project: Project) -> some View {
        dashboardGlass(title: "Управление проектом") {

            NavigationLink {
                ProjectExpensesView(projectID: project.id)
                    .environmentObject(store)
            } label: {
                dashboardRow(
                    icon: "creditcard",
                    title: "Расходы проекта",
                    subtitle: "Контроль бюджета и затрат",
                    trailing: AnyView(Image(systemName: "chevron.right"))
                )
            }

            Divider().padding(.leading, 40)

            Button {
                exportPDF(for: project)
            } label: {
                dashboardRow(
                    icon: "doc.richtext",
                    title: "Экспорт отчёта в PDF",
                    subtitle: "Сводка по объекту, расходам, чек-листам",
                    trailing: AnyView(Image(systemName: "square.and.arrow.up"))
                )
            }

            Divider().padding(.leading, 40)

            Button {
                showChecklistReport = true
            } label: {
                dashboardRow(
                    icon: "checklist",
                    title: "Отчёт по чек-листам",
                    subtitle: "Текущее состояние рабочих чек-листов",
                    trailing: AnyView(Image(systemName: "chevron.right"))
                )
            }
            .accessibilityIdentifier("project.checklistReport.entry")
            .accessibilityLabel("Отчёт по чек-листам")
        }
    }

    // MARK: - Контакты

    private func contactsSection(_ project: Project) -> some View {

        let favorites = project.contacts
            .filter { $0.isFavorite }
            .sorted { $0.name < $1.name }

        return dashboardGlass(title: "Важные контакты") {

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    areContactsExpanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundColor(.primary)

                    Text(contactsSummary(favorites))
                        .font(.body.weight(.medium))

                    Spacer()

                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(areContactsExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if areContactsExpanded {

                Divider().padding(.leading, 40)

                if favorites.isEmpty {
                    Button { showContactsList = true } label: {
                        dashboardRow(
                            icon: "person.crop.circle.badge.plus",
                            title: "Добавить контакт",
                            subtitle: "Создать первый контакт"
                        )
                    }
                } else {

                    ForEach(favorites) { contact in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {

                                HStack(spacing: 6) {
                                    Text(contact.name)
                                        .font(.subheadline.weight(.medium))
                                    if contact.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                            .font(.caption)
                                    }
                                }

                                if !contact.role.isEmpty {
                                    Text(contact.role)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }

                                Text(contact.phone)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button { call(contact.phone) } label: {
                                Image(systemName: "phone.fill")
                                    .foregroundColor(.primary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Позвонить")
                        }
                        .padding(.vertical, 4)

                        Divider().padding(.leading, 40)
                    }

                    Button { showContactsList = true } label: {
                        dashboardRow(
                            icon: "book",
                            title: "Открыть записную книжку",
                            subtitle: "",
                            trailing: AnyView(Image(systemName: "chevron.right"))
                        )
                    }
                }
            }
        }
    }

    private func contactsSummary(_ arr: [ProjectContact]) -> String {
        if arr.isEmpty { return "Контакты не заданы" }
        if arr.count == 1 { return arr[0].name }
        if arr.count == 2 { return "\(arr[0].name), \(arr[1].name)" }
        return "\(arr[0].name), \(arr[1].name) +\(arr.count - 2)"
    }

    // MARK: - Замечания

    private func issuesSection(_ project: Project) -> some View {
        let count = issues.count

        return NavigationLink {
            ProjectIssuesListView(projectID: project.id)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.issue)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Требует внимания")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ProjectUXColors.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ProjectIssuesFormatting.remarksPhrase(count))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ProjectUXColors.issue)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(ProjectUXColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ProjectIssuesFormatting.dashboardAccessibilityLabel(count: count))
        .accessibilityHint("Открывает список замечаний")
        .accessibilityIdentifier("project.issues.entry")
        .accessibilityAddTraits(.isButton)
    }

    private func reloadIssues() {
        issuesLoadGeneration += 1
        let generation = issuesLoadGeneration
        let pid = projectID
        Task.detached(priority: .userInitiated) {
            let result = ProjectIssuesCollector.issues(for: pid)
            await MainActor.run {
                guard generation == issuesLoadGeneration else { return }
                issues = result
            }
        }
    }

    // MARK: - Секция чек-листов проекта

    private func stagesSection(_ project: Project) -> some View {

        _ = progressVersion // триггер перерисовки

        return VStack(alignment: .leading, spacing: 16) {
            Text("Ход строительства")
                .font(.headline)

            VStack(spacing: 0) {

                stageRow(
                    pack: .geology,
                    title: "Геология и подготовка участка",
                    subtitle: "Отчёт, топосъёмка, подготовка площадки",
                    measurement: packMeasurement(GeologyProgressStore.load, project: project),
                    showsConnector: true
                ) { GeologyStagesScreen(project: project) }

                stageRow(
                    pack: .foundation,
                    title: "Фундамент",
                    subtitle: "Тип основания, подушка, армирование",
                    measurement: packMeasurement(FoundationProgressStore.load, project: project),
                    showsConnector: true
                ) { FoundationStagesScreen(project: project) }

                stageRow(
                    pack: .walls,
                    title: "Стены",
                    subtitle: "Кладка, армопояса, облицовка",
                    measurement: packMeasurement(WallsProgressStore.load, project: project),
                    showsConnector: true
                ) { WallsStagesScreen(project: project) }

                stageRow(
                    pack: .slab,
                    title: "Перекрытия",
                    subtitle: "Монолит, плиты, деревянные",
                    measurement: packMeasurement(SlabProgressStore.load, project: project),
                    showsConnector: true
                ) { SlabStagesScreen(project: project) }

                stageRow(
                    pack: .roof,
                    title: "Крыша",
                    subtitle: "Стропила, плёнки, обрешётка",
                    measurement: packMeasurement(RoofProgressStore.load, project: project),
                    showsConnector: true
                ) { RoofStagesScreen(project: project) }

                stageRow(
                    pack: .roofCover,
                    title: "Покрытие крыши",
                    subtitle: "Черепица, металл, доборные элементы",
                    measurement: packMeasurement(RoofCoverProgressStore.load, project: project),
                    showsConnector: true
                ) { RoofCoverStagesScreen(project: project) }

                stageRow(
                    pack: .engineering,
                    title: "Инженерия",
                    subtitle: "Электрика, отопление, вода, канализация",
                    measurement: packMeasurement(EngineeringProgressStore.load, project: project),
                    showsConnector: true
                ) { EngineeringStagesScreen(project: project) }

                stageRow(
                    pack: .windows,
                    title: "Окна",
                    subtitle: "Замер, монтаж, регулировка, примыкания",
                    measurement: packMeasurement(WindowsProgressStore.load, project: project),
                    showsConnector: true
                ) { WindowsStagesScreen(project: project) }

                stageRow(
                    pack: .doors,
                    title: "Двери",
                    subtitle: "Коробка, порог, примыкания, фурнитура",
                    measurement: packMeasurement(DoorsProgressStore.load, project: project),
                    showsConnector: true
                ) { DoorsStagesScreen(project: project) }

                stageRow(
                    pack: .finishing,
                    title: "Отделка",
                    subtitle: "Черновая и чистовая",
                    measurement: packMeasurement(FinishingProgressStore.load, project: project),
                    showsConnector: true
                ) { FinishingStagesScreen(project: project) }

                stageRow(
                    pack: .landscaping,
                    title: "Благоустройство",
                    subtitle: "Дороги, ливнёвка, заборы",
                    measurement: packMeasurement(LandscapingProgressStore.load, project: project),
                    showsConnector: false
                ) { LandscapingStagesScreen(project: project) }
            }
        }
    }

    // MARK: - Одна строка этапа

    /// One `load` per pack. Percent, N of M and issue count all come from that result.
    private func packMeasurement(
        _ loader: (UUID) -> [Stage]?,
        project: Project
    ) -> ChecklistPackMeasurement {
        ChecklistPackMeasurement.measure(loader(project.id))
    }

    @ViewBuilder
    private func stageRow<Destination: View>(
        pack: ChecklistPack,
        title: String,
        subtitle: String,
        measurement: ChecklistPackMeasurement,
        showsConnector: Bool,
        destination: @escaping () -> Destination
    ) -> some View {
        ChecklistPackTimelineRow(
            title: title,
            subtitle: subtitle,
            measurement: measurement,
            showsConnector: showsConnector,
            accessibilityIdentifier: "project.checklistPack.\(pack.rawValue)",
            destination: destination
        )
    }

    // MARK: - PDF Export

    private func exportPDF(for project: Project) {
        let service = PDFReportService()
        let expenses = store.expenses(for: project.id)
        let stages = project.stages

        do {
            let url = try service.makeProjectReport(
                project: project,
                stages: stages,
                expenses: expenses
            )
            reportURL = url
            showShareSheet = true
        } catch {
            print("❌ PDF report error:", error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func call(_ num: String) {
        guard let url = URL(string: "tel://\(num)") else { return }
        UIApplication.shared.open(url)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }
}

// MARK: - Быстрая форма задачи для конкретного проекта

struct ProjectQuickTaskForm: View {

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var hasDueDate: Bool = true
    @State private var dueDate: Date = Date()
    @State private var errorText: String?

    var body: some View {
        Form {
            Section("Задача") {
                TextField("Что нужно сделать", text: $title)

                TextField("Подробности (необязательно)", text: $details, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section("Срок") {
                Toggle("Указать срок", isOn: $hasDueDate)

                if hasDueDate {
                    DatePicker(
                        "Дата",
                        selection: $dueDate,
                        displayedComponents: [.date]
                    )
                }
            }

            if let errorText {
                Section("Ошибка") {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle("Новая задача")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            errorText = "Введите название задачи."
            return
        }

        do {
            try store.addTask(
                title: trimmedTitle,
                details: details.isEmpty ? nil : details,
                projectID: projectID,
                dueDate: hasDueDate ? dueDate : nil
            )
            dismiss()
        } catch {
            errorText = "Не удалось сохранить задачу: \(error.localizedDescription)"
        }
    }
}

// MARK: - Glass Card Wrapper

private func dashboardGlass<Content: View>(
    title: String,
    @ViewBuilder content: () -> Content
) -> some View {

    VStack(alignment: .leading, spacing: 14) {

        Text(title)
            .font(.headline)

        VStack(spacing: 0) {
            content()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - Dashboard Row (чёрные, жирные иконки)

private func dashboardRow(
    icon: String,
    title: String,
    subtitle: String,
    trailing: AnyView? = nil
) -> some View {

    HStack(spacing: 14) {

        Image(systemName: icon)
            .font(.title3.weight(.bold))
            .foregroundColor(.primary)

        VStack(alignment: .leading, spacing: 2) {

            Text(title)
                .font(.body.weight(.medium))

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Spacer()

        if let trailing {
            trailing
                .foregroundStyle(.secondary)
                .font(.caption)
        }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }

// MARK: - Экран списка контактов проекта

struct ProjectContactsListView: View {

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var showingEditor = false
    @State private var contactToEdit: ProjectContact?
    @State private var errorText: String?
    @State private var query = ""

    private var project: Project? {
        store.projects.first(where: { $0.id == projectID })
    }

    private var sortedContacts: [ProjectContact] {
        guard let project else { return [] }
        return project.contacts.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var visibleContacts: [ProjectContact] {
        let sorted = sortedContacts
        guard !ProjectContactSearch.normalizedQuery(query).isEmpty else { return sorted }
        return sorted.filter { ProjectContactSearch.matches($0, query: query) }
    }

    var body: some View {

        List {

            if project?.contacts.isEmpty != false {

                Text("Контакты не добавлены")
                    .foregroundStyle(.secondary)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("project.contacts.empty")

            } else if visibleContacts.isEmpty {

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ничего не найдено")
                        .font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Попробуйте изменить запрос.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Ничего не найдено. Попробуйте изменить запрос.")
                .accessibilityIdentifier("project.contacts.emptyResults")

            } else {

                ForEach(visibleContacts) { contact in

                    HStack(alignment: .top, spacing: 12) {

                        VStack(alignment: .leading, spacing: 4) {

                            HStack(spacing: 6) {
                                Text(contact.name)
                                    .font(.headline)
                                if contact.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                }
                            }

                            if !contact.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(contact.role)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Button {
                                callPhone(contact.phone)
                            } label: {
                                Text(contact.phone)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 8)

                        Button {
                            contactToEdit = contact
                            showingEditor = true
                        } label: {
                            Image(systemName: "pencil")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete(perform: deleteContacts)
            }
        }
        .navigationTitle("Контакты проекта")
        .searchable(text: $query, prompt: "Поиск контактов")
        .accessibilityIdentifier("project.contacts.list")
        .toolbar {

            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    contactToEdit = nil
                    showingEditor = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }

        .alert("Ошибка", isPresented: .constant(errorText != nil)) {
            Button("OK") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }

        .sheet(isPresented: $showingEditor) {
            NavigationStack {
                ContactEditorView(projectID: projectID, contact: contactToEdit)
                    .environmentObject(store)
            }
        }
    }

    // Delete contacts

    private func deleteContacts(at offsets: IndexSet) {
        let ids = offsets.compactMap { index -> UUID? in
            guard visibleContacts.indices.contains(index) else { return nil }
            return visibleContacts[index].id
        }

        for id in ids {
            guard let contact = project?.contacts.first(where: { $0.id == id }) else { continue }
            do {
                try store.deleteContact(contact, from: projectID)
            } catch {
                errorText = "Не удалось удалить контакт: \(error.localizedDescription)"
            }
        }
    }

    private func callPhone(_ num: String) {
        let cleaned = num.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, let url = URL(string: "tel://\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }
}

/// In-memory contact search. Does not write contacts or change stored phone strings.
enum ProjectContactSearch {
    static func normalizedQuery(_ query: String) -> String {
        normalizeText(query)
    }

    static func matches(_ contact: ProjectContact, query: String) -> Bool {
        let textQuery = normalizeText(query)
        guard !textQuery.isEmpty else { return true }

        if textMatches(contact.name, textQuery) { return true }
        if textMatches(contact.role, textQuery) { return true }
        if let note = contact.note, textMatches(note, textQuery) { return true }

        let queryDigits = digits(query)
        guard queryDigits.count >= 3 else { return false }
        if textMatches(contact.phone, textQuery) { return true }
        return phoneMatches(stored: contact.phone, queryDigits: queryDigits)
    }

    private static func textMatches(_ field: String, _ query: String) -> Bool {
        normalizeText(field).localizedStandardContains(query)
    }

    private static func normalizeText(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    private static func digits(_ value: String) -> String {
        value.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    /// Comparison keys only. An 11-digit number starting with 8 is also matched as 7.
    private static func phoneKeys(_ digitString: String) -> [String] {
        var keys = [digitString]
        if digitString.count == 11, digitString.hasPrefix("8") {
            let asSeven = "7" + digitString.dropFirst()
            keys.append(asSeven)
            keys.append(String(asSeven.dropFirst()))
        } else if digitString.count == 11, digitString.hasPrefix("7") {
            keys.append(String(digitString.dropFirst()))
        }
        return keys
    }

    private static func phoneMatches(stored: String, queryDigits: String) -> Bool {
        let storedDigits = digits(stored)
        guard storedDigits.count >= 3 else { return false }
        let storedKeys = phoneKeys(storedDigits)
        let queryKeys = phoneKeys(queryDigits)
        for storedKey in storedKeys {
            for queryKey in queryKeys where storedKey.contains(queryKey) {
                return true
            }
        }
        return false
    }
}

// MARK: - Редактор контакта

struct ContactEditorView: View {

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let contactToEdit: ProjectContact?

    @State private var name: String
    @State private var role: String
    @State private var phone: String
    @State private var note: String
    @State private var isFavorite: Bool
    @State private var errorText: String?

    private var isEditing: Bool {
        contactToEdit != nil
    }

    init(projectID: UUID, contact: ProjectContact?) {
        self.projectID = projectID
        self.contactToEdit = contact

        _name = State(initialValue: contact?.name ?? "")
        _role = State(initialValue: contact?.role ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _note = State(initialValue: contact?.note ?? "")
        _isFavorite = State(initialValue: contact?.isFavorite ?? false)
    }

    var body: some View {

        Form {

            Section("Основное") {
                TextField("Имя", text: $name)
                TextField("Роль (заказчик, прораб…)", text: $role)
                TextField("Телефон", text: $phone)
                    .keyboardType(.phonePad)
            }

            Section("Дополнительно") {
                TextField("Заметка", text: $note, axis: .vertical)
                    .lineLimit(1...4)

                Toggle("Избранный контакт", isOn: $isFavorite)
            }

            if let errorText {
                Section("Ошибка") {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }

        .navigationTitle(isEditing ? "Редактировать контакт" : "Новый контакт")
        .navigationBarTitleDisplayMode(.inline)

        .toolbar {

            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { save() }
                    .disabled(
                        name.trimmingCharacters(in: .whitespaces).isEmpty ||
                        phone.trimmingCharacters(in: .whitespaces).isEmpty
                    )
            }
        }
    }

    // MARK: - Save contact

    private func save() {

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty, !trimmedPhone.isEmpty else {
            errorText = "Имя и телефон обязательны."
            return
        }

        do {

            if var contact = contactToEdit {

                contact.name = trimmedName
                contact.role = role
                contact.phone = trimmedPhone
                contact.note = note.isEmpty ? nil : note
                contact.isFavorite = isFavorite

                try store.updateContact(contact, in: projectID)

            } else {

                let new = ProjectContact(
                    id: UUID(),
                    name: trimmedName,
                    role: role,
                    phone: trimmedPhone,
                    note: note.isEmpty ? nil : note,
                    isFavorite: isFavorite
                )

                try store.addContact(new, to: projectID)
            }

            dismiss()

        } catch {
            errorText = "Не удалось сохранить контакт: \(error.localizedDescription)"
        }
    }
}
