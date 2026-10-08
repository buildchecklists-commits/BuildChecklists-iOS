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

    var compactTitle: String {
        switch self {
        case .all: return "Все"
        case .current: return "Тек."
        case .completed: return "Готово"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .current: return "clock"
        case .completed: return "checkmark"
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var query: String = ""
    @State private var showForm: Bool = false
    @State private var errorText: String?
    @State private var projectPendingDeletion: Project?
    @State private var deletionStatusText: String?

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

    /// One column. Wide iPad windows center this column instead of placing two narrow cards side by side.
    private let projectColumnMaxWidth: CGFloat = 640

    private let gridColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16)
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

    var body: some View {
        Group {
            if store.projects.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "" : "Мои проекты")
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        .searchable(
            text: $query,
            placement: dynamicTypeSize.isAccessibilitySize
                ? .navigationBarDrawer(displayMode: .always)
                : .automatic,
            prompt: dynamicTypeSize.isAccessibilitySize
                ? Text("Поиск").accessibilityLabel("Поиск по проектам…")
                : Text("Поиск по проектам…")
        )
        .toolbar {
            if dynamicTypeSize.isAccessibilitySize {
                ToolbarItem(placement: .principal) {
                    Text("Мои проекты")
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("Мои проекты")
                }
            }
        }
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
                    .demoTrainingCalculatorNavigation()
            }
            .demoTrainingSheetOverlay()
        }
        .demoTrainingCalculatorBridge($showCalculator)

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
        .alert(
            "Удалить проект?",
            isPresented: Binding(
                get: { projectPendingDeletion != nil },
                set: { if !$0 { projectPendingDeletion = nil } }
            )
        ) {
            Button("Отмена", role: .cancel) { projectPendingDeletion = nil }
            Button("Удалить", role: .destructive) {
                if let project = projectPendingDeletion {
                    projectPendingDeletion = nil
                    confirmDelete(project)
                }
            }
        } message: {
            Text("Будут удалены проект и сохранённая история замечаний с её фотографиями.")
        }
        .alert(
            "Удаление проекта",
            isPresented: Binding(
                get: { deletionStatusText != nil },
                set: { if !$0 { deletionStatusText = nil } }
            )
        ) {
            Button("OK", role: .cancel) { deletionStatusText = nil }
        } message: {
            Text(deletionStatusText ?? "")
        }

        .onAppear {
            recalcAllProjectsProgress()
            reportIncompleteHistoryCleanupIfNeeded()
        }
        .onChange(of: store.projects) { _, _ in
            recalcAllProjectsProgress()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bcProgressDidChange)) { _ in
            recalcAllProjectsProgress()
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
        .padding()
        .frame(maxWidth: projectColumnMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ProjectUXColors.screenBackground)
    }

    private var contentView: some View {
        OfferedWidthBox(maxWidth: projectColumnMaxWidth) {
            VStack(alignment: .leading, spacing: 20) {
                controlsView

                if !currentProjects.isEmpty {
                    sectionHeader(title: "Текущие проекты")

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        ForEach(currentProjects, id: \.project.id) { pair in
                            VStack(alignment: .leading, spacing: 8) {
                                projectRow(pair.project, progress: pair.progress)
                                if store.showsDemoCoach(.openProject), pair.project.id == store.sessionDemoProjectID {
                                    DemoCoachNote(
                                        text: "Начните с примера: откройте этот проект",
                                        identifier: "demo.coach.openProject"
                                    )
                                }
                            }
                        }
                    }
                }

                if !completedProjects.isEmpty {
                    Divider().padding(.vertical, 4)

                    sectionHeader(title: "Завершённые")

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        ForEach(completedProjects, id: \.project.id) { pair in
                            VStack(alignment: .leading, spacing: 8) {
                                projectRow(pair.project, progress: pair.progress)
                                if store.showsDemoCoach(.openProject), pair.project.id == store.sessionDemoProjectID {
                                    DemoCoachNote(
                                        text: "Начните с примера: откройте этот проект",
                                        identifier: "demo.coach.openProject"
                                    )
                                }
                            }
                        }
                    }
                }

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

    private func sortMenu(showsTitle: Bool) -> some View {
        Menu {
            ForEach(ProjectSort.allCases) { sort in
                Button { selectedSort = sort } label: {
                    Label(sort.title, systemImage: sort.iconName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: selectedSort.iconName)
                if showsTitle {
                    Text(selectedSort.title)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(ProjectUXColors.accentAction)
            .padding(.horizontal, 6)
            .frame(minWidth: 44, minHeight: 44)
            .background(.thinMaterial)
            .clipShape(Capsule())
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Сортировка, \(selectedSort.title)")
        .accessibilityAddTraits(.isButton)
    }

    private func calculatorButton(showsTitle: Bool) -> some View {
        Button {
            showCalculator = true
        } label: {
            Group {
                if showsTitle {
                    Text("Калькулятор")
                        .font(.subheadline)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 6)
                        .frame(minHeight: 44)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
                        )
                } else {
                    Image(systemName: "plus.forwardslash.minus")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.thinMaterial)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(ProjectUXColors.accentAction.opacity(0.45), lineWidth: 1)
                        )
                }
            }
            .foregroundStyle(ProjectUXColors.accentAction)
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .demoTrainingAnchor(.calculatorEntryButton)
        .accessibilityLabel("Калькулятор")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("project.list.calculator")
    }

    private func newProjectButton(showsTitle: Bool) -> some View {
        Button {
            guard requireWritableAccess("создавать проекты") else { return }
            showForm = true
        } label: {
            HStack(spacing: 4) {
                if showsTitle {
                    Text("Новый проект")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                Image(systemName: "plus")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(ProjectUXColors.accentAction.opacity(0.18))
                    .foregroundStyle(ProjectUXColors.accentAction)
                    .clipShape(Circle())
            }
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Новый проект")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("project.list.new")
    }

    private var controlsView: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                filterPicker(title: \.title)
                    .fixedSize(horizontal: true, vertical: false)
                filterPicker(title: \.compactTitle)
                    .fixedSize(horizontal: true, vertical: false)
                filterPicker(title: nil)
                    .fixedSize(horizontal: true, vertical: false)
                filterMenu
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .demoTrainingAnchor(.projectsListHeader)

            // Own row (DEMO only): does not compete with sort / calculator titles in listTools.
            DemoTrainingEntryRow()

            ViewThatFits(in: .horizontal) {
                listTools(showsTitles: true)
                listTools(showsTitles: false)
            }
            .frame(maxWidth: .infinity)

            NavigationLink {
                TasksCenterView()
            } label: {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        calendarLabelStacked()
                    } else {
                        ViewThatFits(in: .horizontal) {
                            calendarLabel(showsSubtitle: true)
                            calendarLabel(showsSubtitle: false)
                            calendarLabelWrapped()
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
            .buttonStyle(.plain)
            .demoTrainingAnchor(.taskCalendarEntryBanner)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Календарь задач. Напоминания: купить материалы, заказать бетон и т.д.")
            .accessibilityAddTraits(.isButton)
        }
    }

    private func filterPicker(title: KeyPath<ProjectFilter, String>?) -> some View {
        Picker("Фильтр", selection: $selectedFilter) {
            ForEach(ProjectFilter.allCases) { filter in
                if let title {
                    Text(filter[keyPath: title])
                        .tag(filter)
                        .accessibilityLabel(filter.title)
                } else {
                    Image(systemName: filter.iconName)
                        .tag(filter)
                        .accessibilityLabel(filter.title)
                }
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Фильтр")
    }

    private var filterMenu: some View {
        Menu {
            Picker("Фильтр", selection: $selectedFilter) {
                ForEach(ProjectFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
        } label: {
            Text(selectedFilter.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityLabel("Фильтр, \(selectedFilter.title)")
    }

    private func calendarLabelStacked() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHidden(true)
            }
            UnbrokenText(
                text: "Календарь задач",
                textStyle: .subheadline,
                weight: .semibold,
                maxLines: 2
            )
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func calendarLabelWrapped() -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .accessibilityHidden(true)
            UnbrokenText(
                text: "Календарь задач",
                textStyle: .subheadline,
                weight: .semibold,
                maxLines: 2
            )
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private func listTools(showsTitles: Bool) -> some View {
        HStack(spacing: 8) {
            sortMenu(showsTitle: showsTitles)
            Spacer(minLength: 8)
            calculatorButton(showsTitle: showsTitles)
            newProjectButton(showsTitle: showsTitles)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func calendarLabel(showsSubtitle: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Календарь задач")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if showsSubtitle {
                    Text("Напоминания: купить материалы, заказать бетон и т.д.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func sectionHeader(title: String) -> some View {
        UnbrokenText(
            text: title,
            textStyle: .headline,
            weight: .semibold,
            maxLines: 1
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isHeader)
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
        .demoTrainingAnchor(.profileCreateProfileHint)
    }

    private func projectRow(_ project: Project, progress: Double) -> some View {
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
                    address: dynamicTypeSize.isAccessibilitySize ? "" : project.address,
                    manager: dynamicTypeSize.isAccessibilitySize ? nil : project.manager,
                    description: dynamicTypeSize.isAccessibilitySize ? nil : project.description,
                    progress: progress,
                    progressPercent: progressPercent,
                    cardColorName: project.cardColor,
                    isCompleted: isCompleted,
                    coverImage: coverImage,
                    deadline: dynamicTypeSize.isAccessibilitySize ? nil : deadline,
                    issueCount: dynamicTypeSize.isAccessibilitySize ? 0 : issueCount
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(CardLinkStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(projectCardSummary(project, progressPercent: progressPercent, deadline: deadline, issueCount: issueCount, isCompleted: isCompleted))
            .accessibilityHint("Открывает проект")
            .accessibilityAddTraits(.isButton)
            .accessibilitySortPriority(5)
            .accessibilityIdentifier("project.card.open")
            .modifier(DemoTrainingDemoCardAnchorModifier(isDemoCard: project.id == store.sessionDemoProjectID))

            Button {
                startEdit(project)
            } label: {
                editLabel(onCover: coverImage != nil, ink: fallbackInk)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 10)
            .accessibilityLabel("Редактировать проект, \(project.name)")
            .accessibilitySortPriority(4)
            .accessibilityIdentifier("project.card.edit")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HStack(spacing: 4) {
                projectCardAction(
                    title: "Фото (\(photosCount))",
                    systemImage: "photo.on.rectangle",
                    accessibilityLabel: "Фото проекта, \(project.name)",
                    identifier: "project.card.photos",
                    sortPriority: 3,
                    foreground: coverImage == nil ? fallbackInk : Color.white,
                    action: { photosProject = project }
                )
                projectCardAction(
                    title: "Документы (\(docsCount))",
                    compactTitle: "Док. (\(docsCount))",
                    systemImage: "doc.on.doc",
                    accessibilityLabel: "Документы проекта, \(project.name)",
                    identifier: "project.card.documents",
                    sortPriority: 2,
                    foreground: coverImage == nil ? fallbackInk : Color.white,
                    action: { filesProject = project }
                )
                projectCardAction(
                    title: hasProjectPDF ? "Проект (PDF)" : "Проект",
                    systemImage: hasProjectPDF ? "doc.richtext" : "doc",
                    accessibilityLabel: hasProjectPDF ? "Проект, PDF, \(project.name)" : "Проект, \(project.name)",
                    identifier: "project.card.projectFile",
                    sortPriority: 1,
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
                requestDelete(project)
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

    private func requestDelete(_ project: Project) {
        guard requireWritableAccess("удалять проекты") else { return }
        projectPendingDeletion = project
    }

    private func confirmDelete(_ project: Project) {
        withAnimation {
            do {
                let result = try store.deleteProject(project)
                if let message = result.message {
                    deletionStatusText = message
                } else if result.projectRemoved, !result.historyCleanupFinished {
                    deletionStatusText = IssueHistoryProjectDeletion.incompleteCleanupMessage(projectName: project.name)
                }
            } catch {
                deletionStatusText = error.localizedDescription
            }
        }
    }

    private func reportIncompleteHistoryCleanupIfNeeded() {
        guard !store.isDemoMode else { return }
        guard let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        if IssueHistoryProjectDeletion.hasIncompleteCleanupIntents(fileRoot: root) {
            deletionStatusText = "Есть проекты, удалённые из списка, у которых очистка истории замечаний ещё не завершена. История этих проектов больше не пополняется."
        }
    }

    // MARK: - Progress Cache

    private func recalcAllProjectsProgress() {
        var dict: [UUID: Double] = [:]
        for project in store.projects {
            dict[project.id] = overallProgress(for: project)
        }
        progressCache = dict
    }

    private func editLabel(onCover: Bool, ink: Color) -> some View {
        let foreground = onCover ? Color.white : ink
        let fill = onCover ? Color.black.opacity(0.46) : ink.opacity(0.10)
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: "pencil")
                    .font(.body.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "pencil")
                    Text("Ред.")
                        .lineLimit(1)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(minWidth: 44, minHeight: 44)
            }
        }
        .background { Capsule().fill(fill) }
        .foregroundStyle(foreground)
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private func projectCardAction(
        title: String,
        compactTitle: String? = nil,
        systemImage: String,
        accessibilityLabel: String,
        identifier: String,
        sortPriority: Double = 0,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                cardActionLabel(title, systemImage: systemImage)
                if let compactTitle, compactTitle != title {
                    cardActionLabel(compactTitle, systemImage: systemImage)
                }
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilitySortPriority(sortPriority)
        .accessibilityIdentifier(identifier)
    }

    private func cardActionLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .font(.caption2.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
    }

    private func projectCardSummary(
        _ project: Project,
        progressPercent: Int,
        deadline: ProjectCardDeadline?,
        issueCount: Int,
        isCompleted: Bool
    ) -> String {
        var parts = [project.name]
        if !project.address.isEmpty {
            parts.append(project.address)
        }
        parts.append("Прогресс \(progressPercent) процентов")
        if isCompleted, deadline?.text != "Завершён" {
            parts.append("проект завершён")
        }
        if let deadline {
            parts.append(deadline.text)
        }
        if issueCount > 0 {
            parts.append(ProjectIssuesFormatting.remarksPhrase(issueCount))
        }
        if let manager = project.manager?.trimmingCharacters(in: .whitespacesAndNewlines), !manager.isEmpty {
            parts.append("Ответственный: \(manager)")
        }
        if let description = project.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            parts.append(description)
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
            return ProjectCardDeadline(
                text: ProjectUXCopy.remainingDays(diff),
                compactText: ProjectUXCopy.compactRemainingDays(diff),
                color: ProjectUXColors.secondaryText,
                readableOnCover: true
            )
        }
        if diff == 0 {
            return ProjectCardDeadline(text: "Сегодня", color: ProjectUXColors.progressActive, readableOnCover: true)
        }
        return ProjectCardDeadline(
            text: ProjectUXCopy.overdueDays(abs(diff)),
            compactText: ProjectUXCopy.compactOverdueDays(abs(diff)),
            color: ProjectUXColors.overdue,
            readableOnCover: false
        )
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
    /// Shown only when `text` does not fit. «Сегодня» and «Завершён» stay as they are.
    var compactText: String? = nil
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 64 : 44)
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
            UnbrokenText(
                text: name,
                textStyle: dynamicTypeSize.isAccessibilitySize ? .subheadline : .headline,
                weight: .semibold,
                color: titleColor,
                maxLines: dynamicTypeSize.isAccessibilitySize ? 1 : 2
            )

            if !address.isEmpty {
                UnbrokenText(
                    text: address,
                    textStyle: .subheadline,
                    color: secondaryColor,
                    maxLines: 2
                )
            }

            if let manager = manager?.trimmingCharacters(in: .whitespacesAndNewlines), !manager.isEmpty {
                UnbrokenText(
                    text: "Ответственный: \(manager)",
                    textStyle: .caption1,
                    color: secondaryColor,
                    maxLines: 1
                )
            }

            if includesDescription,
               let description = description?.trimmingCharacters(in: .whitespacesAndNewlines),
               !description.isEmpty {
                UnbrokenText(
                    text: description,
                    textStyle: .caption1,
                    color: secondaryColor,
                    maxLines: 1
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let deadline {
                ViewThatFits(in: .horizontal) {
                    statusPhrase(deadline.text, color: deadlineInk(deadline))
                    if let compact = deadline.compactText {
                        statusPhrase(compact, color: deadlineInk(deadline))
                    }
                }
                .accessibilityHidden(true)
            }
            if issueCount > 0 {
                Text(ProjectIssuesFormatting.remarksPhrase(issueCount))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.issue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }

    private func deadlineInk(_ deadline: ProjectCardDeadline) -> Color {
        deadline.readableOnCover ? titleColor : deadline.color
    }

    /// One line at its natural width, so `ViewThatFits` can choose the full phrase or the short one.
    private func statusPhrase(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Прогресс")
                    .font(.caption2)
                    .foregroundStyle(secondaryColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 8)
                Text("\(progressPercent)%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(progressColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            ProjectProgressBar(fraction: progress, color: progressColor)
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
