import SwiftUI

struct StageScheduleEditView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let projectID: UUID
    let stage: Stage

    @State private var startDate: Date
    @State private var endDate: Date

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    init(projectID: UUID, stage: Stage) {
        self.projectID = projectID
        self.stage = stage

        _startDate = State(initialValue: stage.plannedStart ?? Date())
        _endDate   = State(initialValue: stage.plannedEnd ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Этап")) {
                    Text(stage.title)
                    if let subtitle = stage.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section(header: Text("Плановые даты")) {
                    DatePicker("Начало", selection: $startDate, displayedComponents: [.date])

                    DatePicker(
                        "Окончание",
                        selection: $endDate,
                        in: startDate...,
                        displayedComponents: [.date]
                    )
                }

                Section(footer: Text("Плановые даты влияют на срок проекта и отображаются в таймлайне.")) {
                    EmptyView()
                }
            }
            .navigationTitle("Сроки этапа")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        if store.isReadOnlyMode {
                            showReadOnlyAlert = true
                            return
                        }
                        save()
                    }
                }
            }

            // Paywall
            .sheet(isPresented: $showPaywall) {
                PaywallView()
                    .environmentObject(store)
            }

            // Read-only alert
            .alert("Режим только просмотр", isPresented: $showReadOnlyAlert) {
                Button("Отмена", role: .cancel) { }
                Button("Разблокировать") {
                    Task {
                        _ = await store.refreshRoleForCurrentUser()
                        if store.isReadOnlyMode {
                            showPaywall = true
                        }
                    }
                }
            } message: {
                Text("Сейчас активен режим просмотра. Для изменения сроков нужна подписка USER или PRO.")
            }
        }
    }

    private func save() {
        do {
            try store.updateStagePlannedDates(
                projectID: projectID,
                stageID: stage.id,
                plannedStart: startDate,
                plannedEnd: endDate
            )
            dismiss()
        } catch {
            debugPrint("❌ updateStagePlannedDates:", error.localizedDescription)
            dismiss()
        }
    }
}
