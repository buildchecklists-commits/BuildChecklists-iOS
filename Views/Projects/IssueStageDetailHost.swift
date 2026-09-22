import SwiftUI

/// Opens the working-checklist block for an issue without going through the pack hub.
/// Load/save uses the same ProgressStore files as the collector (no template merge).
struct IssueStageDetailHost: View {
    @EnvironmentObject private var store: AppStore

    let projectID: UUID
    let pack: ChecklistPack
    let stageID: UUID
    let itemID: UUID

    @State private var stages: [Stage] = []
    @State private var didLoad = false

    private var project: Project? {
        store.projects.first(where: { $0.id == projectID })
    }

    private var stageIndex: Int? {
        guard let index = stages.firstIndex(where: { $0.id == stageID }) else { return nil }
        guard stages[index].items.contains(where: { $0.id == itemID }) else { return nil }
        return index
    }

    var body: some View {
        Group {
            if let project, let index = stageIndex {
                StageDetailView2(
                    stage: binding(at: index),
                    project: project,
                    highlightItemID: itemID,
                    onStageChanged: {
                        ChecklistPackStore.save(pack: pack, projectID: projectID, stages: stages)
                    }
                )
            } else if didLoad {
                missingItemView
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: loadIfNeeded)
    }

    private var missingItemView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пункт не найден")
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Не удалось открыть этот пункт в рабочем чек-листе. Отметка «Проблема» сохранена и не удалена.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(20)
        .navigationTitle("Замечание")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("project.issues.itemMissing")
    }

    private func binding(at index: Int) -> Binding<Stage> {
        Binding(
            get: { stages[index] },
            set: { stages[index] = $0 }
        )
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        stages = ChecklistPackStore.load(pack: pack, projectID: projectID)
        didLoad = true
    }
}
