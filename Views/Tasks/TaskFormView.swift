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

    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var selectedProjectID: UUID?
    @State private var isCompleted: Bool = false

    @State private var showDeleteAlert: Bool = false
    @State private var errorText: String?

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    init(mode: Mode) {
        self.mode = mode
    }

    var body: some View {
        Form {

            // MARK: - Описание
            Section("Описание") {
                TextField("Что нужно сделать?", text: $title)

                TextField("Детали (необязательно)", text: $details, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)
            }

            // MARK: - Срок
            Section("Срок") {
                Toggle("У задачи есть крайний срок", isOn: $hasDueDate.animation())

                if hasDueDate {

                    DatePicker(
                        "Дата и время",
                        selection: $dueDate,
                        in: Date()...,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .datePickerStyle(.wheel)

                    HStack {
                        Button("Сегодня 18:00") {
                            setQuickTime(hour: 18, minute: 0, today: true)
                        }
                        .buttonStyle(.bordered)

                        Button("Завтра 09:00") {
                            setQuickTime(hour: 9, minute: 0, today: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // MARK: - Проект
            Section("Проект") {
                Picker("Проект", selection: Binding(
                    get: { selectedProjectID ?? UUID?.none as UUID?? ?? nil },
                    set: { selectedProjectID = $0 }
                )) {
                    Text("Без привязки")
                        .tag(UUID?.none)

                    ForEach(store.projects) { project in
                        Text(project.name)
                            .tag(Optional(project.id))
                    }
                }
            }

            // MARK: - Статус (для редактирования)
            if case .edit = mode {
                Section("Статус") {
                    Toggle("Выполнено", isOn: $isCompleted)
                }
            }

            // MARK: - Удаление задачи
            if case .edit = mode {
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

        // MARK: - Верхняя кнопка "Сохранить"
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") {
                    saveTask()
                }
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }

        // MARK: - Paywall
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }

        // MARK: - Read-only предупреждение
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

        // MARK: - Доступ ограничен (бывшая «Ошибка»)
        .alert("Доступ ограничен", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }

        // MARK: - Удаление подтверждение
        .alert("Удалить задачу?", isPresented: $showDeleteAlert) {
            Button("Удалить", role: .destructive) { deleteTask() }
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Эту задачу нельзя будет восстановить.")
        }

        // MARK: - OnAppear
        .onAppear {
            if case let .edit(task) = mode {
                title = task.title
                details = task.details ?? ""

                if let d = task.dueDate {
                    hasDueDate = true
                    dueDate = d
                } else {
                    hasDueDate = false
                }

                selectedProjectID = task.projectID
                isCompleted = task.isCompleted
            }
        }
    }

    // MARK: - Быстрые кнопки времени
    private func setQuickTime(hour: Int, minute: Int, today: Bool) {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "ru_RU")

        var components = calendar.dateComponents([.year, .month, .day], from: Date())

        if !today {
            if let dateTomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
                components = calendar.dateComponents([.year, .month, .day], from: dateTomorrow)
            }
        }

        components.hour = hour
        components.minute = minute

        if let newDate = calendar.date(from: components) {
            if newDate < Date() {
                dueDate = calendar.date(byAdding: .day, value: 1, to: newDate) ?? Date()
            } else {
                dueDate = newDate
            }
        }
    }

    // MARK: - Save task
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

    // MARK: - Удаление задачи
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
