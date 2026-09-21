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
    @State private var typeID: String = "monolithic"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let subtitle = slabStageSubtitle(stage)
                let prog = progress(for: stage)
                let label = progressLabel(prog)
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        onStageChanged: {
                            // сохранение и уведомление централизованы в onChange(of: stages)
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.title)
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
        SlabProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
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

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
