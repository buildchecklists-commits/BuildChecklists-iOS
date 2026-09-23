import SwiftUI
import PDFKit
import UIKit

// MARK: - Filter & Sort Types

private enum ProjectFilter: String, CaseIterable, Identifiable {
    case all
    case current
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .current: return "Текущие"
        case .completed: return "Завершённые"
        }
    }
}

private enum ProjectSort: String, CaseIterable, Identifiable {
    case manual
    case name
    case date
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Ручная"
        case .name: return "По имени"
        case .date: return "По дате"
        case .progress: return "По прогрессу"
        }
    }

    var iconName: String {
        switch self {
        case .manual: return "arrow.up.arrow.down"
        case .name: return "textformat"
        case .date: return "calendar"
        case .progress: return "chart.bar.fill"
        }
    }
}

// MARK: - Projects List View

struct ProjectsListView: View {
    @EnvironmentObject var store: AppStore

    @State private var query: String = ""
    @State private var showForm: Bool = false
    @State private var errorText: String?

    @State private var progressCache: [UUID: Double] = [:]

    @State private var selectedFilter: ProjectFilter = .all
    @State private var selectedSort: ProjectSort = .manual

    // Expenses
    @State private var showExpenses: Bool = false
    @State private var selectedProjectID: UUID?

    // Files sheet (общий экран файлов)
    @State private var filesProject: Project?

    // Отдельные экраны
    @State private var photosProject: Project?
    @State private var pdfProject: Project?

    // Edit
    @State private var editingProject: Project?

    // Регистрация из демо-баннера
    @State private var showRegister: Bool = false

    // Калькулятор (MVP, без сохранения)
    @State private var showCalculator: Bool = false
    // DEMO coachmark (только для текущей сессии)
    @State private var showDemoCoachmark: Bool = false
    @State private var didDismissDemoCoachmark: Bool = false

    private let gridColumns: [GridItem] = [
        GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 16)
    ]

    private var projectsWithProgress: [(project: Project, progress: Double)] {
        let base: [(Project, Double)] = store.projects.map { project in
            let progress = progressCache[project.id] ?? overallProgress(for: project)
            return (project, progress)
        }

        let searched = base.filter { pair in
            guard !query.isEmpty else { return true }
            let p = pair.0
            return p.name.localizedCaseInsensitiveContains(query) ||
                   p.address.localizedCaseInsensitiveContains(query)
        }

        let filtered = searched.filter { pair in
            let progress = pair.1
            switch selectedFilter {
            case .all: return true
            case .current: return progress < 1.0
            case .completed: return progress >= 1.0
            }
        }

        let sorted: [(Project, Double)]
        switch selectedSort {
        case .manual:
            sorted = filtered
        case .name:
            sorted = filtered.sorted {
                $0.0.name.localizedCompare($1.0.name) == .orderedAscending
            }
        case .date:
            func key(_ p: Project) -> Date {
                if let d = p.lastUpdated { return d }
                if let d = p.dateStart { return d }
                return .distantPast
            }
            sorted = filtered.sorted { key($0.0) > key($1.0) }
        case .progress:
            sorted = filtered.sorted { $0.1 > $1.1 }
        }

        return sorted
    }

    private var currentProjects: [(project: Project, progress: Double)] {
        projectsWithProgress.filter { $0.progress < 1.0 }
    }

    private var completedProjects: [(project: Project, progress: Double)] {
        projectsWithProgress.filter { $0.progress >= 1.0 }
    }

    private var highlightedDemoProjectID: UUID? {
        projectsWithProgress.first?.project.id
    }

    private var shouldShowDemoCoachmark: Bool {
        showDemoCoachmark && store.isDemoMode && !store.projects.isEmpty
    }

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle("Мои проекты")
        .searchable(text: $query, prompt: "Поиск по проектам…")
        .sheet(isPresented: $showForm) {
            ProjectFormView().environmentObject(store)
        }
        .sheet(item: $editingProject) { project in
            EditProjectView(project: project).environmentObject(store)
        }
        // Expenses sheet
        .sheet(isPresented: $showExpenses) {
            if let id = selectedProjectID {
                NavigationStack {
                    ProjectExpensesView(projectID: id)
                        .environmentObject(store)
                }
            }
        }
        // Общий экран файлов
        .sheet(item: $filesProject) { project in
            NavigationStack {
                ProjectFilesView(projectID: project.id)
                    .environmentObject(store)
            }
        }
        // Экран фото проекта
        .sheet(item: $photosProject) { project in
            NavigationStack {
                ProjectPhotosView(projectID: project.id)
                    .environmentObject(store)
            }
        }
        // Экран PDF-проекта
        .sheet(item: $pdfProject) { project in
            NavigationStack {
                ProjectPDFView(projectID: project.id)
                    .environmentObject(store)
            }
        }
        // Регистрация из демо-баннера
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(store)
        }
        // Калькулятор
        .sheet(isPresented: $showCalculator) {
            NavigationStack {
                CalculatorHomeView()
            }
        }

        // ✅ ИСПРАВЛЕНО: был "Ошибка" + .constant (алерт не управляемый)
        // Теперь заголовок бизнес-логики: "Доступ ограничен"
        .alert("Доступ ограничен", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }

        .onAppear {
            recalcAllProjectsProgress(animated: false)
            updateDemoCoachmarkVisibility()
        }
        .onChange(of: store.projects) { _, _ in
            recalcAllProjectsProgress(animated: true)
            updateDemoCoachmarkVisibility()
        }
        .onChange(of: store.isDemoMode) { _, isDemo in
            if isDemo {
                updateDemoCoachmarkVisibility()
            } else {
                showDemoCoachmark = false
                didDismissDemoCoachmark = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bcProgressDidChange)) { _ in
            recalcAllProjectsProgress(animated: true)
        }
        .overlay {
            if shouldShowDemoCoachmark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowDemoCoachmark {
                demoCoachmark
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
    }

    // MARK: - Access guard (read-only)

    private func requireWritableAccess(_ actionName: String) -> Bool {
        // В демо можно всё (но не сохраняется) — это ок по твоей логике.
        // В read-only (нет/истекла подписка) — блокируем любые изменения.
        if store.isReadOnlyMode && !store.isDemoMode {
            errorText = "Доступ только для просмотра. Чтобы \(actionName), оформите или продлите подписку."
            return false
        }
        return true
    }

    // MARK: - Subviews

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Text("Нет проектов")
                .font(.title3.weight(.semibold))

            Text("Создайте первый проект, чтобы начать контроль строительства.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                guard requireWritableAccess("создавать проекты") else { return }
                showForm = true
            } label: {
                Label("Новый проект", systemImage: "plus")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 4)

            if store.isDemoMode {
                demoBanner
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(ProjectUXColors.screenBackground)
    }

    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                controlsView

                if !currentProjects.isEmpty {
                    sectionHeader(title: "Текущие проекты")

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        ForEach(currentProjects, id: \.project.id) { pair in
                            projectRow(
                                pair.project,
                                progress: pair.progress,
                                isDemoHighlighted: shouldShowDemoCoachmark && pair.project.id == highlightedDemoProjectID
                            )
                        }
                    }
                }

                if !completedProjects.isEmpty {
                    Divider().padding(.vertical, 4)

                    sectionHeader(title: "Завершённые")

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        ForEach(completedProjects, id: \.project.id) { pair in
                            projectRow(
                                pair.project,
                                progress: pair.progress,
                                isDemoHighlighted: shouldShowDemoCoachmark && pair.project.id == highlightedDemoProjectID
                            )
                        }
                    }
                }

                // В демо-режиме — аккуратный баннер внизу списка
                if store.isDemoMode {
                    demoBanner
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(ProjectUXColors.screenBackground)
    }

    private var controlsView: some View {
        VStack(spacing: 8) {
            Picker("Фильтр", selection: $selectedFilter) {
                ForEach(ProjectFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .center, spacing: 8) {
                // LEFT: сортировка
                Menu {
                    ForEach(ProjectSort.allCases) { sort in
                        Button { selectedSort = sort } label: {
                            Label(sort.title, systemImage: sort.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedSort.iconName)

                        Text(selectedSort.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                }

                Spacer(minLength: 8)

                // CENTER: калькулятор — компактный pill как “Ручная”, без иконки
                Button {
                    showCalculator = true
                } label: {
                    Text("Калькулятор")
                        .font(.subheadline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
                        )
                        .foregroundStyle(ProjectUXColors.accentAction)
                        .accessibilityLabel("Калькулятор")
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                // RIGHT: новый проект
                Text("Новый проект")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Button {
                    guard requireWritableAccess("создавать проекты") else { return }
                    showForm = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .padding(10)
                        .background(ProjectUXColors.accentAction.opacity(0.18))
                        .foregroundStyle(ProjectUXColors.accentAction)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                TasksCenterView()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Календарь задач")
                            .font(.subheadline.weight(.semibold))

                        Text("Напоминания: купить материалы, заказать бетон и т.д.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
        }
    }

    // MARK: - Демо-баннер

    @ViewBuilder
    private var demoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.subheadline)
                    .foregroundStyle(ProjectUXColors.accentAction)

                Text("Демо-режим")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Проекты не сохраняются после закрытия приложения. Создайте профиль, чтобы фиксировать стройки и работать без ограничений.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showRegister = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Создать профиль")
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(ProjectUXColors.accentAction)
                .foregroundStyle(ProjectUXColors.onAccent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(ProjectUXColors.accentAction.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
        )
    }

    private var demoCoachmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ProjectUXColors.accentAction)
                Text("Демонстрационный проект")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    dismissDemoCoachmark()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Откройте проект и посмотрите, как приложение помогает контролировать этапы, сроки, расходы и фото. В DEMO его можно редактировать.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Понятно") {
                    dismissDemoCoachmark()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(ProjectUXColors.accentAction)
                .foregroundStyle(ProjectUXColors.onAccent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    // MARK: - projectRow

    private func projectRow(_ project: Project, progress: Double, isDemoHighlighted: Bool = false) -> some View {
        let progressPercent = Int((progress * 100).rounded())
        let isCompleted = progress >= 1.0

        let photosCount = project.photoPaths.count
        let docsCount = project.documentPaths.count
        let hasProjectPDF = project.projectPDFPath != nil

        let coverImage = CoverImageStore.shared.loadCover(for: project.id)
        let issueCount = ProjectIssuesCollector.issues(for: project.id).count
        let deadline = projectDeadline(project.dateEnd, isComplete: isCompleted)
        let fallbackInk = projectCardFallbackInk(colorName: project.cardColor)

        return ZStack(alignment: .topTrailing) {
            NavigationLink {
                ProjectDashboardView(projectID: project.id)
            } label: {
                ProjectCardView(
                    name: project.name,
                    address: project.address,
                    manager: project.manager,
                    description: project.description,
                    progress: progress,
                    progressPercent: progressPercent,
                    cardColorName: project.cardColor,
                    isCompleted: isCompleted,
                    coverImage: coverImage,
                    deadline: deadline,
                    issueCount: issueCount
                )
            }
            .buttonStyle(CardLinkStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(projectCardSummary(project, progressPercent: progressPercent, deadline: deadline, issueCount: issueCount))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("project.card.open")

            Button {
                startEdit(project)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("Ред.")
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
                .background {
                    Capsule().fill(coverImage == nil ? fallbackInk.opacity(0.10) : Color.black.opacity(0.46))
                }
                .foregroundStyle(coverImage == nil ? fallbackInk : Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 10)
            .accessibilityLabel("Редактировать проект")
            .accessibilityIdentifier("project.card.edit")
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                projectCardAction(
                    title: "Фото (\(photosCount))",
                    systemImage: "photo.on.rectangle",
                    accessibilityLabel: "Фото проекта",
                    identifier: "project.card.photos",
                    foreground: coverImage == nil ? fallbackInk : Color.white,
                    action: { photosProject = project }
                )
                projectCardAction(
                    title: "Документы (\(docsCount))",
                    compactTitle: "Док. (\(docsCount))",
                    systemImage: "doc.on.doc",
                    accessibilityLabel: "Документы проекта",
                    identifier: "project.card.documents",
                    foreground: coverImage == nil ? fallbackInk : Color.white,
                    action: { filesProject = project }
                )
                projectCardAction(
                    title: hasProjectPDF ? "Проект (PDF)" : "Проект",
                    systemImage: hasProjectPDF ? "doc.richtext" : "doc",
                    accessibilityLabel: hasProjectPDF ? "Проект, PDF" : "Проект",
                    identifier: "project.card.projectFile",
                    foreground: coverImage == nil ? fallbackInk : Color.white,
                    action: {
                        if project.projectPDFPath != nil {
                            pdfProject = project
                        } else {
                            filesProject = project
                        }
                    }
                )
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .overlay {
            if isDemoHighlighted {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(ProjectUXColors.accentAction, lineWidth: 2)
                    .shadow(color: ProjectUXColors.accentAction.opacity(0.35), radius: 10, x: 0, y: 0)
            }
        }
        .hoverEffect(.lift)
        .swipeActions(edge: .leading) {
            Button {
                selectedProjectID = project.id
                showExpenses = true
            } label: {
                Label("Расходы", systemImage: "creditcard")
            }
            .tint(.blue)
        }
        .contextMenu {
            Button {
                startEdit(project)
            } label: {
                Label("Редактировать", systemImage: "pencil")
            }

            Button(role: .destructive) {
                delete(project)
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func startEdit(_ project: Project) {
        guard requireWritableAccess("редактировать проекты") else { return }
        editingProject = project
    }

    private func delete(_ project: Project) {
        guard requireWritableAccess("удалять проекты") else { return }
        withAnimation {
            do { try store.deleteProject(project) }
            catch { errorText = error.localizedDescription }
        }
    }

    // MARK: - Progress Cache

    private func recalcAllProjectsProgress(animated: Bool) {
        var dict: [UUID: Double] = [:]
        for project in store.projects {
            dict[project.id] = overallProgress(for: project)
        }
        if animated {
            withAnimation { progressCache = dict }
        } else {
            progressCache = dict
        }
    }

    private func updateDemoCoachmarkVisibility() {
        guard store.isDemoMode else {
            showDemoCoachmark = false
            return
        }
        showDemoCoachmark = !didDismissDemoCoachmark && !store.projects.isEmpty
    }

    private func dismissDemoCoachmark() {
        didDismissDemoCoachmark = true
        withAnimation(.easeOut(duration: 0.2)) {
            showDemoCoachmark = false
        }
    }

    private func projectCardAction(
        title: String,
        compactTitle: String? = nil,
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                cardActionLabel(title, systemImage: systemImage)
                cardActionLabel(compactTitle ?? title, systemImage: systemImage)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }

    private func cardActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
        }
        .font(.caption2.weight(.semibold))
    }

    private func projectCardSummary(
        _ project: Project,
        progressPercent: Int,
        deadline: ProjectCardDeadline?,
        issueCount: Int
    ) -> String {
        var parts = [project.name]
        if !project.address.isEmpty {
            parts.append(project.address)
        }
        parts.append("Прогресс \(progressPercent) процентов")
        if let deadline {
            parts.append(deadline.text)
        }
        if issueCount > 0 {
            parts.append(ProjectIssuesFormatting.remarksPhrase(issueCount))
        }
        return parts.joined(separator: ", ")
    }

    private func projectDeadline(_ endDate: Date?, isComplete: Bool) -> ProjectCardDeadline? {
        guard let endDate else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: endDate)
        let diff = calendar.dateComponents([.day], from: today, to: target).day ?? 0
        if isComplete, diff < 0 {
            return ProjectCardDeadline(text: "Завершён", color: ProjectUXColors.progressComplete, readableOnCover: false)
        }
        if diff > 0 {
            return ProjectCardDeadline(text: "Осталось \(diff) \(dayWord(diff))", color: ProjectUXColors.secondaryText, readableOnCover: true)
        }
        if diff == 0 {
            return ProjectCardDeadline(text: "Сегодня", color: ProjectUXColors.progressActive, readableOnCover: true)
        }
        return ProjectCardDeadline(
            text: "Просрочено на \(abs(diff)) \(dayWord(abs(diff)))",
            color: ProjectUXColors.overdue,
            readableOnCover: false
        )
    }

    private func dayWord(_ count: Int) -> String {
        let mod100 = abs(count) % 100
        let mod10 = abs(count) % 10
        if (11...14).contains(mod100) { return "дней" }
        if mod10 == 1 { return "день" }
        if (2...4).contains(mod10) { return "дня" }
        return "дней"
    }

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
}

/// Draws the existing JPEG with the same fill as `scaledToFill`, without letting the
/// bitmap's own aspect become the card's accessibility frame.
private struct ProjectCardCoverFill: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> ProjectCardCoverView {
        let view = ProjectCardCoverView()
        view.isAccessibilityElement = false
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: ProjectCardCoverView, context: Context) {
        uiView.image = image
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: ProjectCardCoverView,
        context: Context
    ) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

private final class ProjectCardCoverView: UIView {
    var image: UIImage? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentMode = .redraw
        clipsToBounds = true
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override func draw(_ rect: CGRect) {
        guard let image, rect.width > 0, rect.height > 0 else { return }
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
        image.draw(in: CGRect(origin: origin, size: size))
    }
}

private struct ProjectCardDeadline {
    let text: String
    let color: Color
    /// Neutral deadline follows the title ink. Red and green keep their own colors.
    let readableOnCover: Bool
}

private struct CardLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// MARK: - Карточка проекта: премиальный вид с тёмным градиентом
// Разметка как в рабочей сборке «релиз 2» (без общего shell).

/// Chooses ink when the color is drawn. The closure receives the current traits and does not store a snapshot.
private func projectCardFallbackInk(colorName: String?) -> Color {
    let name = (colorName?.isEmpty == false) ? colorName! : "softGray"
    let dynamic = UIColor { traits in
        let resolved = (UIColor(named: name) ?? UIColor(white: 0.90, alpha: 1)).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return UIColor(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
        }
        let luminance = (0.2126 * red) + (0.7152 * green) + (0.0722 * blue)
        if luminance >= 0.62 {
            return UIColor(red: 17.0 / 255.0, green: 17.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
        }
        return .white
    }
    return Color(uiColor: dynamic)
}

private struct ProjectCardView: View {
    let name: String
    let address: String
    let manager: String?
    let description: String?
    let progress: Double
    let progressPercent: Int
    let cardColorName: String?
    let isCompleted: Bool
    let coverImage: UIImage?
    let deadline: ProjectCardDeadline?
    let issueCount: Int

    private var cardColor: Color {
        if let name = cardColorName { Color(name) }
        else { Color("softGray") }
    }

    private var onCover: Bool { coverImage != nil }

    private var fallbackInk: Color {
        projectCardFallbackInk(colorName: cardColorName)
    }

    private var titleColor: Color { onCover ? .white : fallbackInk }

    private var secondaryColor: Color {
        onCover ? Color.white.opacity(0.92) : fallbackInk.opacity(0.72)
    }

    private var progressColor: Color {
        progress >= 1.0 ? ProjectUXColors.progressComplete : ProjectUXColors.progressActive
    }

    var body: some View {
        ProjectCardShell {
            Color.clear
                .overlay {
                    cardStack
                }
        }
    }

    private var cardStack: some View {
        ZStack(alignment: .topLeading) {
                Color.clear
                    .overlay {
                        if let coverImage {
                            ProjectCardCoverFill(image: coverImage)
                        } else {
                            LinearGradient(
                                colors: [
                                    cardColor.opacity(0.9),
                                    cardColor.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .overlay {
                        if onCover {
                            coverScrims
                        }
                    }
                    .clipped()
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    ViewThatFits(in: .vertical) {
                        header(includesDescription: true)
                        header(includesDescription: false)
                    }
                    .padding(.trailing, 72)

                    Spacer(minLength: 4)

                    VStack(alignment: .leading, spacing: 6) {
                        if deadline != nil || issueCount > 0 {
                            statusRow
                        }
                        progressBlock
                    }
                    .layoutPriority(1)

                    Color.clear
                        .frame(height: 44)
                        .accessibilityHidden(true)
                }
                .padding(.top, 10)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilityHidden(true)
        }
    }

    private var coverScrims: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: ProjectUXColors.coverScrimTop, location: 0),
                        .init(color: ProjectUXColors.coverScrimTop.opacity(0.88), location: 0.46),
                        .init(color: ProjectUXColors.coverScrimTop.opacity(0.40), location: 0.74),
                        .init(color: ProjectUXColors.coverScrimTop.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.48, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                LinearGradient(
                    stops: [
                        .init(color: ProjectUXColors.coverScrimBottom.opacity(0), location: 0),
                        .init(color: ProjectUXColors.coverScrimBottom.opacity(0.18), location: 0.12),
                        .init(color: ProjectUXColors.coverScrimBottom.opacity(0.55), location: 0.28),
                        .init(color: ProjectUXColors.coverScrimBottom.opacity(0.86), location: 0.46),
                        .init(color: ProjectUXColors.coverScrimBottom, location: 0.68)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height * 0.58, alignment: .bottom)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func header(includesDescription: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.headline.weight(.semibold))
                .foregroundStyle(titleColor)
                .lineLimit(2)

            if !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(2)
            }

            if let manager = manager?.trimmingCharacters(in: .whitespacesAndNewlines), !manager.isEmpty {
                Text("Ответственный: \(manager)")
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }

            if includesDescription,
               let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
            }
        }
    }

    private var statusRow: some View {
        HStack(spacing: 6) {
            if let deadline {
                Text(deadline.text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(deadline.readableOnCover ? titleColor : deadline.color)
                    .lineLimit(2)
            }
            if issueCount > 0 {
                Text(ProjectIssuesFormatting.remarksPhrase(issueCount))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.issue)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Прогресс")
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                Spacer(minLength: 8)
                Text("\(progressPercent)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(progressColor)
                    .monospacedDigit()
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(ProjectUXColors.progressTrack)
                    if progress > 0 {
                        Capsule()
                            .fill(progressColor)
                            .frame(width: max(0, proxy.size.width * min(max(progress, 0), 1)))
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Экран фото проекта

private struct ProjectPhotosView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    @State private var previewImage: UIImage?

    private var project: Project? {
        store.project(by: projectID)
    }

    var body: some View {
        Group {
            if let project, !project.photoPaths.isEmpty {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(project.photoPaths, id: \.self) { path in
                            if let url = existingFileURL(path),
                               let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 120)
                                    .clipped()
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        previewImage = image
                                    }
                            } else {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.secondary.opacity(0.1))
                                    VStack {
                                        Image(systemName: "photo")
                                        Text("Не удалось загрузить")
                                            .font(.caption2)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .frame(height: 120)
                            }
                        }
                    }
                    .padding(8)
                }
            } else {
                Text("Фотографии пока не добавлены.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Фото проекта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { previewImage != nil },
            set: { if !$0 { previewImage = nil } }
        )) {
            if let image = previewImage {
                FullScreenImageView(image: image)
            }
        }
    }
}

// MARK: - Экран PDF-проекта

private struct ProjectPDFView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID

    private var project: Project? {
        store.project(by: projectID)
    }

    private var pdfURL: URL? {
        guard let path = project?.projectPDFPath else { return nil }
        return existingFileURL(path)
    }

    var body: some View {
        Group {
            if let url = pdfURL,
               FileManager.default.fileExists(atPath: url.path) {
                ZStack {
                    PDFKitContainer(url: url)
                        .ignoresSafeArea()
                }
            } else {
                Text("PDF-проект не найден.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Проект (PDF)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
    }
}

private struct PDFKitContainer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}

// MARK: - Хранилище обложек проектов

final class CoverImageStore {
    static let shared = CoverImageStore()

    private init() {}

    private func coversDirectory() -> URL {
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("ProjectCovers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private func coverURL(for projectID: UUID) -> URL {
        coversDirectory().appendingPathComponent("cover_\(projectID.uuidString).jpg")
    }

    func loadCover(for projectID: UUID) -> UIImage? {
        let url = coverURL(for: projectID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func saveCover(_ image: UIImage, for projectID: UUID) {
        let url = coverURL(for: projectID)
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        try? data.write(to: url, options: [.atomic])
    }

    func deleteCover(for projectID: UUID) {
        let url = coverURL(for: projectID)
        try? FileManager.default.removeItem(at: url)
    }
}
