import SwiftUI

// MARK: - Тип благоустройства
private func landscapingTypeID(for project: Project) -> String {
    "default"
}

// MARK: - Подзаголовки под этапы благоустройства
private func landSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Этап 1. Разметка и подготовка": "Дороги, подъезды, планировка",
        "Этап 2. Дренаж/ливнёвка": "Трубы, колодцы, уклоны, выпуск",
        "Этап 3. Заборы/ворота": "Столбы, откатные/распашные, автоматика",
        "Этап 4. Площадки и дорожки": "Основание, покрытие, узлы",
        "Этап 5. Озеленение": "Подготовка, газон, посадки",
        "Этап 6. Коммуникации на участке": "Лотки, надземное/подземное",
        "Этап 7. Приёмка": "Отметки, паспорта, гарантия, фото"
    ]
    return map[title] ?? "Дороги, дождевка, заборы"
}

// MARK: - Экран стадий благоустройства

struct LandscapingStagesScreen: View {
    let project: Project

    @State private var stages: [Stage] = []
    @State private var typeID: String = "default"

    var body: some View {
        List {
            headerSection

            if stages.isEmpty {
                emptyState
            } else {
                stagesList
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Благоустройство")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - HEADER

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Контроль благоустройства")
                    .font(.headline)

                Text("Отслеживайте выполнение всех этапов благоустройства участка.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    ProgressView(value: overallProgress)
                        .tint(Color("AccentYellow"))

                    Text(progressLabel(overallProgress))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(
                                    overallProgress >= 0.999
                                    ? Color.green.opacity(0.9)
                                    : Color("AccentYellow").opacity(0.9)
                                )
                        )
                        .foregroundColor(.black.opacity(0.9))
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Пустое состояние

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Нет данных по благоустройству")
                .font(.headline)
            Text("Проверьте, что для данного проекта доступен шаблон этапов благоустройства.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Список этапов

    private var stagesList: some View {
        Section {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let index = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = landSubtitle(for: title)
                let prog = stageProgress(stage)
                let label = progressLabel(prog)
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: index),
                        project: project,
                        onStageChanged: {
                            // Сохранение и нотификация централизованы в onChange(of: stages)
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
    }

    // MARK: - LOAD (синхронная)

    private func initialLoad() {
        typeID = landscapingTypeID(for: project)

        // 1️⃣ Сначала пробуем MERGE-загрузку (шаблон + сохранённый прогресс)
        if let merged = LandscapingProgressStore.load(projectID: project.id, typeID: typeID),
           !merged.isEmpty {
            stages = merged
            return
        }

        // 2️⃣ Резервный путь — старая логика (оставляем без изменений)
        if let saved = LandscapingProgressStore.load(projectID: project.id),
           !saved.isEmpty {
            stages = saved
        } else {
            // 3️⃣ Если сохранений нет — грузим из провайдера
            let loaded = LandscapingStagesProvider.loadStages(for: typeID)
            stages = loaded
            // Первичное сохранение сделает onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        LandscapingProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    // MARK: - BINDING

    private func binding(at index: Int) -> Binding<Stage> {
        Binding(
            get: { stages[index] },
            set: { stages[index] = $0 }
        )
    }

    // MARK: - OVERALL PROGRESS

    private var overallProgress: Double {
        let allItems = stages.flatMap { $0.items }
        guard !allItems.isEmpty else { return 0 }

        let done = allItems.filter { $0.status == .ok }.count
        return Double(done) / Double(allItems.count)
    }

    // MARK: - PROGRESS PER STAGE

    private func stageProgress(_ stage: Stage) -> Double {
        let items = stage.items
        guard !items.isEmpty else { return 0 }

        let done = items.filter { $0.status == .ok }.count
        return Double(done) / Double(items.count)
    }

    // MARK: - LABEL

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если прогресс 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
