import SwiftUI

// MARK: - Вспомогательные функции

/// Пока один тип отделки — "default".
private func finishingTypeID(for project: Project) -> String { "default" }

/// Подзаголовки под конкретные этапы отделки
private func finishingSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Этап 1. Подготовка коробки под отделку": "Готовим коробку и базовую геометрию",
        "Этап 2. Черновая инженерия (стены и потолок)": "Разводка инженерии по стенам и потолку",
        "Этап 3. Инженерия в полу / тёплый пол": "Коммуникации и тёплые полы в основании",
        "Этап 4. Гидроизоляция и подготовка под стяжку": "Гидроизоляция и подготовка основания",
        "Этап 5. Стяжка пола": "Основная стяжка по маякам",
        "Этап 6. Штукатурка стен (черновая)": "Ровные стены под чистовую",
        "Этап 7. Черновые потолки (ГКЛ, закладные, ниши)": "Каркасы, ниши и закладные",
        "Этап 8. Малярика — старт": "Стартовая шпаклёвка и грунты",
        "Этап 9. Плиточные работы": "Санузлы, фартуки, мокрые зоны",
        "Этап 10. Малярика — финиш": "Финишная шпаклёвка и покраска",
        "Этап 11. Чистовые потолки": "Натяжные и гипсовые потолки",
        "Этап 12. Полы (чистовые)": "Ламинат, паркет, плитка",
        "Этап 13. Двери, плинтуса, доборы": "Монтаж дверей и обвязки",
        "Этап 14. Освещение / электрика / финальная приёмка": "Свет, розетки и общий финчек"
    ]
    return map[title] ?? "Отделка — контроль этапа"
}

// MARK: - Экран отделки

struct FinishingStagesScreen: View {
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
        .navigationTitle("Отделка")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: initialLoad)
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Контроль отделочных этапов")
                    .font(.headline)
                Text("Отслеживайте готовность отделки, проверяйте все чек-листы и не пропускайте важные этапы.")
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
            Text("Нет данных по отделке")
                .font(.headline)
            Text("Проверьте, что для данного проекта доступен шаблон этапов отделки.")
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
                let subtitle = finishingSubtitle(for: title)
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

    // MARK: - Загрузка данных

    private func initialLoad() {
        typeID = finishingTypeID(for: project)

        // 1️⃣ Сначала пробуем MERGE-загрузку — актуальный шаблон + сохранённый прогресс
        if let merged = FinishingProgressStore.load(projectID: project.id, typeID: typeID),
           !merged.isEmpty {
            stages = merged
            return
        }

        // 2️⃣ Резервный путь — старая логика (оставляю как есть, ничего не выкидываю)
        if let saved = FinishingProgressStore.load(projectID: project.id),
           !saved.isEmpty {
            stages = saved
        } else {
            let provider = FinishingStagesProvider()
            stages = provider.loadStages(for: typeID)
            // Первичное сохранение сделает onChange(of: stages)
        }
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        FinishingProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    // MARK: - Bindings

    private func binding(at index: Int) -> Binding<Stage> {
        Binding(
            get: { stages[index] },
            set: { stages[index] = $0 }
        )
    }

    // MARK: - Общий прогресс

    private var overallProgress: Double {
        guard !stages.isEmpty else { return 0 }
        let allItems = stages.flatMap { $0.items }
        guard !allItems.isEmpty else { return 0 }

        let done = allItems.filter { $0.status == .ok }.count
        return Double(done) / Double(allItems.count)
    }

    // MARK: - Progress по одному этапу

    private func stageProgress(_ stage: Stage) -> Double {
        let items = stage.items
        guard !items.isEmpty else { return 0 }
        let done = items.filter { $0.status == .ok }.count
        return Double(done) / Double(items.count)
    }

    private func progressLabel(_ v: Double) -> String {
        // Всегда показываем процент, даже если прогресс 0
        let clamped = max(0, v)
        return "\(Int((clamped * 100).rounded()))%"
    }
}
