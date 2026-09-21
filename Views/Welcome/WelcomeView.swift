import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: AppStore
    @State private var showRegister = false

    @AppStorage("appColorScheme") private var appColorScheme: String = "system"
    @State private var showThemeHint = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                // Фон
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Верхний отступ под "плашку" темы
                        Color.clear.frame(height: 14)

                        // Header
                        header
                            .padding(.top, 8)
                            .padding(.horizontal, 18)

                        // Основной продающий блок
                        valueCard
                            .padding(.top, 14)
                            .padding(.horizontal, 18)

                        // Отступ перед кнопками
                        Color.clear.frame(height: 12)

                        // Низ: кнопки + дисклеймер — прокручиваются вместе с контентом
                        bottomButtons
                            .padding(.horizontal, 18)
                            .padding(.bottom, max(14, geo.safeAreaInsets.bottom))
                    }
                }

                // Переключатель темы (незаметный, справа сверху)
                themeControl
                    .padding(.top, 10)
                    .padding(.trailing, 14)
            }
        }
        .sheet(isPresented: $showRegister) {
            RegisterView()
                .environmentObject(store)
        }
    }

    // MARK: - UI blocks

    private var header: some View {
        VStack(spacing: 6) {
            Text("Добро пожаловать в Build Checklists")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)

            Text("Управляйте стройкой как прораб — по этапам, задачам и бюджету.")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    private var valueCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ValueRow(
                icon: "sparkles",
                title: "Стройка без хаоса",
                subtitle: "Всё по объекту — в одном месте: этапы, задачи, деньги, фото и контакты."
            )

            ValueRow(
                icon: "checklist",
                title: "Чек-листы по этапам",
                subtitle: "Что должно быть сделано + частые ошибки — чтобы не пропустить важное."
            )

            ValueRow(
                icon: "chart.pie.fill",
                title: "Деньги под контролем",
                subtitle: "План/факт, наглядные графики, отчёты — до рубля понятно, куда ушло."
            )

            ValueRow(
                icon: "calendar.badge.exclamationmark",
                title: "Сроки и просрочки",
                subtitle: "Карта дедлайнов по этапам + причины задержек — без “мы не успели и всё”."
            )

            ValueRow(
                icon: "camera.fill",
                title: "Фотофиксация работ",
                subtitle: "Фиксируйте ошибки и правильные решения — потом легко найти нужный кадр."
            )

            ValueRow(
                icon: "person.crop.circle.badge.checkmark",
                title: "Контакты всегда под рукой",
                subtitle: "Подрядчики, поставщики, сервисы по этапам — больше ничего не теряется."
            )

            ValueRow(
                icon: "hand.tap.fill",
                title: "Проверка на объекте — 1 тап",
                subtitle: "Открыли проект — и пошли по чек-листу прямо на стройке."
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(.systemGray4), lineWidth: 1)
        )
    }

    private var bottomButtons: some View {
        VStack(spacing: 12) {
            Button {
                // Включаем демо и сразу просим уведомления (один раз)
                store.enterDemoMode()
                TaskNotificationService.shared.requestAuthorizationOnce()
            } label: {
                Text("Попробовать демо")
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                showRegister = true
            } label: {
                Text("Создать профиль")
            }
            .buttonStyle(SecondaryButtonStyle())

            Text("В демо-режиме данные не сохраняются после закрытия приложения.\nДля постоянной работы создайте профиль.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 2)
        }
    }

    private var themeControl: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Menu {
                Button {
                    appColorScheme = "system"
                } label: {
                    Label("Системная", systemImage: "circle.lefthalf.filled")
                }

                Button {
                    appColorScheme = "light"
                } label: {
                    Label("Светлая", systemImage: "sun.max.fill")
                }

                Button {
                    appColorScheme = "dark"
                } label: {
                    Label("Тёмная", systemImage: "moon.stars.fill")
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "paintbrush")
                        .font(.system(size: 13, weight: .semibold))
                    Text(themeLabel)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color(.systemGray4), lineWidth: 1)
                )
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Лёгкая подсказка (не мешает)
                showThemeHint = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    showThemeHint = false
                }
            })

            if showThemeHint {
                Text("Тема интерфейса")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showThemeHint)
    }

    private var themeLabel: String {
        switch appColorScheme {
        case "dark": return "Тёмная"
        case "light": return "Светлая"
        default: return "Системная"
        }
    }
}

// MARK: - Small rows

private struct ValueRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color("AccentYellow"))
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
    }
}
