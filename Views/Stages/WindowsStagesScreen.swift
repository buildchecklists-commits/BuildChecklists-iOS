import SwiftUI

// Тип окон — пока один, но структура позволяет в будущем расширить
private func windowsTypeID(for project: Project) -> String { "default" }

// Подзаголовки строго под 5 этапов окон
private func windowsSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Этап 1. Замер/проект": "Замеры, профиль, стеклопакеты, спецификация",
        "Этап 2. Проёмы/подготовка": "Геометрия, опорный профиль, ленты, подготовка",
        "Этап 3. Монтаж": "Рама, пена, створки, регулировка",
        "Этап 4. Примыкания": "Подоконник, откосы, отлив, герметизация",
        "Этап 5. Паспорт/приёмка": "Паспорт, гарантия, финальная проверка"
    ]
    return map[title] ?? "Монтаж, примыкания, приёмка"
}

struct WindowsStagesScreen: View {
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
                let subtitle = windowsSubtitle(for: title)
                let prog = stageProgress(stage)

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        pack: .windows,
                        progressEpoch: $progressEpoch,
                        onStageChanged: {}
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
        .navigationTitle("Окна")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Load

    private func initialLoad() {
        typeID = windowsTypeID(for: project)

        // ⬇⬇⬇ КЛЮЧЕВАЯ СТРОКА — здесь включён MERGE через новый метод
        if let saved = WindowsProgressStore.load(projectID: project.id, typeID: typeID),
           !saved.isEmpty {
            stages = saved
        } else {
            stages = WindowsStagesProvider.loadStages(for: typeID)
            // Сохранением займётся onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        let result = IssueProgressSaveFeedback.apply(
            outcome: WindowsProgressStore.save(projectID: project.id, stages: newStages, epoch: progressEpoch),
            stages: newStages,
            epoch: progressEpoch,
            reload: { WindowsProgressStore.load(projectID: project.id) ?? [] }
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
