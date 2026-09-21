import SwiftUI

/// Универсальная карточка-строка списка этапов с мини-прогрессом.
/// Внутри — NavigationLink, поэтому карточка сама пушит destination.
struct StageListCard<Destination: View>: View {
    var title: String
    var subtitle: String?
    var progress: Double   // 0...1
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Мини-прогресс под карточкой
                HStack(spacing: 8) {
                    ProgressView(value: progress)
                        .tint(Color("AccentYellow"))
                    Text(progressLabel(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .trailing)
                }
                .padding(.top, 2)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
    }

    private func progressLabel(_ value: Double) -> String {
        // Показываем проценты; если 0 — «Нет данных»
        if value.isNaN || value <= 0 { return "Нет данных" }
        return "\(Int((value * 100).rounded()))%"
    }
}

// Превью (можно удалить)
#Preview {
    NavigationStack {
        List {
            StageListCard(title: "Отчёт геологии",
                          subtitle: "Договор, точки бурения, журналы, паспорт",
                          progress: 0.35) {
                Text("Destination")
            }
        }.listStyle(.insetGrouped)
    }
}
