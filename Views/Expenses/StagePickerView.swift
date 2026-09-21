import SwiftUI

/// Экран выбора глобального этапа (GlobalStageCategory) для привязки расхода.
/// Показывает все доступные глобальные категории.
struct StagePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID            // сейчас не используется, но оставляем на будущее
    @Binding var selectedCategory: GlobalStageCategory?

    var body: some View {
        List {
            ForEach(GlobalStageCategory.allCases) { cat in
                Button {
                    selectedCategory = cat
                    dismiss()
                } label: {
                    HStack {
                        Text(cat.title)
                            .font(.body)

                        Spacer()

                        if selectedCategory == cat {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.blue)
                                .imageScale(.large)
                        }
                    }
                }
            }
        }
        .navigationTitle("Этап строительства")
        .navigationBarTitleDisplayMode(.inline)
    }
}
