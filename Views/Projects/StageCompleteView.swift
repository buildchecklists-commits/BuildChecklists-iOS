import SwiftUI

struct StageCompleteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let stage: Stage
    let onCompleted: (_ actualStart: Date, _ actualEnd: Date) -> Void

    @State private var actualStart: Date
    @State private var actualEnd: Date

    init(
        projectID: UUID,
        stage: Stage,
        onCompleted: @escaping (_ actualStart: Date, _ actualEnd: Date) -> Void
    ) {
        self.projectID = projectID
        self.stage = stage
        self.onCompleted = onCompleted

        let now = Date()
        let s = stage.actualStart ?? stage.plannedStart ?? now
        let e = stage.actualEnd ?? stage.plannedEnd ?? now

        _actualStart = State(initialValue: s)
        _actualEnd   = State(initialValue: max(s, e))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Этап")) {
                    Text(stage.title)
                    if let sub = stage.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Фактические даты")) {
                    DatePicker("Начало", selection: $actualStart, displayedComponents: [.date])

                    DatePicker(
                        "Завершение",
                        selection: $actualEnd,
                        in: actualStart...,
                        displayedComponents: [.date]
                    )
                }

                if stage.actualStart != nil || stage.actualEnd != nil {
                    Section {
                        Button(role: .destructive) { resetFact() } label: {
                            Text("Сбросить факт завершения")
                        }
                    } footer: {
                        Text("Если отметили завершение случайно — можно сбросить.")
                    }
                }

                Section(footer: Text("Фактические даты фиксируют реальное завершение этапа.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Завершение этапа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { save() }
                }
            }
        }
    }

    private func save() {
        do {
            try store.updateStageActualDates(
                projectID: projectID,
                stageID: stage.id,
                actualStart: actualStart,
                actualEnd: actualEnd
            )

            dismiss()
            onCompleted(actualStart, actualEnd)

        } catch {
            debugPrint("❌ updateStageActualDates:", error.localizedDescription)
            dismiss()
        }
    }

    private func resetFact() {
        do {
            try store.updateStageActualDates(
                projectID: projectID,
                stageID: stage.id,
                actualStart: nil,
                actualEnd: nil
            )
            dismiss()
        } catch {
            debugPrint("❌ resetStageActualDates:", error.localizedDescription)
            dismiss()
        }
    }
}
