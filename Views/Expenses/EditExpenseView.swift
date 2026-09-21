import SwiftUI

struct EditExpenseView: View {
    @EnvironmentObject var store: AppStore
    let expense: ExpenseItem

    @Environment(\.dismiss) private var dismiss

    @State private var category: ExpenseCategory
    @State private var subCategory: ExpenseSubCategory
    @State private var amountText: String
    @State private var date: Date
    @State private var note: String

    @State private var stageCategory: GlobalStageCategory?
    @State private var stageItemID: UUID?

    @State private var showStagePicker = false
    @State private var showStageItemPicker = false

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    init(expense: ExpenseItem) {
        self.expense = expense

        _category = State(initialValue: expense.category)
        _subCategory = State(initialValue: expense.subCategory)
        _amountText = State(initialValue: EditExpenseView.format(expense.amount))
        _date = State(initialValue: expense.date)
        _note = State(initialValue: expense.note ?? "")

        _stageCategory = State(initialValue: expense.stageCategory)
        _stageItemID = State(initialValue: expense.stageItemID)
    }

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: " ", with: ""))
    }

    private var isReadOnlyBlocked: Bool {
        store.isReadOnlyMode && !store.isDemoMode
    }

    var body: some View {
        Form {

            Section("Этап строительства") {
                Picker("Этап", selection: $category) {
                    ForEach(ExpenseCategory.allCases) { cat in
                        Text(cat.title).tag(cat)
                    }
                }
            }

            Section("Тип расхода") {
                Picker("Тип", selection: $subCategory) {
                    ForEach(ExpenseSubCategory.allCases) { sub in
                        Text(sub.title).tag(sub)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Привязка к этапу") {
                Button {
                    if isReadOnlyBlocked {
                        showReadOnlyAlert = true
                        return
                    }
                    showStagePicker = true
                } label: {
                    HStack {
                        Text("Этап")
                        Spacer()
                        Text(stageCategory?.title ?? "Не выбрано")
                            .foregroundStyle(stageCategory == nil ? .secondary : .primary)
                    }
                }

                Button {
                    if isReadOnlyBlocked {
                        showReadOnlyAlert = true
                        return
                    }
                    if stageCategory != nil { showStageItemPicker = true }
                } label: {
                    HStack {
                        Text("Пункт этапа")
                        Spacer()
                        Text(stageItemName)
                            .foregroundStyle(stageItemID == nil ? .secondary : .primary)
                    }
                }
                .disabled(stageCategory == nil)
            }

            Section("Сумма") {
                TextField("150 000", text: $amountText)
                    .keyboardType(.numberPad)
                    .onChange(of: amountText) { _, new in
                        formatAmountInput(new)
                    }
            }

            Section("Дата") {
                DatePicker("Дата расхода", selection: $date, displayedComponents: .date)
            }

            Section("Комментарий") {
                TextField("Что покупали / оплачивали", text: $note, axis: .vertical)
                    .lineLimit(1...4)
            }

            Section {
                Button(role: .destructive) {
                    if isReadOnlyBlocked {
                        showReadOnlyAlert = true
                        return
                    }
                    delete()
                } label: {
                    Text("Удалить расход")
                }
            }
        }
        .navigationTitle("Редактирование расхода")
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Сохранить") {
                    if isReadOnlyBlocked {
                        showReadOnlyAlert = true
                        return
                    }
                    save()
                }
                .disabled(amount == nil)
            }
        }
        .sheet(isPresented: $showStagePicker) {
            StagePickerView(
                projectID: expense.projectID,
                selectedCategory: $stageCategory
            )
        }
        .sheet(isPresented: $showStageItemPicker) {
            if let stageCategory {
                StageItemPickerView(
                    projectID: expense.projectID,
                    stageCategory: stageCategory,
                    selectedItemID: $stageItemID
                )
            }
        }

        // Read-only alert (стандартный)
        .alert("Ошибка", isPresented: $showReadOnlyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Доступен только просмотр. Чтобы редактировать или удалять расходы, оформите или продлите подписку.")
        }

        // Paywall (оставлено без изменений, но больше не открывается отсюда)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    private var stageItemName: String {
        guard let stageCategory,
              let stageItemID,
              let project = store.project(by: expense.projectID),
              let stage = project.stages.first(where: { $0.title == stageCategory.title }),
              let item = stage.items.first(where: { $0.id == stageItemID })
        else { return "Не выбрано" }

        return item.title
    }

    private func formatAmountInput(_ v: String) {
        let digits = v.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard !digits.isEmpty else { amountText = ""; return }

        let reversed = String(digits.reversed())
        var groups: [String] = []; var current = ""

        for (i, c) in reversed.enumerated() {
            current.append(c)
            if i % 3 == 2 { groups.append(current); current = "" }
        }
        if !current.isEmpty { groups.append(current) }

        amountText = groups.map { String($0.reversed()) }.reversed().joined(separator: " ")
    }

    private static func format(_ d: Decimal) -> String {
        let number = d as NSDecimalNumber
        let f = NumberFormatter()
        f.groupingSeparator = " "
        f.usesGroupingSeparator = true
        f.maximumFractionDigits = 0
        return f.string(from: number) ?? number.stringValue
    }

    private func save() {
        guard let amount else { return }

        let input = NewExpenseInput(
            projectID: expense.projectID,
            category: category,
            subCategory: subCategory,
            stageCategory: stageCategory,
            stageItemID: stageItemID,
            amount: amount,
            date: date,
            note: note.isEmpty ? nil : note
        )

        do {
            try store.updateExpense(expense, with: input)
            dismiss()
        } catch {
            debugPrint("❌ updateExpense error:", error.localizedDescription)
        }
    }

    private func delete() {
        do {
            try store.deleteExpense(expense)
            dismiss()
        } catch {
            debugPrint("❌ deleteExpense error:", error.localizedDescription)
        }
    }
}
