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
    @EnvironmentObject private var store: AppStore
    @State private var stages: [Stage] = []
    @State private var progressEpoch = IssueProgressEpoch.current

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                stageLink(at: i)

                if i == 0, store.showsDemoCoach(.openFirstGroup), project.id == store.sessionDemoProjectID {
                    DemoCoachNote(
                        text: "Здесь собраны проверки этапа. Откройте первую группу",
                        identifier: "demo.coach.firstGroup"
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Геология")
        .onAppear {
            initialLoad()
            if project.id == store.sessionDemoProjectID {
                store.advanceDemoCoach(from: .openGeology, to: .openFirstGroup)
            }
        }
        .onChange(of: stages) { _, newValue in
            let result = IssueProgressSaveFeedback.apply(
                outcome: GeologyProgressStore.save(projectID: project.id, stages: newValue, epoch: progressEpoch),
                stages: newValue,
                epoch: progressEpoch,
                reload: { GeologyProgressStore.load(projectID: project.id) ?? [] }
            )
            progressEpoch = result.epoch
            if result.stages != stages {
                stages = result.stages
            }
        }
    }

    @ViewBuilder
    private func stageLink(at i: Int) -> some View {
        let stage = stages[i]
        let stageProgress = progress(for: i)

        NavigationLink {
            StageDetailView2(
                stage: binding(at: i),
                project: project,
                pack: .geology,
                progressEpoch: $progressEpoch,
                acceptsDemoMark: i == 0 && project.id == store.sessionDemoProjectID,
                onStageChanged: {
                    // Сохранение и уведомление теперь централизованы в onChange(of: stages)
                }
            )
        } label: {
            StageGroupProgressCardLabel(
                title: stage.title,
                subtitle: geologySubtitle(for: stage.title),
                progress: stageProgress,
                issueCount: ChecklistStageBulkActions.issueCount(in: stage.items)
            )
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(i == 0 ? "geology.group.first" : "geology.group.\(i)")
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
