import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore

    @State private var name = ""
    @State private var address = ""
    @State private var dateStart = Date()
    @State private var dateEnd = Calendar.current.date(byAdding: .day, value: 14, to: Date())!
    @State private var hasDates = true
    @State private var budget = ""
    @State private var manager = ""
    @State private var description = ""
    @State private var errorText: String?

    @State private var createdProject: Project?
    @State private var pushFoundation = false

    // Лимит
    @State private var showLimitAlert = false

    // Read-only
    @State private var showReadOnlyAlert = false

    private static let budgetFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {

                if store.userRole == .user {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Для текущего тарифа доступно ограниченное количество проектов.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Text("Изменить тариф и управлять доступом можно во вкладке «Профиль».")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                store.setSelectedTab(.profile)
                                dismiss()
                            } label: {
                                Text("Перейти в профиль")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color("AccentYellow"))
                            .buttonBorderShape(.capsule)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Проект") {
                    TextField("Название*", text: $name)
                    TextField("Адрес*", text: $address)

                    Toggle("Использовать даты", isOn: $hasDates)

                    if hasDates {
                        DatePicker("Начало", selection: $dateStart, displayedComponents: .date)
                        DatePicker("Окончание", selection: $dateEnd, displayedComponents: .date)
                    }

                    TextField(
                        "Бюджет (опц.)",
                        text: Binding(
                            get: { budget },
                            set: { newValue in
                                let clean = newValue
                                    .replacingOccurrences(of: " ", with: "")
                                    .replacingOccurrences(of: ",", with: ".")

                                if let value = Decimal(string: clean) {
                                    let formatted = Self.budgetFormatter.string(from: value as NSDecimalNumber) ?? clean
                                    budget = formatted
                                } else {
                                    budget = newValue
                                }
                            }
                        )
                    )
                    .keyboardType(.numberPad)

                    Text("Общий бюджет проекта. В разделе «Бюджет» вы сможете распределить сумму по этапам строительства и отслеживать расходы.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Ответственный (опц.)", text: $manager)

                    Text("Контактное лицо или ответственный за ведение проекта.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    TextField("Описание (опц.)", text: $description, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)

                    Text("Краткое описание проекта: тип объекта, площадь или особенности.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                }

                Section {
                    Button("Создать проект") {

                        if store.isReadOnlyMode && !store.isDemoMode {
                            errorText = nil
                            showReadOnlyAlert = true
                            return
                        }

                        do {
                            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                                errorText = "Введите название"
                                return
                            }
                            guard !address.trimmingCharacters(in: .whitespaces).isEmpty else {
                                errorText = "Введите адрес"
                                return
                            }

                            let budgetClean = budget
                                .replacingOccurrences(of: " ", with: "")
                                .replacingOccurrences(of: ",", with: ".")
                            let budgetDecimal = Decimal(string: budgetClean)

                            let input = NewProjectInput(
                                name: name,
                                address: address,
                                dateStart: hasDates ? dateStart : nil,
                                dateEnd: hasDates ? dateEnd : nil,
                                budget: budgetDecimal,
                                manager: manager.isEmpty ? nil : manager,
                                description: description.isEmpty ? nil : description
                            )

                            try store.createProject(input)

                            if let justCreated = store.projects.first {
                                createdProject = justCreated
                                pushFoundation = true
                            }
                        } catch {
                            if let appError = error as? AppStoreError,
                               appError == .projectLimitReached {
                                errorText = nil
                                showLimitAlert = true
                            } else {
                                errorText = error.localizedDescription
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentYellow"))
                }

                NavigationLink(isActive: $pushFoundation) {
                    if let p = createdProject {
                        FoundationPickerView(project: p, onFinished: {
                            dismiss()
                        })
                    }
                } label: {
                    EmptyView()
                }
                .hidden()
            }
            .navigationTitle("Новый проект")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .onAppear {
                if store.isReadOnlyMode && !store.isDemoMode {
                    showReadOnlyAlert = true
                }
            }
            .alert("Ограничение по проектам", isPresented: $showLimitAlert) {
                Button("Перейти в профиль") {
                    store.setSelectedTab(.profile)
                    dismiss()
                }
                Button("Закрыть", role: .cancel) {}
            } message: {
                Text("Для текущего тарифа достигнуто доступное количество проектов. Управление тарифом доступно во вкладке «Профиль».")
            }
            .alert("Ошибка", isPresented: $showReadOnlyAlert) {
                Button("OK") { dismiss() }
            } message: {
                Text("Доступен только просмотр. Чтобы создавать проекты, требуется активная подписка.")
            }
        }
    }
}
