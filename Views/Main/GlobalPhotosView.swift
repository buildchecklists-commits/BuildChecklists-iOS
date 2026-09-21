import SwiftUI
import UIKit

// MARK: - Источник фото
private enum GlobalPhotoSource: String, CaseIterable, Identifiable {
    case all
    case project
    case checklist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:       return "Все"
        case .project:   return "Проект"
        case .checklist: return "Чек-листы"
        }
    }
}

// MARK: - Сортировка фото
private enum PhotoSort: String, CaseIterable, Identifiable {
    case dateNewest
    case dateOldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateNewest: return "По дате (новые сначала)"
        case .dateOldest: return "По дате (старые сначала)"
        }
    }

    var icon: String {
        switch self {
        case .dateNewest: return "calendar.badge.clock"
        case .dateOldest: return "calendar"
        }
    }
}

// MARK: - Группа по времени
private enum PhotoTimeGroup: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case thisMonth
    case older

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:     return "Сегодня"
        case .thisWeek:  return "На этой неделе"
        case .thisMonth: return "В этом месяце"
        case .older:     return "Раньше"
        }
    }
}

// MARK: - Модель одного фото
private struct GlobalPhotoItem: Identifiable, Hashable {
    let projectID: UUID
    let projectName: String
    let stageTitle: String?
    let itemTitle: String?
    let path: String
    let source: GlobalPhotoSource
    let date: Date?
    let stageCategory: GlobalStageCategory?

    var id: String { "\(projectID.uuidString)|\(path)" }
}

// MARK: - Глобальная галерея
struct GlobalPhotosView: View {
    @EnvironmentObject var store: AppStore

    @State private var selectedProjectID: UUID? = nil
    @State private var sourceFilter: GlobalPhotoSource = .all
    @State private var selectedStageCategory: GlobalStageCategory? = nil
    @State private var selectedSort: PhotoSort = .dateNewest

    @State private var showFullScreen = false
    @State private var currentIndex: Int = 0

    @State private var expandedGroups: Set<PhotoTimeGroup> = [.today, .thisWeek]

    @State private var navigateToStage: Bool = false
    @State private var navigationProject: Project? = nil
    @State private var navigationCategory: GlobalStageCategory? = nil

    // Read-only / Paywall
    @State private var showPaywall: Bool = false

    /// DEMO coachmark (только текущая сессия, без AppStore)
    @State private var showDemoPhotosCoachmark: Bool = false
    @State private var didDismissDemoPhotosCoachmark: Bool = false

    // MARK: - Все фото
    private var allPhotosRaw: [GlobalPhotoItem] {
        var result: [GlobalPhotoItem] = []

        for project in store.projects {

            // Фото проекта
            for path in project.photoPaths {
                guard existingFileURL(path) != nil else { continue }

                result.append(
                    GlobalPhotoItem(
                        projectID: project.id,
                        projectName: project.name,
                        stageTitle: nil,
                        itemTitle: nil,
                        path: path,
                        source: .project,
                        date: fileDate(path),
                        stageCategory: nil
                    )
                )
            }

            // Фото из чек-листов
            let allStagesArrays: [(GlobalStageCategory, [Stage]?)] = [
                (.geologyAndPrep, GeologyProgressStore.load(projectID: project.id)),
                (.foundation,     FoundationProgressStore.load(projectID: project.id)),
                (.walls,          WallsProgressStore.load(projectID: project.id)),
                (.slabs,          SlabProgressStore.load(projectID: project.id)),
                (.roof,           RoofProgressStore.load(projectID: project.id)),
                (.roofCover,      RoofCoverProgressStore.load(projectID: project.id)),
                (.engineering,    EngineeringProgressStore.load(projectID: project.id)),
                (.windows,        WindowsProgressStore.load(projectID: project.id)),
                (.doors,          DoorsProgressStore.load(projectID: project.id)),
                (.finishing,      FinishingProgressStore.load(projectID: project.id)),
                (.landscaping,    LandscapingProgressStore.load(projectID: project.id))
            ]

            for (category, stagesOpt) in allStagesArrays {
                guard let stages = stagesOpt else { continue }

                for stage in stages {
                    for item in stage.items {
                        for path in item.photoPaths {
                            guard existingFileURL(path) != nil else { continue }

                            result.append(
                                GlobalPhotoItem(
                                    projectID: project.id,
                                    projectName: project.name,
                                    stageTitle: stage.title,
                                    itemTitle: item.title,
                                    path: path,
                                    source: .checklist,
                                    date: fileDate(path),
                                    stageCategory: category
                                )
                            )
                        }
                    }
                }
            }
        }

        return result
    }

    // MARK: - Фильтры
    private var filteredPhotos: [GlobalPhotoItem] {
        var items = allPhotosRaw

        // Проект
        if let pid = selectedProjectID {
            items = items.filter { $0.projectID == pid }
        }

        // Источник
        switch sourceFilter {
        case .all:
            break
        case .project:
            items = items.filter { $0.source == .project }
        case .checklist:
            items = items.filter { $0.source == .checklist }
        }

        // Этап
        if let stageCat = selectedStageCategory {
            items = items.filter { $0.stageCategory == stageCat }
        }

        // Сортировка по дате
        items.sort { lhs, rhs in
            let d1 = lhs.date ?? .distantPast
            let d2 = rhs.date ?? .distantPast
            switch selectedSort {
            case .dateNewest:
                return d1 > d2
            case .dateOldest:
                return d1 < d2
            }
        }

        return items
    }

    private var groupedByTime: [(PhotoTimeGroup, [GlobalPhotoItem])] {
        let calendar = Calendar.current
        let now = Date()
        var groups: [PhotoTimeGroup: [GlobalPhotoItem]] = [:]
        for g in PhotoTimeGroup.allCases { groups[g] = [] }

        for item in filteredPhotos {
            guard let date = item.date else {
                groups[.older]?.append(item)
                continue
            }

            if calendar.isDateInToday(date) {
                groups[.today]?.append(item)
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                groups[.thisWeek]?.append(item)
            } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
                groups[.thisMonth]?.append(item)
            } else {
                groups[.older]?.append(item)
            }
        }

        return PhotoTimeGroup.allCases.compactMap {
            if let items = groups[$0], !items.isEmpty {
                return ($0, items)
            }
            return nil
        }
    }

    /// Первая плитка в порядке отображения (первая группа `groupedByTime` → первый элемент).
    private var firstVisibleGridPhotoID: String? {
        groupedByTime.first?.1.first?.id
    }

    private var shouldShowDemoPhotosCoachmark: Bool {
        showDemoPhotosCoachmark && store.isDemoMode && !filteredPhotos.isEmpty
    }

    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {

                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        ForEach(groupedByTime, id: \.0.id) { group, items in
                            VStack(alignment: .leading, spacing: 8) {

                                Button {
                                    if expandedGroups.contains(group) {
                                        expandedGroups.remove(group)
                                    } else {
                                        expandedGroups.insert(group)
                                    }
                                } label: {
                                    HStack {
                                        Text(group.title)
                                            .font(.headline)
                                        Spacer()
                                        Text("\(items.count)")
                                            .foregroundStyle(.secondary)
                                        Image(systemName: expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)

                                if expandedGroups.contains(group) {
                                    LazyVGrid(
                                        columns: [
                                            GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 12)
                                        ],
                                        spacing: 12
                                    ) {
                                        ForEach(items) { item in
                                            photoTile(item: item)
                                                .overlay {
                                                    if shouldShowDemoPhotosCoachmark,
                                                       item.id == firstVisibleGridPhotoID {
                                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                                            .stroke(Color("AccentYellow"), lineWidth: 2)
                                                            .shadow(
                                                                color: Color("AccentYellow").opacity(0.35),
                                                                radius: 8,
                                                                x: 0,
                                                                y: 0
                                                            )
                                                    }
                                                }
                                                .onTapGesture {
                                                    if let idx = filteredPhotos.firstIndex(where: { $0.id == item.id }) {
                                                        currentIndex = idx
                                                        showFullScreen = true
                                                    }
                                                }
                                        }
                                    }
                                    .padding(.horizontal, 12)
                                }
                            }
                        }

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 16)
                }
            }
            // Закреплённый хедер в стиле «Бюджет / Сроки»
            .safeAreaInset(edge: .top) {
                GlobalPhotosHeaderView(
                    sourceFilter: $sourceFilter,
                    selectedSort: $selectedSort,
                    selectedProjectID: $selectedProjectID,
                    selectedStageCategory: $selectedStageCategory,
                    showPaywall: $showPaywall
                )
                .environmentObject(store)
            }
            .sheet(isPresented: $showFullScreen) {
                if !filteredPhotos.isEmpty {
                    FullScreenPhotoGallery(
                        photos: filteredPhotos,
                        currentIndex: $currentIndex,
                        showFullScreen: $showFullScreen,
                        onStageTap: { item in
                            guard let project = store.projects.first(where: { $0.id == item.projectID }) else { return }
                            guard let category = item.stageCategory else { return }

                            navigationProject = project
                            navigationCategory = category
                            navigateToStage = true
                        }
                    )
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(store)
            }
            .background(
                NavigationLink(
                    destination: stageNavigationDestination,
                    isActive: $navigateToStage,
                    label: { EmptyView() }
                )
            )
            .toolbar(.hidden, for: .navigationBar)
            .animation(.default, value: expandedGroups)
        }
        .onAppear {
            updateDemoPhotosCoachmarkVisibility()
        }
        .onChange(of: store.isDemoMode) { _, isDemo in
            if isDemo {
                updateDemoPhotosCoachmarkVisibility()
            } else {
                showDemoPhotosCoachmark = false
                didDismissDemoPhotosCoachmark = false
            }
        }
        .onChange(of: store.projects) { _, _ in
            updateDemoPhotosCoachmarkVisibility()
        }
        .onChange(of: selectedProjectID) { _, _ in
            updateDemoPhotosCoachmarkVisibility()
        }
        .onChange(of: sourceFilter) { _, _ in
            updateDemoPhotosCoachmarkVisibility()
        }
        .onChange(of: selectedStageCategory) { _, _ in
            updateDemoPhotosCoachmarkVisibility()
        }
        .onChange(of: selectedSort) { _, _ in
            updateDemoPhotosCoachmarkVisibility()
        }
        .overlay {
            if shouldShowDemoPhotosCoachmark {
                Color.black.opacity(0.2)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if shouldShowDemoPhotosCoachmark {
                demoPhotosCoachmark
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
    }

    private var demoPhotosCoachmark: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundColor(Color("AccentYellow"))
                Text("Фотографии проекта")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button {
                    dismissDemoPhotosCoachmark()
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

            Text("Все фото привязаны к проекту — без хаоса в системной галерее. Фильтры по источнику и этапу помогают быстро найти нужное.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Понятно") {
                    dismissDemoPhotosCoachmark()
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

    private func updateDemoPhotosCoachmarkVisibility() {
        guard store.isDemoMode else {
            showDemoPhotosCoachmark = false
            return
        }
        guard !didDismissDemoPhotosCoachmark else {
            showDemoPhotosCoachmark = false
            return
        }
        guard !filteredPhotos.isEmpty else {
            showDemoPhotosCoachmark = false
            return
        }
        // Раскрываем первую непустую группу только при переходе «coachmark выключен → включён»,
        // чтобы не переоткрывать её на каждом onChange и не ломать ручное сворачивание.
        if !showDemoPhotosCoachmark, let firstGroup = groupedByTime.first?.0 {
            expandedGroups.insert(firstGroup)
        }
        showDemoPhotosCoachmark = true
    }

    private func dismissDemoPhotosCoachmark() {
        didDismissDemoPhotosCoachmark = true
        withAnimation(.easeOut(duration: 0.2)) {
            showDemoPhotosCoachmark = false
        }
    }

    // MARK: - Навигация по этапам
    @ViewBuilder
    private var stageNavigationDestination: some View {
        if let project = navigationProject,
           let category = navigationCategory {

            switch category {
            case .geologyAndPrep: GeologyStagesScreen(project: project)
            case .foundation:      FoundationStagesScreen(project: project)
            case .walls:           WallsStagesScreen(project: project)
            case .slabs:           SlabStagesScreen(project: project)
            case .roof:            RoofStagesScreen(project: project)
            case .roofCover:       RoofCoverStagesScreen(project: project)
            case .engineering:     EngineeringStagesScreen(project: project)
            case .windows:         WindowsStagesScreen(project: project)
            case .doors:           DoorsStagesScreen(project: project)
            case .finishing:       FinishingStagesScreen(project: project)
            case .landscaping:     LandscapingStagesScreen(project: project)
            }
        } else {
            EmptyView()
        }
    }

    // MARK: - Плитка фото

    /// Короткий тег этапа для плитки: из "Этап 3. Опалубка/..." делаем "Этап 3".
    private func shortStageTitle(_ full: String?) -> String? {
        guard let full = full, !full.isEmpty else { return nil }
        let parts = full.components(separatedBy: ".")
        if let first = parts.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return full
    }

    private func photoTile(item: GlobalPhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))

                if let ui = loadImage(item.path) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                        .frame(minWidth: 150, minHeight: 110)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 150, minHeight: 110)
                }

                RoundedRectangle(cornerRadius: 16)
                    .stroke(
                        (item.stageCategory?.color ?? .clear).opacity(item.stageCategory == nil ? 0 : 0.6),
                        lineWidth: item.stageCategory == nil ? 0 : 2
                    )
            }
            .frame(height: 120)

            if let shortStage = shortStageTitle(item.stageTitle) {
                Text(shortStage)
                    .font(.caption.weight(.semibold))
            } else {
                Text("Общее фото")
                    .font(.caption.weight(.semibold))
            }

            Text(item.projectName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if item.stageTitle == nil {
                Text("Фото проекта")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let t = item.itemTitle {
                Text(t)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - Хедер вкладки «Фото»

private struct GlobalPhotosHeaderView: View {
    @EnvironmentObject var store: AppStore

    @Binding var sourceFilter: GlobalPhotoSource
    @Binding var selectedSort: PhotoSort
    @Binding var selectedProjectID: UUID?
    @Binding var selectedStageCategory: GlobalStageCategory?
    @Binding var showPaywall: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // Сегменты по источнику
            Picker("Источник", selection: $sourceFilter) {
                ForEach(GlobalPhotoSource.allCases) { s in
                    Text(s.title).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Read-only баннер (как единый премиальный UX)
            if store.isReadOnlyMode {
                readOnlyBanner
                    .padding(.horizontal, 16)
            }

            // Сортировка + фильтр
            HStack(spacing: 12) {
                Menu {
                    ForEach(PhotoSort.allCases) { sort in
                        Button {
                            selectedSort = sort
                        } label: {
                            Label(sort.title, systemImage: sort.icon)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedSort.icon)
                        Text(selectedSort == .dateNewest ? "Новые сначала" : "Старые сначала")
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                }

                Menu {
                    // Проекты
                    Section("Проект") {
                        Button {
                            selectedProjectID = nil
                        } label: {
                            Label("Все проекты", systemImage: "square.stack.3d.up")
                        }

                        ForEach(store.projects) { project in
                            Button {
                                selectedProjectID = project.id
                            } label: {
                                Label(project.name, systemImage: "house")
                            }
                        }
                    }

                    // Этапы
                    Section("Этап") {
                        Button {
                            selectedStageCategory = nil
                        } label: {
                            Label("Все этапы", systemImage: "line.3.horizontal.decrease")
                        }

                        ForEach(GlobalStageCategory.allCases) { category in
                            Button {
                                selectedStageCategory = category
                            } label: {
                                Label(category.title, systemImage: "checkmark.circle")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                        Text("Фильтр")
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

            // Заголовок + подзаголовок
            VStack(alignment: .leading, spacing: 2) {
                Text("Фото")
                    .font(.title2.weight(.bold))

                Text("Просматривайте фото по проектам, этапам и датам, чтобы контролировать ход стройки.")
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

    private var readOnlyBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("Режим только просмотр")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Добавление и удаление фото доступно по подписке USER или PRO.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    _ = await store.refreshRoleForCurrentUser()
                    if store.isReadOnlyMode {
                        showPaywall = true
                    }
                }
            } label: {
                Text("Разблокировать")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Fullscreen Gallery
private struct FullScreenPhotoGallery: View {
    let photos: [GlobalPhotoItem]
    @Binding var currentIndex: Int
    @Binding var showFullScreen: Bool

    @State private var scale: CGFloat = 1.0
    var onStageTap: ((GlobalPhotoItem) -> Void)? = nil

    private var currentItem: GlobalPhotoItem? {
        guard !photos.isEmpty,
              currentIndex >= 0,
              currentIndex < photos.count else { return nil }
        return photos[currentIndex]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty || currentIndex < 0 || currentIndex >= photos.count {
                Text("Фото недоступно")
                    .foregroundColor(.white)
            } else {
                TabView(selection: $currentIndex) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { (index, item) in
                        ZStack {
                            Color.black.ignoresSafeArea()

                            if let ui = loadImage(item.path) {
                                GeometryReader { proxy in
                                    let size = proxy.size
                                    Image(uiImage: ui)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: size.width, height: size.height)
                                        .scaleEffect(scale)
                                        .gesture(
                                            MagnificationGesture()
                                                .onChanged { value in
                                                    scale = value
                                                }
                                                .onEnded { _ in
                                                    withAnimation(.spring()) { scale = 1.0 }
                                                }
                                        )
                                }
                            } else {
                                Text("Не удалось загрузить фото")
                                    .foregroundColor(.white)
                            }
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }

            VStack(spacing: 8) {
                HStack {
                    Button {
                        showFullScreen = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding()
                    }
                    Spacer()
                }

                if let item = currentItem,
                   let stage = item.stageTitle {
                    Button {
                        showFullScreen = false
                        onStageTap?(item)
                    } label: {
                        HStack(spacing: 6) {
                            Text(stage).bold()
                            Text("· \(item.projectName)")
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                    }
                    .padding(.horizontal)
                }

                Spacer()

                if let item = currentItem {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.projectName)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.white)

                        if let stage = item.stageTitle {
                            Text(stage).foregroundColor(.white)
                        }

                        if let t = item.itemTitle {
                            Text(t)
                                .foregroundStyle(.white.opacity(0.9))
                                .lineLimit(2)
                        }

                        HStack {
                            Text(item.source == .project ? "Фото проекта" : "Фото из чек-листа")
                                .foregroundStyle(.white.opacity(0.8))
                            Spacer()
                            if let d = formattedDateString(item.date) {
                                Text(d)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }

                        Text("\(currentIndex + 1) из \(photos.count)")
                            .foregroundStyle(.white.opacity(0.8))

                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .padding(.bottom, 20)
                }
            }
        }
    }
}

// MARK: - Helpers
private func loadImage(_ path: String) -> UIImage? {
    guard let url = existingFileURL(path) else { return nil }
    return UIImage(contentsOfFile: url.path)
}

private func fileDate(_ path: String) -> Date? {
    guard let url = existingFileURL(path) else { return nil }
    let fm = FileManager.default
    guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { return nil }

    if let c = attrs[.creationDate] as? Date { return c }
    if let m = attrs[.modificationDate] as? Date { return m }
    return nil
}

private func formattedDateString(_ date: Date?) -> String? {
    guard let date = date else { return nil }
    let df = DateFormatter()
    df.dateStyle = .medium
    df.timeStyle = .short
    return df.string(from: date)
}
