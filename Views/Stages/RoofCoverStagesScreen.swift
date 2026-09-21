import SwiftUI

// Преобразуем Optional RoofCoverType -> String ID для имен файлов JSON
private func roofCoverTypeID(_ t: RoofCoverType?) -> String {
    switch t {
    case .some(.metal):     return "metal"
    case .some(.prof):      return "prof"
    case .some(.seam):      return "seam"
    case .some(.shingle):   return "shingle"
    case .some(.ceramic):   return "ceramic"
    case .some(.composite): return "composite"
    case .some(.membrane):  return "membrane"
    case .none:
        return "metal" // дефолт — металлочерепица/профнастил
    }
}

private func roofCoverSubtitle(for stage: Stage) -> String {
    let t = stage.title.lowercased()

    if t.contains("основание") || t.contains("подготов") {
        return "Обрешётка, плёнки, готовность ската"
    }
    if t.contains("монтаж") || t.contains("листы") {
        return "Раскладка листов, нахлёсты, крепёж"
    }
    if t.contains("добор") || t.contains("ендов") || t.contains("конёк") {
        return "Ендовы, коньки, примыкания"
    }
    if t.contains("безопас") || t.contains("водост") {
        return "Снегозадержатели, лестницы, водосток"
    }
    if t.contains("зима") || t.contains("эксплуатац") {
        return "Снег, наледь, регламент обслуживания"
    }
    if t.contains("приём") {
        return "Осмотр, дефекты, финальная оценка"
    }

    return "Основание, покрытие, узлы, эксплуатация"
}

struct RoofCoverStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "metal"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let index = pair.offset
                let stage = pair.element

                let prog = stageProgress(stage)
                let label = progressLabel(prog)
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: bindingForStage(at: index),
                        project: project,
                        onStageChanged: {
                            // сохранение и уведомление делаем централизованно в onChange(of: stages)
                        }
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.title)
                                    .font(.headline)

                                Text(roofCoverSubtitle(for: stage))
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
        .navigationTitle("Покрытие крыши")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        typeID = roofCoverTypeID(project.roofCoverType)

        if let saved = RoofCoverProgressStore.load(projectID: project.id),
           !saved.isEmpty {
            stages = saved
        } else {
            stages = RoofCoverStagesProvider.loadStages(for: typeID)
            // сохранение выполнит onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        RoofCoverProgressStore.save(projectID: project.id, stages: newStages)
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

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если прогресс 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
