import SwiftUI
import CoreFoundation

// MARK: - Debug-диагностика времени запуска (фильтр в консоли: BC_TIMING)

enum BCTiming {
    private static var launchTime: CFAbsoluteTime = 0
    static func ms() -> Int {
        if launchTime == 0 { launchTime = CFAbsoluteTimeGetCurrent() }
        return Int((CFAbsoluteTimeGetCurrent() - launchTime) * 1000)
    }
    static func log(_ msg: String) {
        debugPrint("[BC_TIMING] \(ms()) ms - \(msg)")
    }
}

@main
struct BuildChecklistsApp: App {
    @StateObject private var store = AppStore()
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                // Акцентный цвет для всего UI
                .tint(Color("AccentYellow"))
                .accentColor(Color("AccentYellow"))
                // Тема приложения (system / light / dark) — применяется ко всему UI
                .preferredColorScheme(
                    appColorScheme == "system"
                    ? nil
                    : (appColorScheme == "dark" ? .dark : .light)
                )
        }
    }
}

/// Корневой экран.
///
/// Слайды не зависят от ключа прохождения: запись ключа не подменяет текущее представление.
/// Зарегистрированный пользователь читается с диска до онбординга. Полный bootstrap во время слайдов не идёт.
private struct RootView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("bc_has_seen_onboarding") private var hasSeenOnboarding = false
    @State private var showRegister = false

    private var showsOnboarding: Bool {
        if store.isDemoMode { return false }
        if showRegister { return true }
        if store.isRegistered || store.persistedRegistrationFlag() { return false }
        return true
    }

    var body: some View {
        Group {
            if store.isDemoMode || (store.isMainDataReady && !showsOnboarding) {
                NavigationStack {
                    MainTabView()
                }
            } else if showsOnboarding {
                OnboardingFlowView(
                    initialPage: hasSeenOnboarding ? 3 : 0,
                    showRegister: $showRegister
                )
            } else {
                Color(.systemBackground)
                    .ignoresSafeArea()
            }
        }
        .task(id: "root-launch") {
            guard !store.isDemoMode else { return }
            guard store.isRegistered || store.persistedRegistrationFlag() else { return }
            await store.prepareMainDataIfNeeded()
        }
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(store)
        }
        .onAppear {
            BCTiming.log("RootView onAppear (первый UI показан)")
        }
    }
}
