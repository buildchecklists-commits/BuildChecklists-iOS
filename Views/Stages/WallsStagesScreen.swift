import SwiftUI

// ID пакета по типу стен (fallback: aac)
private func wallsTypeID(from project: Project) -> String {
    switch project.wallType {
    case .aac?:        return "aac"         // Газобетон
    case .keramBlock?: return "keramblock"  // Керамоблок (имя файла в паках — в нижнем регистре)
    case .brick?:      return "brick"       // Кирпич
    case .woodcrete?:  return "woodcrete"   // Арболит (в провайдере замапится на arbolit)
    case .monolithic?: return "monolithic"  // Монолит
    case .keramzit?:   return "keramzit"    // Керамзитобетон
    case .combo?:      return "combo"       // Комбинированные
    default:           return "aac"
    }
}

private func wallSubtitle(for title: String) -> String {
    let map: [String: String] = [
        "Подготовка": "Проект, оси, раствор, подача материала",
        "Кладка стен": "Ряды, перевязка, вертикаль, допуски",
        "Армирование/пояса": "Сетки, штрабы, хомуты, армопояс",
        "Проёмы и перемычки": "Размеры, опоры, анкера, ГОСТ",
        "Гидро- и теплоизоляция": "Швы, утепление, мостики холода",
        "Приёмка": "Диагонали, отметки, документы, фото"
    ]
    return map[title] ?? "Материалы, перевязка, армирование"
}

struct WallsStagesScreen: View {
    let project: Project
    @State private var stages: [Stage] = []
    @State private var typeID: String = "aac"

    var body: some View {
        List {
            ForEach(Array(stages.enumerated()), id: \.offset) { pair in
                let i = pair.offset
                let stage = pair.element

                let title = stage.title
                let subtitle = wallSubtitle(for: title)
                let prog = progress(for: stage)
                let percent = Int((prog * 100).rounded())
                let isCompleted = prog >= 0.999

                NavigationLink {
                    StageDetailView2(
                        stage: binding(at: i),
                        project: project,
                        onStageChanged: {
                            // сохранение и нотификация централизованы в onChange(of: stages)
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
        .navigationTitle("Стены")
        .onAppear { initialLoad() }
        .onChange(of: stages) { _, newValue in
            saveProgressAndNotify(newValue)
        }
    }

    // MARK: - Helpers

    /// Первичная загрузка этапов по типу стен.
    /// 1) Сначала пробуем взять сохранённый прогресс c MERGE шаблона.
    /// 2) Если не получилось — работаем по старой схеме (совместимость + fallback).
    private func initialLoad() {
        typeID = wallsTypeID(from: project)

        // 1. Новый путь: MERGE-загрузка через WallsProgressStore.load(projectID:typeID:)
        if let merged = WallsProgressStore.load(projectID: project.id, typeID: typeID),
           !merged.isEmpty {
            stages = merged
            return
        }

        // 2. Старый путь (оставляем как резервный вариант, ничего не выкидываем).
        if let saved = WallsProgressStore.load(projectID: project.id), !saved.isEmpty {
            let fresh = WallsStagesProvider.loadStages(for: typeID)

            // Совместимость: одинаковое количество этапов и совпадающие заголовки.
            let isCompatible =
                saved.count == fresh.count &&
                zip(saved, fresh).allSatisfy { $0.title == $1.title }

            if isCompatible {
                stages = saved
                return
            } else {
                print("⚠️ WallsStagesScreen: saved stages outdated, reloading from pack for typeID = \(typeID)")
                stages = fresh
                // сохранением займётся onChange(of: stages)
                return
            }
        }

        // 3. Если сохранений нет — просто грузим pack.
        var loaded = WallsStagesProvider.loadStages(for: typeID)

        // Защита от пустого экрана: если по какой-то причине пак не найден,
        // пробуем универсальный фолбэк (aac).
        if loaded.isEmpty, typeID != "aac" {
            print("⚠️ WallsStagesScreen: pack for \(typeID) is empty, fallback to aac")
            loaded = WallsStagesProvider.loadStages(for: "aac")
        }

        stages = loaded
        // сохранением займётся onChange(of: stages)
    }

    private func saveProgressAndNotify(_ newStages: [Stage]) {
        WallsProgressStore.save(projectID: project.id, stages: newStages)
        NotificationCenter.default.post(name: .bcProgressDidChange, object: nil)
    }

    private func binding(at i: Int) -> Binding<Stage> {
        Binding(get: { stages[i] }, set: { stages[i] = $0 })
    }

    private func progress(for s: Stage) -> Double {
        let total = max(s.items.count, 1)
        let done = s.items.filter { $0.status == .ok }.count
        return Double(done) / Double(total)
    }
}

#if DEBUG
// MARK: - Preview

struct WallsStagesScreen_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            WallsStagesScreen(project: .previewMonolithic)
        }
    }
}

private extension Project {
    /// Проект для превью экрана "Стены — монолит".
    static var previewMonolithic: Project {
        Project(
            id: UUID(),
            name: "Дом (монолит, превью)",
            address: "Предпросмотр",
            dateStart: nil,
            dateEnd: nil,
            budget: nil,
            manager: nil,
            coverImagePath: nil,
            description: nil,
            foundationType: .slab,
            wallType: .monolithic,
            slabType: .mono,
            roofShapeType: .gable,
            roofCoverType: .metal,
            stages: []
        )
    }
}
#endif
