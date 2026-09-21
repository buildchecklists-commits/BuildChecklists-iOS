import SwiftUI

// Если появятся варианты инженерии — можно вычислять ID из project.meta
private func engineeringTypeID(for project: Project) -> String { "default" }

// Подзаголовки по этапам инженерии
private func engineeringSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Электрика": "Проект, трассы, щит, согласование",
        "Отопление": "Котёл/насос, радиаторы/тёплый пол, гидравлика",
        "Водоснабжение": "Скважина/ввод, разводка, фильтрация",
        "Канализация": "Септик/ЛОС, уклоны, вентиляция",
        "Вентиляция": "Приток/вытяжка, балансировка",
        "Слаботочка": "Интернет, камеры, датчики",
        "Пусконаладка и приёмка": "Паспорта, испытания, фото"
    ]
    return map[title] ?? "Электрика, отопление, вода, канализация"
}

struct EngineeringStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "default"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = engineeringSubtitle(for: title)
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
        .navigationTitle("Инженерия")
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    private func initialLoad() {
        typeID = engineeringTypeID(for: project)

        // ⚠️ Здесь ключевое изменение: используем MERGE-версию load(...)
        if let saved = EngineeringProgressStore.load(projectID: project.id, typeID: typeID),
           !saved.isEmpty {
            stages = saved
        } else {
            stages = EngineeringStagesProvider.loadStages(for: typeID)
            // сохранение выполнит onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        EngineeringProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(get: { stages[i] }, set: { stages[i] = $0 })
    }

    private func progress(for stage: Stage) -> Double {
        let items = stage.items
        guard !items.isEmpty else { return 0 }
        let done = items.filter { $0.status == .ok }.count
        return Double(done) / Double(items.count)
    }

    private func progressLabel(_ value: Double) -> String {
        // Всегда показываем процент, даже если 0
        let clamped = max(0, value)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
