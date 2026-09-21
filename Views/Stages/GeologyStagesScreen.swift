import SwiftUI

private func geologySubtitle(for title: String) -> String {
    // Короткие подсказки под названием этапа
    switch title {
    case _ where title.contains("Полевые"):
        return "Точки/глубины бурения, УГВ, отбор образцов"
    case _ where title.contains("Лаборатория"):
        return "Испытания образцов, протоколы, привязка к скважинам"
    case _ where title.contains("Отчёт"):
        return "Разрезы, рекомендации по фундаменту и подготовке"
    default:
        return ""
    }
}

struct GeologyStagesScreen: View {
    let project: Project
    @State private var stages: [Stage] = []

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = stages[i]
                let stageProgress = progress(for: i)
                let percent = Int((stageProgress * 100).rounded())
                let isCompleted = stageProgress >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        onStageChanged: {
                            // Сохранение и уведомление теперь централизованы в onChange(of: stages)
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.title)
                                    .font(.headline)

                                let sub = geologySubtitle(for: stage.title)
                                if !sub.isEmpty {
                                    Text(sub)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

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
                        }

                        ProgressView(value: stageProgress)
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
        .navigationTitle("Геология")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            // Единственная точка сохранения прогресса и нотификации
            GeologyProgressStore.save(projectID: project.id, stages: newValue)
            NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        if let saved = GeologyProgressStore.load(projectID: project.id), !saved.isEmpty {
            // Загружаем ранее сохранённые стадии
            stages = saved
        } else {
            // Первичная инициализация стадий
            stages = GeologyStagesProvider.loadStages()
            // Сохранением и нотификацией займётся onChange(of: stages)
        }
    }

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(
            get: { stages[i] },
            set: { stages[i] = $0 }
        )
    }

    private func progress(for i: Int) -> Double {
        let total = max(stages[i].items.count, 1)
        let done  = stages[i].items.filter { $0.status == .ok }.count
        return Double(done) / Double(total)
    }
}
