import SwiftUI

struct StageDelayReasonView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let stage: Stage

    @State private var selectedReason: DelayReason?
    @State private var comment: String

    // Инициализатор — подхватываем уже сохранённую причину/коммент
    init(projectID: UUID, stage: Stage) {
        self.projectID = projectID
        self.stage = stage
        _selectedReason = State(initialValue: stage.delayReason)
        _comment = State(initialValue: stage.delayComment ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {

                // Причина просрочки
                Section {
                    Picker("Причина", selection: $selectedReason) {
                        // Вариант «не указана» — по сути сброс
                        Text("Не указана").tag(DelayReason?.none)

                        ForEach(DelayReason.allCases, id: \.self) { reason in
                            Text(reason.title)
                                .tag(DelayReason?.some(reason))
                        }
                    }
                } header: {
                    Text("Причина просрочки")
                }

                // Комментарий
                Section {
                    TextField("Добавьте детали…", text: $comment, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Комментарий (необязательно)")
                } footer: {
                    Text("Эта информация поможет анализировать задержки по проектам.")
                }

                // Сброс причины, если она уже сохранена
                if stage.delayReason != nil || (stage.delayComment?.isEmpty == false) {
                    Section {
                        Button(role: .destructive) {
                            resetReason()
                        } label: {
                            Text("Сбросить причину просрочки")
                        }
                    } footer: {
                        Text("Если указали причину случайно или она больше не актуальна — можно полностью сбросить.")
                    }
                }
            }
            .navigationTitle("Причина просрочки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        save()
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        do {
            let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.updateStageDelay(
                projectID: projectID,
                stageID: stage.id,
                reason: selectedReason,
                comment: trimmed.isEmpty ? nil : trimmed
            )
            dismiss()
        } catch {
            debugPrint("❌ updateStageDelay error:", error.localizedDescription)
            dismiss()
        }
    }

    private func resetReason() {
        do {
            try store.updateStageDelay(
                projectID: projectID,
                stageID: stage.id,
                reason: nil,
                comment: nil
            )
            // Локально тоже очищаем, чтобы всё было в нуле
            selectedReason = nil
            comment = ""
            dismiss()
        } catch {
            debugPrint("❌ resetStageDelay error:", error.localizedDescription)
            dismiss()
        }
    }
}
