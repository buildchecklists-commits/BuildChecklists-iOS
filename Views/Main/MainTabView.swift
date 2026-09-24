import SwiftUI
import UIKit
import PhotosUI

// MARK: - Фильтры и сортировка для вкладки «Сроки»

private enum PlanFilter: String, CaseIterable, Identifiable {
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

private enum PlanSort: String, CaseIterable, Identifiable {
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

// MARK: - Главный таббар

private let bcLastSeenWhatsNewVersionKey = "bc_last_seen_whats_new_version"

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @State private var showWhatsNew = false

    var body: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.setSelectedTab($0) }
        )) {

            // ПРОЕКТЫ
            ProjectsListView()
                .tabItem {
                    Label("Проекты", systemImage: "square.grid.2x2")
                }
                .tag(MainTab.projects)

            // СРОКИ
            PlanProjectsListView()
                .environmentObject(store)
                .tabItem {
                    Label("Сроки", systemImage: "calendar.badge.clock")
                }
                .tag(MainTab.plan)

            // БЮДЖЕТ
            BudgetProjectsListView()
                .environmentObject(store)
                .tabItem {
                    Label("Бюджет", systemImage: "chart.pie")
                }
                .tag(MainTab.budget)

            // ГЛОБАЛЬНЫЕ ФОТО
            GlobalPhotosView()
                .tabItem {
                    Label("Фото", systemImage: "photo.on.rectangle")
                }
                .tag(MainTab.photos)

            // ПРОФИЛЬ
            ProfilePlaceholderView()
                .tabItem {
                    Label("Профиль", systemImage: "person.crop.circle")
                }
                .tag(MainTab.profile)
        }
        .preferredColorScheme(
            appColorScheme == "system"
            ? nil
            : (appColorScheme == "dark" ? .dark : .light)
        )
        .onAppear {
            guard store.isRegistered || store.isDemoMode else { return }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
            let lastSeen = UserDefaults.standard.string(forKey: bcLastSeenWhatsNewVersionKey)
            if lastSeen != current {
                showWhatsNew = true
            }
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewView(isPresented: $showWhatsNew)
        }
    }
}

// MARK: - Экран «Сроки» – список проектов

struct PlanProjectsListView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedFilter: PlanFilter = .all
    @State private var selectedSort: PlanSort = .manual
    /// DEMO coachmark (только текущая сессия, без AppStore)
    @State private var showDemoTimelineCoachmark: Bool = false
    @State private var didDismissDemoTimelineCoachmark: Bool = false

    private var filteredAndSorted: [Project] {
        let projects = store.projects.filter { project in
            let progress = store.projectProgress(project)
            switch selectedFilter {
            case .all:
                return true
            case .current:
                return progress < 1.0
            case .completed:
                return progress >= 1.0
            }
        }

        switch selectedSort {
        case .manual:
            return projects
        case .name:
            return projects.sorted {
                $0.name.localizedCompare($1.name) == .orderedAscending
            }
        case .date:
            return projects.sorted {
                let a = $0.lastUpdated ?? $0.dateStart ?? .distantPast
                let b = $1.lastUpdated ?? $1.dateStart ?? .distantPast
                return a > b
            }
        case .progress:
            return projects.sorted {
                store.projectProgress($0) > store.projectProgress($1)
            }
        }
    }

    private var shouldShowDemoTimelineCoachmark: Bool {
        showDemoTimelineCoachmark && store.isDemoMode && !filteredAndSorted.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {

                        Spacer().frame(height: 0)

                        if filteredAndSorted.isEmpty {
                            emptyState
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(filteredAndSorted) { project in
                                    NavigationLink {
                                        ProjectPlanView(projectID: project.id)
                                            .environmentObject(store)
                                    } label: {
                                        PlanProjectRow(project: project)
                                    }
                                    .buttonStyle(.plain)
                                    .overlay {
                                        if shouldShowDemoTimelineCoachmark,
                                           project.id == filteredAndSorted.first?.id {
                                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                                .stroke(Color("AccentYellow"), lineWidth: 2)
                                                .shadow(
                                                    color: Color("AccentYellow").opacity(0.35),
                                                    radius: 10,
                                                    x: 0,
                                                    y: 0
                                                )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                PlanHeaderView(
                    selectedFilter: $selectedFilter,
                    selectedSort: $selectedSort
                )
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            updateDemoTimelineCoachmarkVisibility()
        }
        .onChange(of: store.projects) { _, _ in
            updateDemoTimelineCoachmarkVisibility()
        }
        .onChange(of: selectedFilter) { _, _ in
            updateDemoTimelineCoachmarkVisibility()
        }
        .onChange(of: selectedSort) { _, _ in
            updateDemoTimelineCoachmarkVisibility()
        }
        .onChange(of: store.isDemoMode) { _, isDemo in
            if isDemo {
                updateDemoTimelineCoachmarkVisibility()
            } else {
                showDemoTimelineCoachmark = false
                didDismissDemoTimelineCoachmark = false
            }
        }
        .overlay {
            if shouldShowDemoTimelineCoachmark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowDemoTimelineCoachmark {
                demoTimelineCoachmark
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Пока нет проектов")
                .font(.headline)
            Text("Создайте проект во вкладке «Проекты», чтобы планировать сроки, бюджет и напоминания.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var demoTimelineCoachmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundColor(Color("AccentYellow"))
                Text("Сроки по проекту")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    dismissDemoTimelineCoachmark()
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

            Text("Здесь видно плановые и фактические сроки по этапам, просрочки и причины задержек. Откройте проект, чтобы посмотреть таймлайн строительства.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Понятно") {
                    dismissDemoTimelineCoachmark()
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

    private func updateDemoTimelineCoachmarkVisibility() {
        guard store.isDemoMode else {
            showDemoTimelineCoachmark = false
            return
        }
        showDemoTimelineCoachmark = !didDismissDemoTimelineCoachmark && !filteredAndSorted.isEmpty
    }

    private func dismissDemoTimelineCoachmark() {
        didDismissDemoTimelineCoachmark = true
        withAnimation(.easeOut(duration: 0.2)) {
            showDemoTimelineCoachmark = false
        }
    }
}

// MARK: - Закреплённый хедер вкладки «Сроки»

private struct PlanHeaderView: View {
    @Binding var selectedFilter: PlanFilter
    @Binding var selectedSort: PlanSort

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Picker("Фильтр", selection: $selectedFilter) {
                ForEach(PlanFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            HStack {
                Menu {
                    ForEach(PlanSort.allCases) { sort in
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

            VStack(alignment: .leading, spacing: 2) {
                Text("Сроки")
                    .font(.title2.weight(.bold))

                Text("Следите за прогрессом, дедлайнами и фактическими сроками по каждому проекту.")
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
}

// MARK: - Единая геометрия карточки проекта (Проекты / Сроки / Бюджет)

/// Общие метрики: 16:9 было слишком низким — нижние блоки обрезались на iPhone XR.
enum ProjectCardChrome {
    /// Шире, чем 16/9 — достаточная высота под прогресс + ряд кнопок / чипы бюджета.
    static let aspectRatio: CGFloat = 16.0 / 11.0
    static let cornerRadius: CGFloat = 20
}

/// Один внешний shell: ширина от родителя, высота строго width / (16/11).
/// Высота не берётся из идеального размера текста, иначе Dynamic Type раздвигает карточку.
struct ProjectCardShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ProjectCardRatioLayout(aspectRatio: ProjectCardChrome.aspectRatio) {
            content()
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: ProjectCardChrome.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ProjectCardChrome.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }
}

/// Возвращает высоту только из предложенной ширины. Идеальный размер содержимого не участвует.
private struct ProjectCardRatioLayout: Layout {
    var aspectRatio: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.first?.sizeThatFits(ProposedViewSize(width: nil, height: nil)).width ?? 0
        return CGSize(width: width, height: width / aspectRatio)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let childProposal = ProposedViewSize(width: bounds.width, height: bounds.height)
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: childProposal)
        }
    }
}

// MARK: - Строка проекта во вкладке «Сроки»

struct PlanProjectRow: View {
    let project: Project

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    private var cardColor: Color {
        if let name = project.cardColor, !name.isEmpty {
            return Color(name)
        } else {
            return Color("softGray")
        }
    }

    private var coverImage: UIImage? {
        CoverImageStore.shared.loadCover(for: project.id)
    }

    var body: some View {
        // Тот же shell, что Проекты/Бюджет; контент прижат к верху, низ — запас под единую высоту карточки.
        ProjectCardShell {
            ZStack(alignment: .topLeading) {
                Group {
                    if let image = coverImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                            .clipped()
                    } else {
                        LinearGradient(
                            colors: [
                                cardColor.opacity(0.95),
                                cardColor.opacity(0.7)
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
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 6) {
                    Text(project.name)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if !project.address.isEmpty {
                        Text(project.address)
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.85))
                            .lineLimit(2)
                    }

                    if let start = project.dateStart, let end = project.dateEnd {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.caption)
                            Text("\(Self.dateFormatter.string(from: start)) — \(Self.dateFormatter.string(from: end))")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    } else if let end = project.dateEnd {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.caption)
                            Text("Дедлайн: \(Self.dateFormatter.string(from: end))")
                        }
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                    }

                    Text("Таймлайн этапов, причины задержек и фактические сроки.")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)
                        .padding(.top, 2)

                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

// MARK: - Хелпер отправки писем

private let contactEmail: String = "BuildChecklists@yandex.ru"

private func sendEmail(to: String, subject: String, body: String) {
    let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
    let urlString = "mailto:\(to)?subject=\(subjectEncoded)&body=\(bodyEncoded)"

    guard let url = URL(string: urlString) else { return }

    if UIApplication.shared.canOpenURL(url) {
        UIApplication.shared.open(url)
    }
}

// MARK: - Профиль + советы + выбор темы

struct ProfilePlaceholderView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    @AppStorage("profileName") private var profileName: String = ""
    @AppStorage("profileAvatarData") private var profileAvatarData: Data = Data()

    private enum ActiveSheet: Identifiable {
        case profileEdit
        case adviceOleg
        case paywall

        var id: Int {
            switch self {
            case .profileEdit: return 1
            case .adviceOleg: return 2
            case .paywall: return 3
            }
        }
    }

    @State private var activeSheet: ActiveSheet?

    @State private var isWorkingAccess = false
    @State private var accessMessage: String?

    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountMessage: String?

    /// DEMO coachmark (только текущая сессия, без AppStore)
    @State private var showDemoProfileCoachmark: Bool = false
    @State private var didDismissDemoProfileCoachmark: Bool = false

    // ✅ Новый текст (структурированный для красивой верстки в карточки)
    private let olegAdviceIntro: String =
    """
    Это приложение создано на основе реального строительного опыта.

    Оно помогает выстроить систему там, где чаще всего начинается хаос — в сроках, бюджете и контроле работ.
    """

    private let olegAdviceProTitle: String = "Если вы прораб"
    private let olegAdviceProBullets: [String] = [
        "ведите несколько объектов в одном месте",
        "контролируйте этапы, чек-листы, бюджет и сроки",
        "не теряйте детали по каждому объекту"
    ]

    private let olegAdviceSelfTitle: String = "Если вы строите дом для себя"
    private let olegAdviceSelfBullets: [String] = [
        "правильно организуйте процесс",
        "контролируйте подрядчиков",
        "избегайте типичных ошибок, которые приводят к переделкам и лишним затратам"
    ]

    private let olegAdviceClosingLines: [String] = [
        "Стройка — это не импровизация.",
        "Это система.",
        "И она должна быть под контролем."
    ]

    private var profileImage: Image? {
        guard !profileAvatarData.isEmpty,
              let uiImage = UIImage(data: profileAvatarData) else {
            return nil
        }
        return Image(uiImage: uiImage)
    }

    private var avatarBinding: Binding<Data?> {
        Binding<Data?>(
            get: { profileAvatarData.isEmpty ? nil : profileAvatarData },
            set: { profileAvatarData = $0 ?? Data() }
        )
    }

    private var shouldShowDemoProfileCoachmark: Bool {
        showDemoProfileCoachmark && store.isDemoMode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    profileHeader
                    accountSection
                        .overlay {
                            if shouldShowDemoProfileCoachmark {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color("AccentYellow"), lineWidth: 2)
                                    .shadow(
                                        color: Color("AccentYellow").opacity(0.35),
                                        radius: 10,
                                        x: 0,
                                        y: 0
                                    )
                            }
                        }
                    adviceSection
                    feedbackSection
                    deleteAccountSection
                    themeSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .navigationTitle("Профиль")
        }
        .onAppear {
            updateDemoProfileCoachmarkVisibility()
        }
        .onChange(of: store.isDemoMode) { _, isDemo in
            if isDemo {
                updateDemoProfileCoachmarkVisibility()
            } else {
                showDemoProfileCoachmark = false
                didDismissDemoProfileCoachmark = false
            }
        }
        .overlay {
            if shouldShowDemoProfileCoachmark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowDemoProfileCoachmark {
                demoProfileCoachmark
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .profileEdit:
                ProfileEditView(
                    name: $profileName,
                    avatarData: avatarBinding
                )
            case .adviceOleg:
                AdviceSheetView(
                    title: "О приложении",
                    subtitle: "Коротко и по делу",
                    intro: olegAdviceIntro,
                    firstCardTitle: olegAdviceProTitle,
                    firstCardBullets: olegAdviceProBullets,
                    secondCardTitle: olegAdviceSelfTitle,
                    secondCardBullets: olegAdviceSelfBullets,
                    closingLines: olegAdviceClosingLines
                )
            case .paywall:
                PaywallView()
                    .environmentObject(store)
            }
        }
        .alert("Удалить аккаунт?", isPresented: $showDeleteAccountConfirm) {
            Button("Удалить", role: .destructive) {
                Task { await deleteAccountConfirmed() }
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Будет удалён ваш email, профиль и все локальные данные на этом устройстве. Действие необратимо.")
        }
    }

    // MARK: - Аккаунт и тариф (StoreKit)

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Аккаунт и тариф")
                .font(.headline)

            Text(accountSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {

                HStack(spacing: 10) {
                    Image(systemName: planStatusIcon)
                        .foregroundStyle(planStatusTint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentPlanTitle)
                            .font(.subheadline.weight(.semibold))
                        if let secondary = planSecondaryLine {
                            Text(secondary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if store.isReadOnlyMode && !store.isDemoMode {
                        Text("Только просмотр")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color.orange.opacity(0.16))
                            )
                            .foregroundStyle(Color.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                )

                VStack(spacing: 10) {

                    Button {
                        accessMessage = nil
                        activeSheet = .paywall
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Выбрать тариф")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color("AccentYellow").opacity(0.18))
                        )
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {

                        Button {
                            Task { await refreshAccessTapped() }
                        } label: {
                            HStack(spacing: 8) {
                                if isWorkingAccess {
                                    ProgressView().scaleEffect(0.9)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("Обновить")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorkingAccess)

                        Button {
                            Task { await restorePurchasesTapped() }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Восстановить")
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.systemBackground))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(isWorkingAccess)
                    }
                }
            }

            if let accessMessage {
                Text(accessMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var accountSubtitle: String {
        if store.isDemoMode {
            return "Демо-режим: можно всё, но данные не сохраняются."
        }
        if store.isReadOnlyMode {
            return "Подписка не активна — доступен только просмотр. Чтобы снова редактировать, оформите подписку."
        }
        return "Тариф влияет на лимит проектов и доступ к редактированию."
    }

    private var currentPlanTitle: String {
        switch store.userRole {
        case .demo: return "Демо"
        case .user: return "USER"
        case .pro:  return "PRO"
        }
    }

    private var planSecondaryLine: String? {
        if store.isDemoMode {
            return "Данные не сохраняются"
        }
        if store.isReadOnlyMode {
            return "Редактирование заблокировано"
        }
        switch store.userRole {
        case .demo:
            return nil
        case .user:
            return "Проекты: \(store.projects.count)/2"
        case .pro:
            return "Без ограничений"
        }
    }

    private var planStatusIcon: String {
        if store.isDemoMode { return "wand.and.stars" }
        if store.isReadOnlyMode { return "lock.fill" }
        switch store.userRole {
        case .demo: return "wand.and.stars"
        case .user: return "checkmark.seal.fill"
        case .pro:  return "crown.fill"
        }
    }

    private var planStatusTint: Color {
        if store.isReadOnlyMode && !store.isDemoMode { return .orange }
        switch store.userRole {
        case .demo: return Color("AccentYellow")
        case .user: return .green
        case .pro:  return Color("AccentYellow")
        }
    }

    private func refreshAccessTapped() async {
        isWorkingAccess = true
        defer { isWorkingAccess = false }

        let ok = await store.refreshRoleForCurrentUser()
        accessMessage = ok ? "Доступ обновлён." : "Не удалось обновить доступ. Проверьте интернет и попробуйте позже."
    }

    private func restorePurchasesTapped() async {
        isWorkingAccess = true
        defer { isWorkingAccess = false }

        let restored = await store.subscription.restorePurchases()
        _ = await store.refreshRoleForCurrentUser()

        if restored {
            accessMessage = "Покупки восстановлены. Доступ обновлён."
        } else {
            accessMessage = store.subscription.lastErrorMessage ?? "Не удалось восстановить покупки."
        }
    }

    // MARK: - Шапка профиля

    private var profileHeader: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemBackground))

                if let image = profileImage {
                    image
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(profileName.isEmpty ? "Ваше имя" : profileName)
                    .font(.title3.weight(.semibold))

                Text("Нажмите, чтобы изменить имя и фото.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            activeSheet = .profileEdit
        }
    }

    // MARK: - Блок «Совет от прораба»

    private var adviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("О приложении")
                .font(.headline)

            VStack(spacing: 10) {
                adviceCard(
                    title: "Кому и зачем подходит",
                    subtitle: "Прорабам и тем, кто строит дом для себя — коротко, без воды.",
                    imageName: "avatar_oleg",
                    tint: Color.blue.opacity(0.85)
                ) {
                    activeSheet = .adviceOleg
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func adviceCard(
        title: String,
        subtitle: String,
        imageName: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))

                    Image(imageName)
                        .resizable()
                        .scaledToFill()
                        .clipShape(Circle())
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        )
    }

    // MARK: - Блок «Что добавить в приложение?»

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Что добавить в приложение?")
                .font(.headline)

            Text("Напишите, каких функций или чек-листов вам не хватает. Ваши идеи помогают сделать инструмент удобнее для реальной стройки.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                let subject = "Идея для приложения BuildChecklists"
                let body = """
                Расскажите, чего вам не хватает в приложении:

                • Опишите идею:
                • Для какого этапа стройки это нужно:
                • Нужны ли подсказки/обучение по этой теме:

                (эти пункты можно просто перезаписать своим текстом)
                """
                sendEmail(to: contactEmail, subject: subject, body: body)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.max.fill")
                        .font(.subheadline)
                    Text("Предложить идею")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color("AccentYellow").opacity(0.18))
                )
            }
            .buttonStyle(.plain)

            Text("Мы откроем черновик письма на вашей почте. Просто допишите свои мысли и отправьте.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Удаление аккаунта

    private var deleteAccountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Аккаунт")
                .font(.headline)

            Text("Удаление аккаунта удаляет email, профиль и все локальные данные на этом устройстве.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                deleteAccountMessage = nil
                showDeleteAccountConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.subheadline)
                    Text(isDeletingAccount ? "Удаление…" : "Удалить аккаунт")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(isDeletingAccount)

            if let deleteAccountMessage {
                Text(deleteAccountMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func deleteAccountConfirmed() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            try store.deleteAccountAndWipeLocalData()
            profileName = ""
            profileAvatarData = Data()
            deleteAccountMessage = "Аккаунт удалён. Все локальные данные очищены."
        } catch {
            deleteAccountMessage = "Ошибка удаления: \(error.localizedDescription)"
        }
    }

    // MARK: - Блок выбора темы

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Тема оформления")
                .font(.headline)

            Text("Выберите, как отображать приложение: по системным настройкам, всегда светлым или всегда тёмным.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                themeButton(title: "Системная", value: "system", systemImage: "iphone")
                themeButton(title: "Светлая", value: "light", systemImage: "sun.max.fill")
                themeButton(title: "Тёмная", value: "dark", systemImage: "moon.fill")
            }

            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                .background(
                    ZStack {
                        if appColorScheme == "dark" {
                            LinearGradient(
                                colors: [Color.black, Color("BrandBlack").opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        } else {
                            LinearGradient(
                                colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                )
                .overlay(
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Пример экрана")
                            .font(.caption.weight(.semibold))
                        Text(appColorSchemeDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                )
                .frame(height: 70)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func themeButton(title: String, value: String, systemImage: String) -> some View {
        let isSelected = (appColorScheme == value)

        return Button {
            appColorScheme = value
        } label: {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                Text(title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color("AccentYellow").opacity(0.25) : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color("AccentYellow") : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var appColorSchemeDescription: String {
        switch appColorScheme {
        case "light":
            return "Светлый интерфейс, удобен днём и для скриншотов."
        case "dark":
            return "Тёмный интерфейс — комфортно вечером и на объектах."
        default:
            return "Следуем за настройкой системы на этом устройстве."
        }
    }

    private var demoProfileCoachmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .foregroundColor(Color("AccentYellow"))
                Text("Ваш профиль и настройки")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    dismissDemoProfileCoachmark()
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

            Text("Здесь можно оформить подписку, выбрать тему оформления, управлять аккаунтом и при необходимости удалить профиль.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Понятно") {
                    dismissDemoProfileCoachmark()
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

    private func updateDemoProfileCoachmarkVisibility() {
        guard store.isDemoMode else {
            showDemoProfileCoachmark = false
            return
        }
        showDemoProfileCoachmark = !didDismissDemoProfileCoachmark
    }

    private func dismissDemoProfileCoachmark() {
        didDismissDemoProfileCoachmark = true
        withAnimation(.easeOut(duration: 0.2)) {
            showDemoProfileCoachmark = false
        }
    }
}

// MARK: - sheet с советом (карточки для двух сценариев)

private struct AdviceSheetView: View {
    let title: String
    let subtitle: String

    let intro: String

    let firstCardTitle: String
    let firstCardBullets: [String]

    let secondCardTitle: String
    let secondCardBullets: [String]

    let closingLines: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(intro)
                        .font(.body)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    adviceCard(
                        title: firstCardTitle,
                        icon: "helmet",
                        bullets: firstCardBullets
                    )

                    adviceCard(
                        title: secondCardTitle,
                        icon: "house.fill",
                        bullets: secondCardBullets
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(closingLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.body.weight(.semibold))
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private func adviceCard(title: String, icon: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.headline)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(bullets.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)

                        Text(item)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
    }
}

// MARK: - Редактор профиля

private struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var avatarData: Data?

    @State private var pickerItem: PhotosPickerItem?

    private var avatarImage: Image? {
        if let data = avatarData, let ui = UIImage(data: data) {
            return Image(uiImage: ui)
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Имя")) {
                    TextField("Ваше имя", text: $name)
                }

                Section(header: Text("Аватар")) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color(.secondarySystemBackground))
                            if let image = avatarImage {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 64, height: 64)

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text("Выбрать фото")
                        }
                    }
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .onChange(of: pickerItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        avatarData = data
                    }
                }
            }
        }
    }
}
