import SwiftUI

struct TaskFormView: View {
    enum Mode {
        case create
        case edit(TaskItem)

        var title: String {
            switch self {
            case .create: return "Новая задача"
            case .edit:   return "Редактировать задачу"
            }
        }
    }

    /// One-shot defaults for a new task. Applied in `init`, never reapplied on `onAppear`.
    struct CreatePrefill: Equatable {
        var projectID: UUID? = nil
        var dueDate: Date? = nil
        var hasDueDate: Bool = false
    }

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title: String
    @State private var details: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var selectedProjectID: UUID?
    @State private var isCompleted: Bool

    @State private var showDeleteAlert: Bool = false
    @State private var errorText: String?

    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    init(mode: Mode, prefill: CreatePrefill? = nil) {
        self.mode = mode
        switch mode {
        case .create:
            let draft = prefill ?? CreatePrefill()
            _title = State(initialValue: "")
            _details = State(initialValue: "")
            _hasDueDate = State(initialValue: draft.hasDueDate)
            _dueDate = State(initialValue: draft.dueDate ?? Self.defaultDueSuggestion(on: Date()))
            _selectedProjectID = State(initialValue: draft.projectID)
            _isCompleted = State(initialValue: false)
        case .edit(let task):
            _title = State(initialValue: task.title)
            _details = State(initialValue: task.details ?? "")
            _hasDueDate = State(initialValue: task.dueDate != nil)
            _dueDate = State(initialValue: task.dueDate ?? Self.defaultDueSuggestion(on: Date()))
            _selectedProjectID = State(initialValue: task.projectID)
            _isCompleted = State(initialValue: task.isCompleted)
        }
    }

    var body: some View {
        Form {
            Section("Описание") {
                TextField("Что нужно сделать?", text: $title)
                    .demoTrainingAnchor(.taskCalendarFormDescription)

                TextField("Детали (необязательно)", text: $details, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            Section("Срок") {
                Toggle("У задачи есть крайний срок", isOn: $hasDueDate.animation())

                if hasDueDate {
                    // No minimum date: past deadlines are allowed; existing values stay as-is.
                    DatePicker(
                        "Дата и время",
                        selection: $dueDate,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)

                    HStack {
                        Button("Сегодня 18:00") {
                            setQuickTime(hour: 18, minute: 0, dayOffset: 0)
                        }
                        .buttonStyle(.bordered)

                        Button("Завтра 09:00") {
                            setQuickTime(hour: 9, minute: 0, dayOffset: 1)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Section("Проект") {
                Picker("Проект", selection: $selectedProjectID) {
                    Text("Без привязки")
                        .tag(Optional<UUID>.none)

                    ForEach(store.projects) { project in
                        Text(project.name)
                            .tag(Optional(project.id))
                    }
                }
            }

            if case .edit = mode {
                Section("Статус") {
                    Toggle("Выполнено", isOn: $isCompleted)
                }

                Section {
                    Button(role: .destructive) {
                        if store.isReadOnlyMode {
                            showReadOnlyAlert = true
                            return
                        }
                        showDeleteAlert = true
                    } label: {
                        Text("Удалить задачу")
                    }
                }
            }
        }
        .navigationTitle(mode.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    saveTask()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
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
            Text("Сейчас активен режим просмотра. Для создания и редактирования задач нужна подписка USER или PRO.")
        }
        .alert("Доступ ограничен", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .alert("Удалить задачу?", isPresented: $showDeleteAlert) {
            Button("Удалить", role: .destructive) { deleteTask() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Эту задачу нельзя будет восстановить.")
        }
    }

    // MARK: - Defaults

    /// 18:00 on the given calendar day (used for day-scoped create).
    static func defaultDueSuggestion(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: 18, minute: 0, second: 0, of: start) ?? start
    }

    private func setQuickTime(hour: Int, minute: Int, dayOffset: Int) {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")
        let base = calendar.startOfDay(for: Date())
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: base) else { return }
        if let newDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
            dueDate = newDate
        }
    }

    // MARK: - Save / delete

    private func saveTask() {
        if store.isReadOnlyMode {
            showReadOnlyAlert = true
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDetails = trimmedDetails.isEmpty ? nil : trimmedDetails
        let finalDueDate = hasDueDate ? dueDate : nil

        do {
            switch mode {
            case .create:
                try store.addTask(
                    title: trimmedTitle,
                    details: finalDetails,
                    projectID: selectedProjectID,
                    dueDate: finalDueDate
                )

            case .edit(let task):
                try store.updateTask(
                    task,
                    title: trimmedTitle,
                    details: finalDetails,
                    projectID: selectedProjectID,
                    dueDate: finalDueDate,
                    isCompleted: isCompleted
                )
            }

            dismiss()

        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteTask() {
        if store.isReadOnlyMode {
            showReadOnlyAlert = true
            return
        }

        guard case let .edit(task) = mode else { return }

        do {
            try store.deleteTask(task)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
