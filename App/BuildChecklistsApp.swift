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
/// Логика:
/// - Если онбординг ещё не пройден → OnboardingView.
/// - Если пользователь зарегистрирован ИЛИ он в демо-режиме → показываем основное приложение (MainTabView).
/// - Если не зарегистрирован и не демо → показываем Welcome.
private struct RootView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("bc_has_seen_onboarding") private var hasSeenOnboarding: Bool = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView()
            } else {
                NavigationStack {
                    Group {
                        if store.isRegistered || store.isDemoMode {
                            MainTabView()
                        } else {
                            WelcomeView()
                        }
                    }
                }
                .task {
                    await store.bootstrap()
                }
            }
        }
        .onAppear {
            BCTiming.log("RootView onAppear (первый UI показан)")
        }
    }
}
