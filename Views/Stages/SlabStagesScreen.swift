import SwiftUI

// Преобразуем Optional SlabType -> String ID для имен файлов JSON (slab_*.json)
private func slabTypeID(_ t: SlabType?) -> String {
    switch t {
    case .some(.mono):  return "monolithic"   // slab_monolithic.json
    case .some(.pb):    return "pb"           // slab_pb.json
    case .some(.pc):    return "pc"           // slab_pc.json (на будущее)
    case .some(.steel): return "steel"        // slab_steel.json
    case .some(.wood):  return "wood"         // slab_wood.json
    case .none:         return "monolithic"   // дефолт — монолит
    }
}

private func slabStageSubtitle(_ stage: Stage) -> String {
    let t = stage.title.lowercased()

    if t.contains("схема") || t.contains("подготов") {
        return "Схема раскладки, опоры, выпуски"
    } else if t.contains("поставка") || t.contains("осмотр") || t.contains("складирован") {
        return "Марки плит, дефекты, складирование"
    } else if t.contains("монтаж") {
        return "Строповка, установка, выравнивание"
    } else if t.contains("швы") || t.contains("пояс") || t.contains("монолит") {
        return "Стыки, шпонки, монолитные зоны"
    } else if t.contains("зимн") {
        return "Температура, укрытие, ПМД"
    } else if t.contains("приём") || t.contains("прием") {
        return "Ровность, дефекты, документы"
    } else {
        return "Перекрытие: этапы подготовки и монтажа"
    }
}

struct SlabStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var progressEpoch = IssueProgressEpoch.current
    @State private var typeID: String = "monolithic"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let subtitle = slabStageSubtitle(stage)
                let prog = progress(for: stage)

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        pack: .slab,
                        progressEpoch: $progressEpoch,
                        onStageChanged: {
                            // сохранение и уведомление централизованы в onChange(of: stages)
                        }
                    )
                } label: {
                    StageGroupProgressCardLabel(
                        title: stage.title,
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
        .navigationTitle("Перекрытия")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        // В Project должен быть slabType: SlabType?
        typeID = slabTypeID(project.slabType)

        // Загружаем сохранённые стадии с учётом актуального шаблона для данного типа перекрытия
        if let saved = SlabProgressStore.load(projectID: project.id, typeID: typeID),
           !saved.isEmpty {
            stages = saved
        } else {
            // Первичная инициализация по шаблону для выбранного типа перекрытия
            stages = SlabStagesProvider.loadStages(for: typeID)
            // сохранением займётся onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        let result = IssueProgressSaveFeedback.apply(
            outcome: SlabProgressStore.save(projectID: project.id, stages: newStages, epoch: progressEpoch),
            stages: newStages,
            epoch: progressEpoch,
            reload: { SlabProgressStore.load(projectID: project.id) ?? [] }
        )
        progressEpoch = result.epoch
        if result.stages != stages {
            stages = result.stages
        }
    }

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(
            get: { stages[i] },
            set: { stages[i] = $0 }
        )
    }

    private func progress(for stage: Stage) -> Double {
        let items = max(stage.items.count, 1)
        let done  = stage.items.filter { $0.status == .ok }.count
        return Double(done) / Double(items)
    }

}
