import SwiftUI

struct AddExpenseView: View {
    @EnvironmentObject var store: AppStore
    let projectID: UUID

    @Environment(\.dismiss) private var dismiss

    // MARK: - State

    @State private var category: ExpenseCategory = .foundation
    @State private var subCategory: ExpenseSubCategory = .materials
    @State private var amountText: String = ""
    @State private var date: Date = Date()
    @State private var note: String = ""

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    // MARK: - Computed

    private var amount: Decimal? {
        Decimal(string: amountText.replacingOccurrences(of: " ", with: ""))
    }

    private var isSaveDisabled: Bool {
        amount == nil
    }

    private var isReadOnlyBlocked: Bool {
        store.isReadOnlyMode && !store.isDemoMode
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {

                    // ЭТАП СТРОИТЕЛЬСТВА
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Этап строительства")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                            .overlay(
                                HStack {
                                    Text("Этап")
                                        .font(.subheadline)

                                    Spacer()

                                    Menu {
                                        ForEach(ExpenseCategory.allCases) { cat in
                                            Button(cat.title) {
                                                category = cat
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text(category.title)
                                                .font(.subheadline)
                                            Image(systemName: "chevron.up.chevron.down")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            )
                            .frame(height: 52)
                    }

                    // ТИП РАСХОДА
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Тип расхода")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                            .overlay(
                                Picker("Тип расхода", selection: $subCategory) {
                                    ForEach(ExpenseSubCategory.allCases) { sub in
                                        Text(sub.title).tag(sub)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .padding(12)
                            )
                            .frame(height: 56)
                    }

                    // СУММА
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Сумма")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                            .overlay(
                                HStack {
                                    TextField("Например, 150 000", text: $amountText)
                                        .keyboardType(.numberPad)
                                        .onChange(of: amountText) { _, newValue in
                                            formatAmountInput(newValue)
                                        }
                                        .font(.title3.weight(.semibold))
                                        .multilineTextAlignment(.leading)

                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            )
                            .frame(height: 64)
                    }

                    // ДАТА
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Дата")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                            .overlay(
                                HStack {
                                    Text("Дата расхода")
                                        .font(.subheadline)

                                    Spacer()

                                    DatePicker(
                                        "",
                                        selection: $date,
                                        displayedComponents: .date
                                    )
                                    .labelsHidden()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            )
                            .frame(height: 52)

                        // Быстрые кнопки для выбора даты
                        HStack(spacing: 8) {
                            quickDateButton(title: "Сегодня") {
                                date = Date()
                            }
                            quickDateButton(title: "Вчера") {
                                if let d = Calendar.current.date(byAdding: .day, value: -1, to: Date()) {
                                    date = d
                                }
                            }
                            quickDateButton(title: "Неделя назад") {
                                if let d = Calendar.current.date(byAdding: .day, value: -7, to: Date()) {
                                    date = d
                                }
                            }
                        }
                    }

                    // КОММЕНТАРИЙ
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Комментарий")
                            .font(.headline)

                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemBackground))
                            .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
                            .overlay(
                                TextField(
                                    "Что покупали / оплачивали",
                                    text: $note,
                                    axis: .vertical
                                )
                                .lineLimit(2...5)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                            )
                            .frame(minHeight: 80)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Новый расход")
        .navigationBarTitleDisplayMode(.inline)
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
                .disabled(isSaveDisabled)
            }
        }

        // Read-only alert
        .alert("Ошибка", isPresented: $showReadOnlyAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Доступен только просмотр. Чтобы добавлять, редактировать или удалять расходы, оформите или продлите подписку.")
        }

        // Paywall (оставлено без изменений, но больше не открывается отсюда)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(store)
        }
    }

    // MARK: - Helpers UI

    private func quickDateButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers Logic

    /// Форматирование суммы с пробелами: 150 000
    private func formatAmountInput(_ value: String) {
        let digits = value.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        guard !digits.isEmpty else { amountText = ""; return }

        let reversed = String(digits.reversed())
        var groups: [String] = []
        var current = ""

        for (i, c) in reversed.enumerated() {
            current.append(c)
            if i % 3 == 2 {
                groups.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            groups.append(current)
        }

        amountText = groups
            .map { String($0.reversed()) }
            .reversed()
            .joined(separator: " ")
    }

    private func save() {
        guard let amount else { return }

        let input = NewExpenseInput(
            projectID: projectID,
            category: category,
            subCategory: subCategory,
            stageCategory: nil,
            stageItemID: nil,
            amount: amount,
            date: date,
            note: note.isEmpty ? nil : note
        )

        do {
            try store.addExpense(input)
            dismiss()
        } catch {
            debugPrint("❌ addExpense error:", error.localizedDescription)
        }
    }
}
