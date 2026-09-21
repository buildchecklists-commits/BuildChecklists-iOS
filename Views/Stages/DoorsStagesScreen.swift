import SwiftUI

// Если появятся варианты дверей — можно вычислять ID из project.meta
private func doorsTypeID(for project: Project) -> String { "default" }

// Подзаголовки строго под наши 5 этапов дверей
private func doorsSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Этап 1. Замер/проект":
            "Замеры проёмов, подбор полотен и фурнитуры, спецификация",

        "Этап 2. Проёмы/подготовка":
            "Очистка и геометрия проёмов, усиление, пороги, закладные",

        "Этап 3. Монтаж коробки":
            "Позиционирование, крепёж коробки, пена, доборы",

        "Этап 4. Полотно и примыкания":
            "Навеска полотна, замки, доводчики, порог, уплотнители",

        "Этап 5. Паспорт/приёмка":
            "Паспорт, безопасность, финальная проверка и инструкции"
    ]
    return map[title] ?? "Двери — монтаж, примыкания и приёмка"
}

struct DoorsStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "default"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = doorsSubtitle(for: title)
                let prog = stageProgress(stage)
                let label = progressLabel(prog)
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        onStageChanged: {
                            // Сохранение и уведомление — только в onChange(of: stages)
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(title)
                                    .font(.headline)

                                Text(subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(label)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule().fill(
                                        isCompleted
                                        ? Color.green.opacity(0.9)
                                        : Color("AccentYellow").opacity(0.9)
                                    )
                                )
                                .foregroundColor(.black.opacity(0.9))
                        }

                        ProgressView(value: prog)
                            .tint(Color("AccentYellow"))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
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
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Двери")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Initial load

    private func initialLoad() {
        typeID = doorsTypeID(for: project)

        if let saved = DoorsProgressStore.load(projectID: project.id),
           !saved.isEmpty {
            stages = saved
        } else {
            stages = DoorsStagesProvider.loadStages(for: typeID)
            // Сохранением займётся onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        DoorsProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(
            name: .bcProgressDidChange,
            object: nil
        )
    }

    // MARK: - Bindings

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(
            get: { stages[i] },
            set: { stages[i] = $0 }
        )
    }

    // MARK: - Progress

    private func stageProgress(_ stage: Stage) -> Double {
        let items = stage.items
        guard !items.isEmpty else { return 0 }
        let done = items.filter { $0.status == .ok }.count
        return Double(done) / Double(items.count)
    }

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если прогресс 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
