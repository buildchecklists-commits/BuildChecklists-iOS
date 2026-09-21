import SwiftUI

// Маппинг enum RoofShapeType -> ID для JSON файлов
// Ожидаются файлы:
//  Resources/RoofPacks/roof_flat.json
//                     roof_gable.json
//                     roof_hip.json
//                     roof_mansard.json
//                     roof_shed.json
//                     roof_multi.json
//                     roof_tent.json
//                     roof_halfhip.json
private func roofShapeID(from project: Project) -> String {
    switch project.roofShapeType {        // <— ВАЖНО: имя свойства в Project
    case .some(.flat):    return "flat"      // roof_flat.json
    case .some(.gable):   return "gable"     // roof_gable.json
    case .some(.hip):     return "hip"       // roof_hip.json
    case .some(.mansard): return "mansard"   // roof_mansard.json
    case .some(.shed):    return "shed"      // roof_shed.json
    case .some(.multi):   return "multi"     // roof_multi.json
    case .some(.tent):    return "tent"      // roof_tent.json
    case .some(.halfhip): return "halfhip"   // roof_halfhip.json
    case .none:           return "flat"      // дефолт — плоская
    }
}

private func roofSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Этап 1. Основание и уклоны": "Основание, уклон, пароизоляция",
        "Этап 2. Утепление": "Толщина, плотность, укладка",
        "Этап 3. Гидроизоляция": "Мембрана, швы, воронки",
        "Этап 4. Вентиляция и узлы": "Аэраторы, парапеты, примыкания",
        "Этап 5. Зима и уход": "Наледь, дренаж, эксплуатация",
        "Этап 6. Приёмка": "Герметичность, уклон, акты"
    ]
    return map[title] ?? "Кровельные этапы"
}

struct RoofStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "flat"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = roofSubtitle(for: title)
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
        .navigationTitle("Крыша")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        typeID = roofShapeID(from: project)

        // Загружаем сохранённые данные с учётом актуального шаблона для выбранного типа крыши
        if let saved = RoofProgressStore.load(projectID: project.id, typeID: typeID),
           !saved.isEmpty {
            stages = saved
        } else {
            // Первая инициализация — просто берём шаблон
            stages = RoofStagesProvider.loadStages(for: typeID)
            // сохранением займётся onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        RoofProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(
            get: { stages[i] },
            set: { stages[i] = $0 }
        )
    }

    private func progress(for stage: Stage) -> Double {
        let total = max(stage.items.count, 1)
        let done  = stage.items.filter { $0.status == .ok }.count
        return Double(done) / Double(total)
    }

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
