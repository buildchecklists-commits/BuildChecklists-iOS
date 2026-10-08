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
    @State private var progressEpoch = IssueProgressEpoch.current
    @State private var typeID: String = "default"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = doorsSubtitle(for: title)
                let prog = stageProgress(stage)

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        pack: .doors,
                        progressEpoch: $progressEpoch,
                        onStageChanged: {
                            // Сохранение и уведомление — только в onChange(of: stages)
                        }
                    )
                } label: {
                    StageGroupProgressCardLabel(
                        title: title,
                        subtitle: subtitle,
                        progress: prog,
                        issueCount: ChecklistStageBulkActions.issueCount(in: stage.items)
                    )
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
        let result = IssueProgressSaveFeedback.apply(
            outcome: DoorsProgressStore.save(projectID: project.id, stages: newStages, epoch: progressEpoch),
            stages: newStages,
            epoch: progressEpoch,
            reload: { DoorsProgressStore.load(projectID: project.id) ?? [] }
        )
        progressEpoch = result.epoch
        if result.stages != stages {
            stages = result.stages
        }
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

}
