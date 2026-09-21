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
    @State private var typeID: String = "default"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = windowsSubtitle(for: title)
                let prog = stageProgress(stage)
                let label = progressLabel(prog)
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        onStageChanged: {}
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
        WindowsProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
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

    private func progressLabel(_ v: Double) -> String {
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
