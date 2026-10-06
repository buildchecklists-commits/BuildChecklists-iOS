import SwiftUI

/// Four approved onboarding screens. Local examples do not read stores or generate PDFs.
struct OnboardingFlowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var store: AppStore
    @AppStorage("bc_has_seen_onboarding") private var hasSeenOnboarding = false
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @Binding var showRegister: Bool

    @State private var page: Int
    @State private var allowsIntroReplay: Bool
    @State private var skipOrigin: Int?
    @State private var measuredWidth: Int = 0
    @State private var introPlayed = false
    @State private var introTask: Task<Void, Never>?
    @State private var houseSettled = false
    @State private var titleShown = false
    @State private var checkShown = false
    @State private var revealedPages: Set<Int> = []
    @State private var revealTask: Task<Void, Never>?
    @State private var foundationChecked = false
    @State private var reportOpen = false
    @State private var storyFooterHeight: CGFloat = 0
    @State private var storyLeadHeight: CGFloat = 0
    @State private var startStackHeight: CGFloat = 0

    init(initialPage: Int = 0, showRegister: Binding<Bool>) {
        let clamped = min(max(initialPage, 0), 3)
        _page = State(initialValue: clamped)
        _allowsIntroReplay = State(initialValue: clamped < 3)
        _showRegister = showRegister
    }

    private let pageCount = 4
    private let columnMax: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            let column = min(geo.size.width, columnMax)
            ZStack {
                houseFrame(width: geo.size.width, height: geo.size.height)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: page)
                if page == 0 {
                    cinematicScreen(width: geo.size.width, height: geo.size.height, column: column)
                } else {
                    storyScreen(width: geo.size.width, height: geo.size.height, column: column)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                measuredWidth = Int(geo.size.width.rounded())
                beginStoryReveal(page)
            }
            .onChange(of: geo.size.width) { _, newWidth in
                measuredWidth = Int(newWidth.rounded())
            }
            .onChange(of: page) { _, newPage in
                if newPage != 0 { stopIntro() }
                beginStoryReveal(newPage)
            }
            .onChange(of: reduceMotion) { _, reduce in
                if reduce {
                    stopIntro()
                    revealTask?.cancel()
                    revealTask = nil
                    if page > 0 { revealedPages.insert(page) }
                }
            }
        }
        .background(OnboardingChrome.background.ignoresSafeArea())
    }

    private func storyScreen(width: CGFloat, height: CGFloat, column: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            cinematicVeil
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            storyTextVeil
            if page == 3 {
                startScreen(width: width, height: height, column: column)
            } else {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    storyHeader(column: column)
                    VStack(alignment: .leading, spacing: 12) {
                        storyTitle
                        storySubtitle
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .frame(maxWidth: column)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background {
                    GeometryReader { lead in
                        Color.clear.preference(key: StoryLeadHeightKey.self, value: lead.size.height)
                    }
                }
                GeometryReader { proxy in
                    ScrollViewReader { scroller in
                        ScrollView {
                            storyBody
                                .padding(.horizontal, 24)
                                .padding(.bottom, 8)
                                .frame(maxWidth: column, alignment: .leading)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: max(0, proxy.size.height - 8), alignment: reportOpen ? .top : .bottom)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .id(page)
                        .onChange(of: reportOpen) { _, open in
                            guard open else { return }
                            if reduceMotion {
                                scroller.scrollTo("story.sheet", anchor: .top)
                            } else {
                                withAnimation(.easeOut(duration: 0.32)) {
                                    scroller.scrollTo("story.sheet", anchor: .top)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom, storyFooterHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            storyFooter
                .frame(maxWidth: column)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 8)
                .background(Color.black.opacity(0.45))
                .background {
                    GeometryReader { footerGeo in
                        Color.clear.preference(key: StoryFooterHeightKey.self, value: footerGeo.size.height)
                    }
                }
            }
        }
        .onPreferenceChange(StoryFooterHeightKey.self) { storyFooterHeight = $0 }
        .onPreferenceChange(StoryLeadHeightKey.self) { storyLeadHeight = $0 }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
    }

    /// Darkens only the measured title block, then fades out. The house below stays open.
    private var storyTextVeil: some View {
        let fade: CGFloat = 72
        let covered = max(storyLeadHeight, 0)
        let height = covered + fade
        let solid = covered <= 1 ? 0.72 : covered / height
        return VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.78), location: 0),
                    .init(color: Color.black.opacity(0.62), location: min(0.92, solid)),
                    .init(color: Color.clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: height)
            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func storyHeader(column: CGFloat) -> some View {
        Group {
            if column >= 420 {
                HStack(alignment: .center, spacing: 8) {
                    storyBack
                    cinematicBrand
                    Spacer(minLength: 8)
                    if page < 3 { cinematicSkip }
                }
            } else if column >= 360 {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        storyBack
                        Spacer(minLength: 8)
                        if page < 3 { cinematicSkip }
                    }
                    cinematicBrand
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack { storyBack; Spacer(minLength: 0) }
                    if page < 3 {
                        HStack { Spacer(minLength: 0); cinematicSkip }
                    }
                    cinematicBrand
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var storyBack: some View {
        if showsStoryBack {
            Button(action: retreat) {
                Text("Назад")
                    .font(.body)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: true, vertical: true)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Назад")
            .accessibilityIdentifier("onboarding.flow.back")
        }
    }

    private var showsStoryBack: Bool {
        page > 0 && (page < 3 || allowsIntroReplay)
    }

    private var storyTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(storyLines[0])
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(storyLines[1])
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(ProjectUXColors.accentAction)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(storyHeading.replacingOccurrences(of: "\n", with: " "))
        .accessibilityIdentifier("onboarding.flow.title")
    }

    private var storyLines: [String] {
        let lines = storyHeading.components(separatedBy: "\n")
        return [lines.first ?? "", lines.dropFirst().first ?? ""]
    }

    private var storyHeading: String {
        switch page {
        case 1: return "Важное\nне ускользнёт."
        case 2: return "Деньги понятны.\nОтчёт готов."
        default: return "Ваша стройка.\nНачните здесь."
        }
    }

    private var storySubtitle: some View {
        Text(storySubtitleText)
            .font(.body)
            .foregroundStyle(Color.white.opacity(0.92))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var storySubtitleText: String {
        switch page {
        case 1: return "Проверяйте работы по шагам. Фиксируйте то, что нужно исправить."
        case 2: return "Сравнивайте план и факт. Формируйте отчёт для себя или заказчика."
        default: return "Откройте готовый демо-проект и попробуйте приложение на примере."
        }
    }

    private var storyBody: some View {
        let shown = storyVisible(page)
        return Group {
            switch page {
            case 1:
                checkStory
            case 2:
                moneyStory
            default:
                demoStory
            }
        }
        .opacity(shown ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : 16)
        .accessibilityHidden(!shown)
    }

    private var checkStory: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Гидроизоляция фундамента")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    guard !foundationChecked else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.28)) {
                        foundationChecked = true
                    }
                } label: {
                    HStack(spacing: 10) {
                        ZStack {
                            Circle()
                                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                            if foundationChecked {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.bold))
                                    .foregroundStyle(Color(red: 0.12, green: 0.35, blue: 0.22))
                            }
                        }
                        .frame(width: 28, height: 28)
                        .background(foundationChecked ? Color.green.opacity(0.9) : Color.clear, in: Circle())
                        .accessibilityHidden(true)
                        Text(foundationChecked ? "Выполнено" : "Отметить выполненным")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(foundationChecked ? "Гидроизоляция фундамента, выполнено" : "Отметить выполненным. Гидроизоляция фундамента")
                .accessibilityIdentifier("onboarding.flow.check.toggle")
            }
            .padding(14)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )

            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.16))
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(Color.white)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Замечание")
                        .font(.subheadline.weight(.semibold))
                    Text("К пункту приложено фото")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Замечание. К пункту приложено фото.")
        }
    }

    private var moneyStory: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                moneyLine(title: "План", amount: "1 200 000 ₽", fraction: 1, emphasized: false)
                moneyLine(title: "Факт", amount: "860 000 ₽", fraction: 860.0 / 1200.0, emphasized: true)
            }
            .padding(10)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )

            if reportOpen {
                reportSheet
                    .transition(reduceMotion ? .identity : .opacity)
            }
        }
    }

    private var reportToggleTitle: String {
        reportOpen ? "Скрыть пример отчёта" : "Посмотреть пример отчёта"
    }

    private var reportToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.32)) {
                reportOpen.toggle()
            }
        } label: {
            Text(reportToggleTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 4)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        )
        .accessibilityLabel(reportToggleTitle)
        .accessibilityIdentifier("onboarding.flow.report")
    }

    private func moneyLine(title: String, amount: String, fraction: CGFloat, emphasized: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            OnboardingFitRow(spacing: 12) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
                Text(amount)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(emphasized ? ProjectUXColors.accentAction : Color.white)
                    .monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            GeometryReader { bar in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.22))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(emphasized ? ProjectUXColors.accentAction : Color.white.opacity(0.72))
                            .frame(width: max(0, bar.size.width * fraction))
                    }
            }
            .frame(height: 7)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(amount)")
    }

    private var reportSheet: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BuildChecklists")
                .font(.caption.weight(.semibold))
            Text("Сводный отчёт")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Дом, пример")
                .font(.body.weight(.semibold))
            Text("Гидроизоляция фундамента — выполнено")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Text("План 1 200 000 ₽")
                .font(.body)
            Text("Факт 860 000 ₽")
                .font(.body)
            Text("Общий прогресс: 42%")
                .font(.body)
            Text("Для заказчика формируется отдельный отчёт.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(red: 0.12, green: 0.13, blue: 0.09))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 1, green: 0.98, blue: 0.94), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ProjectUXColors.accentAction)
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Пример сводного отчёта. Дом, пример. Гидроизоляция фундамента выполнена. План 1 200 000 рублей. Факт 860 000 рублей. Общий прогресс 42 процента. Для заказчика формируется отдельный отчёт.")
        .accessibilityIdentifier("onboarding.flow.report.sheet")
        .id("story.sheet")
    }

    private var demoStory: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Демо-проект")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
                Text("Дом, пример")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text("Прогресс 42%")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.accentAction)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Демо-проект. Дом, пример. Прогресс 42 процента.")
        }
    }

    /// Start screen. Theme stays under the buttons when the column fits the container.
    /// When it does not, the theme row sits above the pinned actions and the copy scrolls.
    private func startScreen(width: CGFloat, height: CGFloat, column: CGFloat) -> some View {
        let themeInScroll = startStackHeight > height + 1
        return ZStack(alignment: .top) {
            Group {
                if themeInScroll {
                    PinnedFooterLayout {
                        ScrollView {
                            VStack(spacing: 0) {
                                storyLead(column: column)
                                storyBody
                                    .padding(.horizontal, 24)
                                    .padding(.bottom, 8)
                                    .frame(maxWidth: column, alignment: .leading)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        VStack(spacing: 0) {
                            themeBar(column: column)
                            startActions(column: column, includesTheme: false)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        storyLead(column: column)
                        Spacer(minLength: 0)
                        storyBody
                            .padding(.horizontal, 24)
                            .padding(.bottom, 8)
                            .frame(maxWidth: column, alignment: .leading)
                            .frame(maxWidth: .infinity)
                        startActions(column: column, includesTheme: true)
                    }
                }
            }
            .frame(width: width, height: height, alignment: .top)
            .clipped()
            startColumn(column: column)
                .frame(width: width, alignment: .topLeading)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: StartStackHeightKey.self, value: proxy.size.height)
                    }
                }
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(width: width, height: height, alignment: .top)
        .clipped()
        .onPreferenceChange(StartStackHeightKey.self) { startStackHeight = $0 }
    }

    private func startColumn(column: CGFloat) -> some View {
        VStack(spacing: 0) {
            storyLead(column: column)
            Spacer(minLength: 0)
            storyBody
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .frame(maxWidth: column, alignment: .leading)
                .frame(maxWidth: .infinity)
            startActions(column: column, includesTheme: true)
        }
    }

    private func themeBar(column: CGFloat) -> some View {
        themeMenu
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            .frame(maxWidth: column)
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.45))
    }

    private func storyLead(column: CGFloat) -> some View {
        VStack(spacing: 0) {
            storyHeader(column: column)
            VStack(alignment: .leading, spacing: 12) {
                storyTitle
                storySubtitle
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 8)
            .frame(maxWidth: column)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            GeometryReader { lead in
                Color.clear.preference(key: StoryLeadHeightKey.self, value: lead.size.height)
            }
        }
    }

    private func startActions(column: CGFloat, includesTheme: Bool) -> some View {
        VStack(spacing: 8) {
            Text("Демо — учебный пример. Для работы со своим объектом создайте профиль.")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actionButton(
                "Попробовать демо",
                identifier: "onboarding.flow.demo",
                filled: true,
                action: tryDemo
            )
            storySecondaryButton(
                "Создать профиль",
                identifier: "onboarding.flow.profile",
                action: createProfile
            )
            if includesTheme {
                themeMenu
            }
        }
        .frame(maxWidth: column)
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.45))
    }

    @ViewBuilder
    private var storyFooter: some View {
        VStack(spacing: 8) {
            if page == 2 {
                reportToggle
            }
            if page < 3 {
                storyDots
                actionButton(
                    "Далее",
                    identifier: "onboarding.flow.next",
                    filled: true,
                    action: advance
                )
            }
        }
    }

    private func storySecondaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 1)
        )
        .accessibilityIdentifier(identifier)
    }

    private var storyDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == page ? ProjectUXColors.accentAction : Color.white.opacity(0.45))
                    .frame(width: index == page ? 18 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Экран \(page + 1) из 3")
        .accessibilityIdentifier("onboarding.flow.page.\(page)")
    }

    private func storyVisible(_ target: Int) -> Bool {
        reduceMotion || revealedPages.contains(target)
    }

    private func beginStoryReveal(_ target: Int) {
        revealTask?.cancel()
        revealTask = nil
        guard target > 0 else { return }
        if reduceMotion || revealedPages.contains(target) {
            revealedPages.insert(target)
            return
        }
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled, page == target else { return }
            _ = withAnimation(.easeOut(duration: 0.42)) {
                revealedPages.insert(target)
            }
            revealTask = nil
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                let travel = value.translation.width
                guard abs(travel) > abs(value.translation.height), abs(travel) > 48 else { return }
                if travel < 0 {
                    advance()
                } else {
                    retreat()
                }
            }
    }

    private var themeTitle: String {
        switch appColorScheme {
        case "dark": return "Тёмная"
        case "light": return "Светлая"
        default: return "Системная"
        }
    }

    private var themeValue: String {
        switch appColorScheme {
        case "light", "dark": return appColorScheme
        default: return "system"
        }
    }

    private var themeMenu: some View {
        Menu {
            themeChoice("system", "Системная")
            themeChoice("light", "Светлая")
            themeChoice("dark", "Тёмная")
        } label: {
            Text("Тема: \(themeTitle)")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.92))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Тема: \(themeTitle)")
        .accessibilityIdentifier("onboarding.flow.theme")
    }

    private func themeChoice(_ value: String, _ title: String) -> some View {
        Button {
            appColorScheme = value
        } label: {
            if themeValue == value {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .accessibilityIdentifier("onboarding.flow.theme.\(value)")
    }

    private func actionButton(
        _ title: String,
        identifier: String,
        filled: Bool,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(filled ? ProjectUXColors.onAccent : OnboardingChrome.primary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(filled ? ProjectUXColors.accentAction : OnboardingChrome.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(filled ? Color.clear : OnboardingChrome.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .modifier(OnboardingHint(text: hint))
    }


    private func cinematicScreen(width: CGFloat, height: CGFloat, column: CGFloat) -> some View {
        return ZStack {
            cinematicVeil
            VStack(spacing: 0) {
                cinematicHeader(column: column)
                GeometryReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            cinematicTitle
                            Text("Этапы, проверки и расходы вашей стройки — в одном месте")
                                .font(.body)
                                .foregroundStyle(Color.white.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                            .opacity(titleVisible ? 1 : 0)
                            .offset(y: titleVisible ? 0 : 12)
                            .accessibilityHidden(!titleVisible)
                        }
                        .frame(maxWidth: column, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: proxy.size.height, alignment: .top)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }

                VStack(spacing: 8) {
                    cinematicExamples(column: column)
                    cinematicDots
                    actionButton(
                        "Посмотреть, как это работает",
                        identifier: "onboarding.flow.next",
                        filled: true,
                        action: advance
                    )
                }
                .frame(maxWidth: column)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .onAppear(perform: beginIntroIfNeeded)
    }

    private func houseFrame(width: CGFloat, height: CGFloat) -> some View {
        let scale = max(width / 666, height / 1000)
        let displayedHeight = 1000 * scale
        let overflow = max(0, displayedHeight - height)
        let focal = displayedHeight * 0.42
        let shift = min(max(0, focal - height * 0.45), overflow)
        return Image("OnboardingHouse")
            .resizable()
            .interpolation(.high)
            .scaledToFill()
            .frame(width: width, height: height, alignment: .top)
            .scaleEffect(houseResting ? 1 : 1.06, anchor: .top)
            .scaleEffect(storyScale, anchor: .center)
            .offset(x: storyDrift, y: (houseResting ? 0 : 18) - shift)
            .frame(width: width, height: height)
            .clipped()
            .accessibilityHidden(true)
    }

    private var cinematicVeil: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(0.55), location: 0),
                .init(color: Color.black.opacity(0.22), location: 0.18),
                .init(color: Color.black.opacity(0.02), location: 0.34),
                .init(color: Color.clear, location: 0.46),
                .init(color: Color.clear, location: 0.62),
                .init(color: Color.black.opacity(0.28), location: 0.78),
                .init(color: Color.black.opacity(0.72), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func cinematicHeader(column: CGFloat) -> some View {
        Group {
            if column >= 360 {
                HStack(alignment: .center, spacing: 8) {
                    cinematicBrand
                    Spacer(minLength: 12)
                    cinematicSkip
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        cinematicMark
                        Spacer(minLength: 8)
                        cinematicSkip
                    }
                    Text("BuildChecklists")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("BuildChecklists")
                        .accessibilityIdentifier("onboarding.flow.container.\(measuredWidth)")
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var cinematicBrand: some View {
        HStack(spacing: 8) {
            cinematicMark
            Text("BuildChecklists")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BuildChecklists")
        .accessibilityIdentifier("onboarding.flow.container.\(measuredWidth)")
    }

    private var cinematicMark: some View {
        Image("OnboardingMark")
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)
    }

    private var cinematicSkip: some View {
        Button(action: skip) {
            Text("Пропустить")
                .font(.body)
                .foregroundStyle(Color.white)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 4)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Пропустить")
        .accessibilityIdentifier("onboarding.flow.skip")
    }

    private var cinematicTitle: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Стройте.")
                .foregroundStyle(Color.white)
            Text("Без хаоса.")
                .foregroundStyle(ProjectUXColors.accentAction)
        }
        .font(.largeTitle.weight(.bold))
        .fixedSize(horizontal: false, vertical: true)
        .opacity(titleVisible ? 1 : 0)
        .offset(y: titleVisible ? 0 : 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Стройте. Без хаоса.")
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("onboarding.flow.title")
        .accessibilityHidden(!titleVisible)
    }

    private var titleVisible: Bool { titleShown || reduceMotion }
    private var houseResting: Bool { houseSettled || reduceMotion }
    private var checkVisible: Bool { checkShown || reduceMotion }
    private var storyScale: CGFloat {
        if reduceMotion { return 1 }
        switch page {
        case 1: return 1.06
        case 2: return 1.04
        default: return 1
        }
    }
    private var storyDrift: CGFloat {
        if reduceMotion { return 0 }
        switch page {
        case 1: return -22
        case 2: return 20
        default: return 0
        }
    }

    private func cinematicExamples(column: CGFloat) -> some View {
        let row = column >= 360
        return Group {
            if row {
                HStack(alignment: .center, spacing: 10) {
                    foundationCheck
                    objectProgress
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    foundationCheck
                    objectProgress
                }
            }
        }
        .opacity(checkVisible ? 1 : 0)
        .offset(y: checkVisible ? 0 : 16)
        .accessibilityHidden(!checkVisible)
    }

    private var foundationCheck: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ProjectUXColors.progressComplete)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Фундамент")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Выполнено")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Фундамент, выполнено")
        .accessibilityIdentifier(checkVisible ? "onboarding.flow.check.shown" : "onboarding.flow.check.pending")
    }

    private var objectProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Прогресс")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("42%")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ProjectUXColors.accentAction)
                    .monospacedDigit()
            }
            GeometryReader { bar in
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.28))
                    .overlay(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(ProjectUXColors.accentAction)
                            .frame(width: bar.size.width * 0.42)
                    }
            }
            .frame(height: 6)
            .frame(minWidth: 88)
            .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Прогресс 42 процента")
    }

    private var cinematicDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(index == 0 ? ProjectUXColors.accentAction : Color.white.opacity(0.45))
                    .frame(width: index == 0 ? 18 : 8, height: 8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Экран 1 из 3")
        .accessibilityIdentifier("onboarding.flow.page.0")
    }

    private func beginIntroIfNeeded() {
        guard page == 0 else { return }
        if reduceMotion {
            stopIntro()
            return
        }
        if introPlayed {
            if introTask == nil {
                houseSettled = true
                titleShown = true
                checkShown = true
            }
            return
        }
        introPlayed = true
        houseSettled = false
        titleShown = false
        checkShown = false
        introTask?.cancel()
        introTask = Task { @MainActor in
            withAnimation(.easeOut(duration: 1.05)) { houseSettled = true }
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.48)) { titleShown = true }
            try? await Task.sleep(nanoseconds: 460_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.42)) { checkShown = true }
            introTask = nil
        }
    }

    private func stopIntro() {
        introTask?.cancel()
        introTask = nil
        introPlayed = true
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            houseSettled = true
            titleShown = true
            checkShown = true
        }
    }

    private func tryDemo() {
        hasSeenOnboarding = true
        store.enterDemoMode()
    }

    private func createProfile() {
        hasSeenOnboarding = true
        showRegister = true
    }

    private func advance() {
        guard page < pageCount - 1 else { return }
        skipOrigin = nil
        page += 1
    }

    private func retreat() {
        guard page > 0 else { return }
        if page == pageCount - 1, !allowsIntroReplay { return }
        if page == pageCount - 1, let origin = skipOrigin {
            skipOrigin = nil
            page = origin
            return
        }
        skipOrigin = nil
        page -= 1
    }

    private func skip() {
        guard page < pageCount - 1 else { return }
        skipOrigin = page
        page = pageCount - 1
    }
}

/// Keeps a footer at its ideal height and gives the rest of a bounded container to the content.
private struct PinnedFooterLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let footer = subviews[1].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        let scrollHeight = max(0, bounds.height - footer.height)
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: scrollHeight)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.maxY - footer.height),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: footer.height)
        )
    }
}

private struct StartStackHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StoryLeadHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct StoryFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct OnboardingHint: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.accessibilityHint(text)
        } else {
            content
        }
    }
}

private enum OnboardingChrome {
    static var background: Color { ProjectUXColors.screenBackground }
    static var card: Color { ProjectUXColors.cardSurface }
    static var primary: Color { ProjectUXColors.primaryText }
    static var secondary: Color { ProjectUXColors.secondaryText }
    static var border: Color { ProjectUXColors.readableBorder }
    static var dot: Color { Color.secondary.opacity(0.35) }
}

/// Places two labels on one line when both fit. Otherwise the second goes under the first, without shrinking type.
private struct OnboardingFitRow: Layout {
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count >= 2 else { return .zero }
        let limit = proposal.width ?? .greatestFiniteMagnitude
        let first = subviews[0].sizeThatFits(.unspecified)
        let second = subviews[1].sizeThatFits(.unspecified)
        if first.width + spacing + second.width <= limit + 0.5 {
            return CGSize(width: limit, height: max(first.height, second.height))
        }
        let stackedFirst = subviews[0].sizeThatFits(ProposedViewSize(width: limit, height: nil))
        let stackedSecond = subviews[1].sizeThatFits(ProposedViewSize(width: limit, height: nil))
        return CGSize(width: limit, height: stackedFirst.height + 2 + stackedSecond.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count >= 2 else { return }
        let firstIdeal = subviews[0].sizeThatFits(.unspecified)
        let secondIdeal = subviews[1].sizeThatFits(.unspecified)
        if firstIdeal.width + spacing + secondIdeal.width <= bounds.width + 0.5 {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: firstIdeal.width, height: firstIdeal.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.minY),
                anchor: .topTrailing,
                proposal: ProposedViewSize(width: secondIdeal.width, height: secondIdeal.height)
            )
        } else {
            let stackedFirst = subviews[0].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: stackedFirst.height)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + stackedFirst.height + 2),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: nil)
            )
        }
    }
}


#Preview("Светлая") {
    OnboardingFlowView(showRegister: .constant(false))
        .environmentObject(AppStore())
}

#Preview("Тёмная") {
    OnboardingFlowView(showRegister: .constant(false))
        .environmentObject(AppStore())
        .preferredColorScheme(.dark)
}
