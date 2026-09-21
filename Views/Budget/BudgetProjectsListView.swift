import SwiftUI

// MARK: - Фильтр: Все / Текущие / Завершённые
private enum BudgetFilter: String, CaseIterable, Identifiable {
    case all, current, completed
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .current: return "Текущие"
        case .completed: return "Завершённые"
        }
    }
}

// MARK: - Сортировка (как в «Проектах»)
private enum BudgetSort: String, CaseIterable, Identifiable {
    case manual, name, date, progress
    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: return "Ручная"
        case .name: return "По имени"
        case .date: return "По дате"
        case .progress: return "По прогрессу"
        }
    }

    var icon: String {
        switch self {
        case .manual: return "arrow.up.arrow.down"
        case .name: return "textformat"
        case .date: return "calendar"
        case .progress: return "chart.bar.fill"
        }
    }
}

/// Корневой экран модуля "Бюджет": проекты с краткой бюджетной сводкой.
struct BudgetProjectsListView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedFilter: BudgetFilter = .all
    @State private var selectedSort: BudgetSort = .manual
    /// DEMO coachmark (только текущая сессия, без AppStore)
    @State private var showDemoBudgetCoachmark: Bool = false
    @State private var didDismissDemoBudgetCoachmark: Bool = false

    // MARK: - Helpers: прогресс проекта (та же логика, что в ProjectsListView)

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

    // MARK: - Отфильтрованные и отсортированные проекты

    private var filteredAndSorted: [(project: Project, progress: Double)] {
        let allPairs: [(Project, Double)] = store.projects.map { project in
            (project, overallProgress(for: project))
        }

        // Фильтр
        let filtered: [(Project, Double)] = allPairs.filter { pair in
            switch selectedFilter {
            case .all:
                return true
            case .current:
                return pair.1 < 1.0
            case .completed:
                return pair.1 >= 1.0
            }
        }

        // Сортировка
        switch selectedSort {
        case .manual:
            return filtered

        case .name:
            return filtered.sorted { lhs, rhs in
                lhs.0.name.localizedCompare(rhs.0.name) == .orderedAscending
            }

        case .date:
            func key(_ p: Project) -> Date {
                if let d = p.lastUpdated { return d }
                if let d = p.dateStart { return d }
                return .distantPast
            }
            return filtered.sorted { lhs, rhs in
                key(lhs.0) > key(rhs.0)
            }

        case .progress:
            return filtered.sorted { lhs, rhs in
                lhs.1 > rhs.1
            }
        }
    }

    /// Первая карточка в списке: сначала «Текущие», затем «Завершённые».
    private var firstVisibleBudgetProjectID: UUID? {
        let current = filteredAndSorted.filter { $0.progress < 1.0 }
        if let p = current.first { return p.project.id }
        let completed = filteredAndSorted.filter { $0.progress >= 1.0 }
        return completed.first?.project.id
    }

    private var shouldShowDemoBudgetCoachmark: Bool {
        showDemoBudgetCoachmark && store.isDemoMode && !filteredAndSorted.isEmpty
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if store.projects.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            // место под закреплённый хедер
                            Spacer().frame(height: 0)

                            Text("Пока нет проектов")
                                .font(.title3.weight(.semibold))
                            Text("Создайте проект, чтобы начать учитывать бюджет и контролировать перерасход.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding()
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {

                            Spacer().frame(height: 0) // место под фиксированный хедер

                            let current = filteredAndSorted.filter { $0.progress < 1.0 }
                            let completed = filteredAndSorted.filter { $0.progress >= 1.0 }

                            if !current.isEmpty {
                                Text("Текущие проекты")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                ForEach(current, id: \.project.id) { pair in
                                    NavigationLink {
                                        BudgetProjectView(projectID: pair.project.id)
                                    } label: {
                                        BudgetProjectCardView(
                                            project: pair.project,
                                            totalSpent: store.totalAmount(for: pair.project.id),
                                            progress: pair.progress
                                        )
                                    }
                                    .buttonStyle(CardLinkStyle())
                                    .overlay {
                                        if shouldShowDemoBudgetCoachmark,
                                           pair.project.id == firstVisibleBudgetProjectID {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color("AccentYellow"), lineWidth: 2)
                                                .shadow(
                                                    color: Color("AccentYellow").opacity(0.35),
                                                    radius: 10,
                                                    x: 0,
                                                    y: 0
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            if !completed.isEmpty {
                                Divider().padding(.vertical, 6)

                                Text("Завершённые")
                                    .font(.headline)
                                    .padding(.horizontal, 16)

                                ForEach(completed, id: \.project.id) { pair in
                                    NavigationLink {
                                        BudgetProjectView(projectID: pair.project.id)
                                    } label: {
                                        BudgetProjectCardView(
                                            project: pair.project,
                                            totalSpent: store.totalAmount(for: pair.project.id),
                                            progress: pair.progress
                                        )
                                    }
                                    .buttonStyle(CardLinkStyle())
                                    .overlay {
                                        if shouldShowDemoBudgetCoachmark,
                                           pair.project.id == firstVisibleBudgetProjectID {
                                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                                .stroke(Color("AccentYellow"), lineWidth: 2)
                                                .shadow(
                                                    color: Color("AccentYellow").opacity(0.35),
                                                    radius: 10,
                                                    x: 0,
                                                    y: 0
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                            }

                            Spacer().frame(height: 30)
                        }
                    }
                }
            }
            // Закреплённый хедер «Бюджет» + фильтр/сортировка
            .safeAreaInset(edge: .top) {
                VStack(alignment: .leading, spacing: 14) {

                    // Сегменты
                    Picker("Фильтр", selection: $selectedFilter) {
                        ForEach(BudgetFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Сортировка
                    HStack {
                        Menu {
                            ForEach(BudgetSort.allCases) { sort in
                                Button {
                                    selectedSort = sort
                                } label: {
                                    Label(sort.title, systemImage: sort.icon)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selectedSort.icon)
                                Text(selectedSort.title)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption2)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial)
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)

                    // Заголовок + текст
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Бюджет")
                            .font(.title2.weight(.bold))

                        Text("План/факт по этапам и детализация расходов по каждому проекту.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
                .background(.ultraThinMaterial)
                .overlay(
                    Divider().opacity(0.3),
                    alignment: .bottom
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            updateDemoBudgetCoachmarkVisibility()
        }
        .onChange(of: store.projects) { _, _ in
            updateDemoBudgetCoachmarkVisibility()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateDemoBudgetCoachmarkVisibility()
        }
        .onChange(of: selectedSort) { _, _ in
            updateDemoBudgetCoachmarkVisibility()
        }
        .onChange(of: store.isDemoMode) { _, isDemo in
            if isDemo {
                updateDemoBudgetCoachmarkVisibility()
            } else {
                showDemoBudgetCoachmark = false
                didDismissDemoBudgetCoachmark = false
            }
        }
        .overlay {
            if shouldShowDemoBudgetCoachmark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowDemoBudgetCoachmark {
                demoBudgetCoachmark
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
    }

    private var demoBudgetCoachmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(Color("AccentYellow"))
                Text("Контроль бюджета")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    dismissDemoBudgetCoachmark()
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

            Text("Здесь видны расходы по проекту: план и факт по этапам, графики, поиск по операциям и экспорт отчёта. Откройте проект, чтобы посмотреть детали.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Понятно") {
                    dismissDemoBudgetCoachmark()
                }
                .font(.footnote.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentYellow"))
                .foregroundColor(Color("BrandBlack"))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color("AccentYellow").opacity(0.35), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }

    private func updateDemoBudgetCoachmarkVisibility() {
        guard store.isDemoMode else {
            showDemoBudgetCoachmark = false
            return
        }
        showDemoBudgetCoachmark = !didDismissDemoBudgetCoachmark && !filteredAndSorted.isEmpty
    }

    private func dismissDemoBudgetCoachmark() {
        didDismissDemoBudgetCoachmark = true
        withAnimation(.easeOut(duration: 0.2)) {
            showDemoBudgetCoachmark = false
        }
    }
}

// MARK: - Карточка проекта в бюджете

private struct BudgetProjectCardView: View {
    let project: Project
    let totalSpent: Decimal
    let progress: Double

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    private var budget: Decimal? {
        project.budget
    }

    private var formattedSpent: String {
        format(totalSpent) + " ₽"
    }

    private var formattedBudget: String? {
        guard let budget, budget > 0 else { return nil }
        return format(budget) + " ₽"
    }

    private var diffText: String? {
        guard let budget, budget > 0 else { return nil }
        let diff = totalSpent - budget
        if diff == 0 { return "В рамках бюджета" }

        let absDiff = diff < 0 ? -diff : diff
        let amount = format(absDiff) + " ₽"

        if diff > 0 {
            return "Перерасход \(amount)"
        } else {
            return "Экономия \(amount)"
        }
    }

    private var diffColor: Color {
        guard let budget, budget > 0 else { return .secondary }
        return totalSpent > budget ? .red : .green
    }

    private var progressPercentText: String {
        let percent = Int((progress * 100).rounded())
        return "\(percent)%"
    }

    private var dateRangeText: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"

        if let start = project.dateStart, let end = project.dateEnd {
            return "\(formatter.string(from: start)) — \(formatter.string(from: end))"
        } else if let start = project.dateStart {
            return "с \(formatter.string(from: start))"
        } else {
            return nil
        }
    }

    private var coverImage: UIImage? {
        CoverImageStore.shared.loadCover(for: project.id)
    }

    private static func format(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        return numberFormatter.string(from: number) ?? "\(value)"
    }

    private func format(_ value: Decimal) -> String {
        Self.format(value)
    }

    var body: some View {
        // Тот же ProjectCardShell, что «Проекты»/«Сроки» — высота карточки совпадает, низ не обрезается.
        ProjectCardShell {
            ZStack(alignment: .topLeading) {
                Group {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [
                                Color("softGray").opacity(0.95),
                                Color("softGray").opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.65),
                                Color.black.opacity(0.4),
                                Color.black.opacity(0.15)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.name)
                            .font(.headline.weight(.semibold))
                            .lineLimit(2)
                        if !project.address.isEmpty {
                            Text(project.address)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.85))
                                .lineLimit(2)
                        }
                        if let dateText = dateRangeText {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                Text(dateText)
                                    .font(.caption2)
                            }
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        }
                    }
                    .layoutPriority(0)

                    Spacer(minLength: 6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .lastTextBaseline, spacing: 6) {
                            Text(formattedSpent)
                                .font(.title2.weight(.bold))
                                .monospacedDigit()
                                .minimumScaleFactor(0.75)
                                .lineLimit(1)

                            if let formattedBudget {
                                Text("из \(formattedBudget)")
                                    .font(.footnote)
                                    .foregroundColor(.white.opacity(0.9))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                        }

                        Text("Потрачено по проекту")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(1)

                        HStack(alignment: .center, spacing: 8) {
                            if let diffText {
                                Text(diffText)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(diffColor.opacity(0.9))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }

                            Spacer(minLength: 4)

                            Text(progressPercentText)
                                .font(.caption2.weight(.medium))
                                .monospacedDigit()
                                .lineLimit(1)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.top, 2)
                    }
                    .layoutPriority(1)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .foregroundColor(.white)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

// MARK: - Стиль нажатия по карточке (анимация, как в ProjectsListView)

private struct CardLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(
                .spring(response: 0.25, dampingFraction: 0.8),
                value: configuration.isPressed
            )
    }
}

