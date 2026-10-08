import SwiftUI

/// Label for intermediate checklist **group** cards (Geology → group, Foundation → group, …).
/// Shows active `.issue` items from that group only; hidden when the count is zero (no empty gap).
struct StageGroupProgressCardLabel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    var subtitle: String = ""
    let progress: Double
    let issueCount: Int

    private var clampedProgress: Double {
        let value = progress.isNaN ? 0 : progress
        return min(max(value, 0), 1)
    }

    private var percent: Int {
        Int((clampedProgress * 100).rounded())
    }

    private var isCompleted: Bool {
        clampedProgress >= 0.999
    }

    /// Accessibility sizes: stack the percent under the title so the name can use full width.
    private var stacksPercentBelowTitle: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if stacksPercentBelowTitle {
                VStack(alignment: .leading, spacing: 8) {
                    titleBlock
                    percentBadge
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    titleBlock
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)
                    percentBadge
                        .layoutPriority(1)
                }
            }

            if issueCount > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(ProjectUXCopy.remarksPhrase(issueCount))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ProjectUXColors.issue)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            }

            // Custom bar keeps a real intrinsic height (system ProgressView can collapse in List).
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.12))
                    Capsule()
                        .fill(Color("AccentYellow"))
                        .frame(width: max(0, geo.size.width * clampedProgress))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isCompleted
                    ? Color.green.opacity(0.35)
                    : Color.white.opacity(0.08),
                    lineWidth: 1
                )
        )
        .shadow(
            color: Color.black.opacity(0.08),
            radius: 6,
            x: 0,
            y: 3
        )
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOverLabel)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var percentBadge: some View {
        Text("\(percent)%")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(
                        isCompleted
                        ? Color.green.opacity(0.9)
                        : Color("AccentYellow").opacity(0.9)
                    )
            )
            .foregroundColor(.black.opacity(0.9))
            .fixedSize(horizontal: true, vertical: true)
    }

    private var voiceOverLabel: String {
        var parts = [title]
        if !subtitle.isEmpty {
            parts.append(subtitle)
        }
        parts.append("\(percent) процентов")
        if issueCount > 0 {
            parts.append(ProjectUXCopy.remarksPhrase(issueCount))
        }
        return parts.joined(separator: ", ")
    }
}

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
