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

                        // Верхняя карточка с прогрессом проекта
                        headerCard(project)

                        // Задачи проекта
                        tasksSection(project)

                        // Управление проектом
                        managementSection(project)

                        // Контакты
                        contactsSection(project)

                        // Замечания рабочих чек-листов
                        issuesSection(project)

                        // Чек-листы
                        stagesSection(project)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .navigationTitle(project.name)
                .navigationBarTitleDisplayMode(.inline)

                .sheet(isPresented: $showShareSheet) {
                    if let url = reportURL {
                        ShareSheet(activityItems: [url])
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

        // Считаем прогресс так же, как в ProjectsListView.overallProgress(for:)
        let projectProgress = overallProgress(for: project)
        let percentage = Int((projectProgress * 100).rounded())

        return VStack(alignment: .leading, spacing: 18) {

            // Заголовок + проценты справа
            HStack(alignment: .top) {

                VStack(alignment: .leading, spacing: 4) {

                    Text(project.name)
                        .font(.title3.weight(.semibold))

                    // Адрес
                    if !project.address.isEmpty {
                        Text(project.address)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Ответственный (manager)
                    if let manager = project.manager, !manager.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("Ответственный: \(manager)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Процент выполнения
                HStack(spacing: 4) {
                    Text("\(percentage)%")
                        .font(.title3.weight(.bold))
                        .foregroundColor(colorForProjectProgress(projectProgress))

                    if percentage == 100 {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    }
                }
            }

            // Общий прогресс-бар по проекту
            ProgressView(value: projectProgress)
                .tint(colorForProjectProgress(projectProgress))
                .scaleEffect(x: 1, y: 1.3, anchor: .center)
                .padding(.trailing, 4)

            // Даты + статус срока + файлы
            VStack(alignment: .leading, spacing: 10) {

                HStack(spacing: 12) {

                    if let start = project.dateStart {
                        datePill(text: dateString(start),
                                 icon: "calendar")
                    }

                    if let end = project.dateEnd {
                        datePill(text: dateString(end),
                                 icon: "calendar.badge.clock")
                    }

                    Spacer()

                    if let end = project.dateEnd,
                       let status = deadlineStatus(end) {
                        Text(status.text)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(status.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(status.color.opacity(0.1))
                            )
                    }
                }

                filesMiniSection(project)
            }

        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    // MARK: - Даты / статус

    private func datePill(text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.systemGray6))
            .clipShape(Capsule())
    }

    private func deadlineStatus(_ endDate: Date) -> (text: String, color: Color)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: endDate)
        let diff = cal.dateComponents([.day], from: today, to: target).day ?? 0

        if diff > 0 {
            return ("Осталось \(diff) дн.", Color("AccentYellow"))
        } else if diff == 0 {
            return ("Срок сегодня", Color("AccentYellow"))
        } else {
            return ("Просрочено на \(abs(diff)) дн.", .red)
        }
    }

    // MARK: - Цвет прогресса проекта

    private func colorForProjectProgress(_ value: Double) -> Color {
        switch value {
        case 0..<0.33:
            return .red
        case 0.33..<0.66:
            return Color("AccentYellow")
        case 0.66..<0.999:
            return .green
        default:
            return .green
        }
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
                        .foregroundColor(Color("AccentYellow"))
                        .font(.subheadline)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Файлы проекта")
                            .font(.subheadline.weight(.medium))
                        Text("Фото: \(photos) • Документы: \(docs) • PDF: \(hasPDF ? "есть" : "нет")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isFilesExpanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
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
                            .foregroundColor(Color("AccentYellow"))
                        Text("Открыть файлы проекта")
                            .font(.caption.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Секция задач проекта

    private func tasksSection(_ project: Project) -> some View {

        let allTasks = store.tasks(for: project.id)
        let activeTasks = allTasks.filter { !$0.isCompleted }
        let completedTasks = allTasks.count - activeTasks.count

        // ближайшие 3 задачи по дате
        let upcomingSlice = activeTasks.sorted { lhs, rhs in
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
        }.prefix(3)
        let upcoming = Array(upcomingSlice)

        return dashboardGlass(title: "Задачи проекта") {

            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .center, spacing: 12) {

                    VStack(alignment: .leading, spacing: 4) {
                        if allTasks.isEmpty {
                            Text("Задач пока нет")
                                .font(.subheadline.weight(.medium))
                            Text("Создайте первую задачу для этого объекта.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Активные: \(activeTasks.count)")
                                .font(.subheadline.weight(.medium))
                            Text("Завершённые: \(completedTasks)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button {
                        showQuickTaskForm = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("Новая задача")
                        }
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if !upcoming.isEmpty {

                    Divider()
                        .padding(.top, 6)
                        .padding(.bottom, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ближайшие задачи")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        ForEach(upcoming) { task in
                            HStack(alignment: .top, spacing: 8) {

                                Image(systemName: "checklist")
                                    .font(.caption)
                                    .foregroundColor(.primary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title)
                                        .font(.subheadline)

                                    if let date = task.dueDate {
                                        Text(dateString(date))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()
                            }
                        }
                    }
                }
            }
        }
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
                            }
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
        let hasIssues = count > 0

        return NavigationLink {
            ProjectIssuesListView(projectID: project.id)
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: hasIssues ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(hasIssues ? Color.orange : Color.green)
                    .accessibilityHidden(true)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    if hasIssues {
                        Text("Требуют внимания")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Замечания: \(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Замечаний нет")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
            Text("Чек-листы проекта")
                .font(.headline)

            VStack(spacing: 18) {

                stageRow(
                    title: "Геология и подготовка участка",
                    subtitle: "Отчёт, топосъёмка, подготовка площадки",
                    progress: stageProgress(for: project, GeologyProgressStore.load),
                    project: project
                ) { GeologyStagesScreen(project: project) }

                stageRow(
                    title: "Фундамент",
                    subtitle: "Тип основания, подушка, армирование",
                    progress: stageProgress(for: project, FoundationProgressStore.load),
                    project: project
                ) { FoundationStagesScreen(project: project) }

                stageRow(
                    title: "Стены",
                    subtitle: "Кладка, армопояса, облицовка",
                    progress: stageProgress(for: project, WallsProgressStore.load),
                    project: project
                ) { WallsStagesScreen(project: project) }

                stageRow(
                    title: "Перекрытия",
                    subtitle: "Монолит, плиты, деревянные",
                    progress: stageProgress(for: project, SlabProgressStore.load),
                    project: project
                ) { SlabStagesScreen(project: project) }

                stageRow(
                    title: "Крыша",
                    subtitle: "Стропила, плёнки, обрешётка",
                    progress: stageProgress(for: project, RoofProgressStore.load),
                    project: project
                ) { RoofStagesScreen(project: project) }

                stageRow(
                    title: "Покрытие крыши",
                    subtitle: "Черепица, металл, доборные элементы",
                    progress: stageProgress(for: project, RoofCoverProgressStore.load),
                    project: project
                ) { RoofCoverStagesScreen(project: project) }

                stageRow(
                    title: "Инженерия",
                    subtitle: "Электрика, отопление, вода, канализация",
                    progress: stageProgress(for: project, EngineeringProgressStore.load),
                    project: project
                ) { EngineeringStagesScreen(project: project) }

                stageRow(
                    title: "Окна",
                    subtitle: "Замер, монтаж, регулировка, примыкания",
                    progress: stageProgress(for: project, WindowsProgressStore.load),
                    project: project
                ) { WindowsStagesScreen(project: project) }

                stageRow(
                    title: "Двери",
                    subtitle: "Коробка, порог, примыкания, фурнитура",
                    progress: stageProgress(for: project, DoorsProgressStore.load),
                    project: project
                ) { DoorsStagesScreen(project: project) }

                stageRow(
                    title: "Отделка",
                    subtitle: "Черновая и чистовая",
                    progress: stageProgress(for: project, FinishingProgressStore.load),
                    project: project
                ) { FinishingStagesScreen(project: project) }

                stageRow(
                    title: "Благоустройство",
                    subtitle: "Дороги, ливнёвка, заборы",
                    progress: stageProgress(for: project, LandscapingProgressStore.load),
                    project: project
                ) { LandscapingStagesScreen(project: project) }
            }
        }
    }

    // MARK: - Одна строка этапа

    @ViewBuilder
    private func stageRow<Destination: View>(
        title: String,
        subtitle: String,
        progress: Double,
        project: Project,
        destination: @escaping () -> Destination
    ) -> some View {

        let clamped = max(0, min(progress, 1))
        let percent = Int((clamped * 100).rounded())
        let isCompleted = clamped >= 0.999

        // Цвет шкалы прогресса
        let barColor: Color = isCompleted ? .green : Color("AccentYellow")

        // Цвет точки таймлайна
        let timelineColor: Color = {
            if isCompleted { return .green }
            if clamped > 0 { return Color("AccentYellow") }
            return Color(.systemGray4)
        }()

        HStack(alignment: .top, spacing: 14) {

            // Точка + линия таймлайна
            VStack(spacing: 0) {
                Circle()
                    .fill(timelineColor)
                    .frame(width: 15, height: 15)
                    .overlay(
                        Group {
                            if isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            } else {
                                Circle()
                                    .stroke(Color(.systemBackground), lineWidth: 2)
                            }
                        }
                    )

                Rectangle()
                    .fill(timelineColor.opacity(0.5))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 22)

            // Карточка этапа
            NavigationLink(destination: destination()) {
                VStack(alignment: .leading, spacing: 8) {

                    Text(title)
                        .font(.subheadline.weight(.semibold))

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {

                        HStack {
                            Text("\(percent)% готово")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }

                        ProgressView(value: clamped)
                            .tint(barColor)
                    }
                    .padding(.top, 2)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                .foregroundColor(.primary.opacity(0.05))
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Расчёт прогресса одного блока этапов

    private func stageProgress(
        for project: Project,
        _ loader: (UUID) -> [Stage]?
    ) -> Double {

        let projectID = project.id
        guard let stages = loader(projectID), !stages.isEmpty else { return 0 }

        let items = stages.flatMap { $0.items }
        guard !items.isEmpty else { return 0 }

        let done = items.filter { $0.status == .ok }.count
        return Double(done) / Double(items.count)
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
