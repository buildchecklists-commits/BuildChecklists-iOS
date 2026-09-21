import SwiftUI

/// Экран "Что нового" — показывается один раз после обновления приложения.
/// Закрытие по кнопке "Понятно" сохраняет текущую версию в UserDefaults.
struct WhatsNewView: View {
    @Binding var isPresented: Bool

    private static let userDefaultsKey = "bc_last_seen_whats_new_version"

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        bulletSection(
                            title: "Демо-проект с обучением",
                            detail: "Добавили интерактивный демо-проект с подсказками по основным разделам приложения."
                        )
                        bulletSection(
                            title: "Проще разобраться в приложении",
                            detail: "Теперь можно быстро понять, как работают проекты, сроки, бюджет, фото и профиль."
                        )
                        bulletSection(
                            title: "Улучшено отображение экранов",
                            detail: "Интерфейс стал стабильнее и аккуратнее на разных моделях iPhone."
                        )
                        bulletSection(
                            title: "Исправлены ошибки и улучшена стабильность",
                            detail: "Поработали над качеством работы приложения и устранили ряд проблем в интерфейсе."
                        )
                    }
                    .padding(.top, 8)
                }

                Button {
                    UserDefaults.standard.set(currentVersion, forKey: Self.userDefaultsKey)
                    isPresented = false
                } label: {
                    Text("Понятно")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color("AccentYellow"))
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 20)
            .navigationTitle("Что нового")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func bulletSection(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color("AccentYellow"))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}
