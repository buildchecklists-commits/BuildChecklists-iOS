import SwiftUI

/// Экран выбора пункта чек-листа внутри выбранного этапа.
/// Работает с GlobalStageCategory, а не со Stage.id.
struct StageItemPickerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let stageCategory: GlobalStageCategory

    @Binding var selectedItemID: UUID?

    /// Ищем Stage проекта, который соответствует выбранной глобальной категории
    private var stage: Stage? {
        guard let project = store.project(by: projectID) else { return nil }
        return project.stages.first(where: { $0.title == stageCategory.title })
    }

    private var items: [StageItem] {
        stage?.items ?? []
    }

    var body: some View {
        List {
            if items.isEmpty {
                Text("Нет пунктов для этого этапа")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in
                    Button {
                        selectedItemID = item.id
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.body)

                                if !item.code.isEmpty {
                                    Text(item.code)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()

                            if selectedItemID == item.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.blue)
                                    .imageScale(.large)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(stageCategory.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
