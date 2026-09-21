import SwiftUI

// Преобразуем Optional FoundationType -> String ID для имен файлов JSON
private func foundationTypeID(_ t: FoundationType?) -> String {
    switch t {
    case .some(.strip): return "foundation_strip"
    case .some(.slab):  return "foundation_slab"
    case .some(.pile):  return "foundation_pile"
    case .some(.tise):  return "foundation_tise"
    case .some(.combo): return "foundation_combo"
    case .none:         return "foundation_slab"   // дефолт, если не выбран
    }
}

struct FoundationStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "foundation_slab"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = stageSubtitle(stage)
                let prog = stageProgress(stage)
                let percent = Int((prog * 100).rounded())
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: bindingForStage(at: i),
                        project: project,
                        onStageChanged: {
                            // Сохранение и уведомление централизованы в onChange(of: stages)
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
        .navigationTitle("Фундамент")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        typeID = foundationTypeID(project.foundationType)

        // Пытаемся загрузить сохранённый прогресс с учётом актуального шаблона
        if let saved = FoundationProgressStore.load(projectID: project.id, typeID: typeID),
           !saved.isEmpty {
            stages = saved
        } else {
            // Первичная инициализация стадий по типу фундамента
            stages = FoundationStagesProvider.loadStages(named: typeID)
            // Сохранением и нотификацией займётся onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        FoundationProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    private func bindingForStage(at index: Int) -> Binding<Stage> {
        Binding(
            get: { stages[index] },
            set: { stages[index] = $0 }
        )
    }

    private func stageProgress(_ stage: Stage) -> Double {
        let total = max(stage.items.count, 1)
        let done = stage.items.filter { $0.status == .ok }.count
        return Double(done) / Double(total)
    }

    private func stageSubtitle(_ stage: Stage) -> String {
        let lower = stage.title.lowercased()

        if lower.contains("разметк") {
            return "Шаги, оси, подсыпка, подготовка"
        } else if lower.contains("коммуник") || lower.contains("утеплен") {
            return "Тип основания, подушка, армирование"
        } else if lower.contains("опалуб") || lower.contains("рёбра") || lower.contains("ребра") {
            return "Опалубка, арматура, закладные"
        } else if lower.contains("армирован") {
            return "Арматурный каркас, защитный слой"
        } else if lower.contains("бетонирован") {
            return "Марка, прогрев/укрытие, уход"
        } else if lower.contains("приём") || lower.contains("прием") {
            return "Исп. документация, дефекты, фото"
        } else if lower.contains("зимний") {
            return "Мероприятия на холодный период"
        } else {
            return "Тип основания, подушка, армирование"
        }
    }
}
