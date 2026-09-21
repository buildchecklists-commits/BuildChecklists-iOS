import SwiftUI

struct ProjectExpensesView: View {

    @EnvironmentObject var store: AppStore
    let projectID: UUID

    // ✅ FIX: явный init, чтобы не зависеть от access level memberwise init
    init(projectID: UUID) {
        self.projectID = projectID
    }

    @State private var showAddSheet = false
    @State private var showChart = false
    @State private var showFilters = false
    @State private var showExport = false
    @State private var filters = ExpenseFilters()
    @State private var editingExpense: ExpenseItem?

    // Read-only
    @State private var showReadOnlyAlert = false

    private var isReadOnlyBlocked: Bool {
        store.isReadOnlyMode && !store.isDemoMode
    }

    private var project: Project? {
        store.project(by: projectID)
    }

    // MARK: - Источники данных

    /// Все расходы по проекту (сырой список)
    private var projectExpenses: [ExpenseItem] {
        store.expenses(for: projectID)
    }

    /// Итого по проекту (без учёта фильтров — это общая сумма)
    private var total: Decimal {
        store.totalAmount(for: projectID)
    }

    /// Суммы по этапам (категориям) — тоже по всем расходам
    private var totalsByCategory: [(category: ExpenseCategory, amount: Decimal)] {
        let dict = store.totalsByCategory(for: projectID)
            .filter { $0.value > 0 }

        let array: [(category: ExpenseCategory, amount: Decimal)] = dict.map {
            (category: $0.key, amount: $0.value)
        }

        return array.sorted { lhs, rhs in
            lhs.category.title < rhs.category.title
        }
    }

    /// История расходов (по дате, новые сверху)
    private var sortedHistory: [ExpenseItem] {
        projectExpenses.sorted { $0.date > $1.date }
    }

    /// История с учётом фильтров
    private var filteredHistory: [ExpenseItem] {
        var result = sortedHistory

        // Фильтр по этапу
        if let category = filters.category {
            result = result.filter { $0.category == category }
        }

        // Фильтр по типу расхода
        if let sub = filters.subCategory {
            result = result.filter { $0.subCategory == sub }
        }

        // Фильтр по дате "от"
        if let from = filters.dateFrom {
            result = result.filter { $0.date >= from }
        }

        // Фильтр по дате "до"
        if let to = filters.dateTo {
            result = result.filter { $0.date <= to }
        }

        // Поиск по тексту (комментарий + имена категорий)
        if !filters.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = filters.query.lowercased()

            result = result.filter { exp in
                let note = (exp.note ?? "").lowercased()
                let cat = exp.category.title.lowercased()
                let sub = exp.subCategory.title.lowercased()
                return note.contains(q) || cat.contains(q) || sub.contains(q)
            }
        }

        return result
    }

    /// Итого по текущим фильтрам (если фильтры включены)
    private var filteredTotal: Decimal {
        filteredHistory.reduce(Decimal.zero) { $0 + $1.amount }
    }

    /// Суммы по этапам с учётом фильтров
    private var filteredTotalsByCategory: [(category: ExpenseCategory, amount: Decimal)] = {
        [] // будет пересчитано ниже через computed var
    }()

    private var computedFilteredTotalsByCategory: [(category: ExpenseCategory, amount: Decimal)] {
        let dict = Dictionary(grouping: filteredHistory, by: { $0.category })
            .mapValues { expenses in
                expenses.reduce(Decimal.zero) { $0 + $1.amount }
            }
            .filter { $0.value > 0 }

        let array: [(category: ExpenseCategory, amount: Decimal)] = dict.map {
            (category: $0.key, amount: $0.value)
        }

        return array.sorted { lhs, rhs in
            lhs.category.title < rhs.category.title
        }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if let project {
                List {
                    if !projectExpenses.isEmpty {
                        summarySection(project)
                        byCategorySection
                        historySection
                    } else {
                        emptyState
                    }
                }
                .listStyle(.insetGrouped)
                .navigationTitle("Расходы")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        Button {
                            showFilters = true
                        } label: {
                            Image(systemName: filters.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                        }

                        Button {
                            showExport = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }

                        Button {
                            showChart = true
                        } label: {
                            Image(systemName: "chart.bar.doc.horizontal")
                        }

                        Button {
                            // Read-only: вместо открытия формы — ошибка
                            if isReadOnlyBlocked {
                                showReadOnlyAlert = true
                            } else {
                                showAddSheet = true
                            }
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showAddSheet) {
                    NavigationStack {
                        AddExpenseView(projectID: project.id)
                            .environmentObject(store)
                    }
                }
                .sheet(isPresented: $showChart) {
                    NavigationStack {
                        ProjectExpensesChartView(projectID: projectID)
                            .environmentObject(store)
                    }
                }
                .sheet(isPresented: $showFilters) {
                    NavigationStack {
                        ExpenseFilterView(filters: $filters)
                    }
                }
                .sheet(isPresented: $showExport) {
                    NavigationStack {
                        ExpensesExportView(projectID: projectID)
                            .environmentObject(store)
                    }
                }
                .sheet(item: $editingExpense) { expense in
                    NavigationStack {
                        EditExpenseView(expense: expense)
                            .environmentObject(store)
                    }
                }
                .alert(AppAlerts.readOnly.title, isPresented: $showReadOnlyAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(AppAlerts.readOnly.message)
                }
            } else {
                Text("Проект не найден")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sections

    /// ИТОГО по проекту
    private func summarySection(_ project: Project) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Итого по проекту")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(formatAmount(total))
                            .font(.title2.bold())

                        // Дополнительно показываем сумму по текущим фильтрам
                        if !filters.isEmpty {
                            Text("По текущим фильтрам: \(formatAmount(filteredTotal))")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                    }

                    Spacer()

                    if !filters.isEmpty {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Фильтры включены")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Text("Показано \(filteredHistory.count) из \(sortedHistory.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !project.address.isEmpty {
                    Text(project.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Краткое резюме активных фильтров
                if !filters.isEmpty, !filters.summaryText.isEmpty {
                    Text("Фильтры: \(filters.summaryText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// По этапам (фундамент, стены и т.д.)
    private var byCategorySection: some View {
        let data = filters.isEmpty ? totalsByCategory : computedFilteredTotalsByCategory
        let header = filters.isEmpty ? "По этапам (все расходы)" : "По этапам (по текущим фильтрам)"

        return Section(header) {
            if data.isEmpty {
                Text("Пока нет расходов по этапам")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(data, id: \.category.id) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(group.category.title)
                                .font(.headline)

                            Spacer()

                            Text(formatAmount(group.amount))
                                .font(.headline)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    /// История расходов (с учётом фильтров)
    private var historySection: some View {
        Section {
            if sortedHistory.isEmpty {
                Text("Пока нет расходов по этому проекту")
                    .foregroundStyle(.secondary)
            } else if filteredHistory.isEmpty && !filters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("По текущим фильтрам ничего не найдено.")
                        .font(.subheadline)
                    Button("Сбросить фильтры") {
                        filters.reset()
                    }
                    .font(.subheadline)
                }
                .foregroundStyle(.secondary)
            } else {
                ForEach(filteredHistory) { expense in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(expense.category.shortTitle)
                                .font(.headline)

                            Text("·")
                                .foregroundStyle(.secondary)

                            Text(expense.subCategory.title)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text(formatAmount(expense.amount))
                                .font(.headline)
                        }

                        if let note = expense.note, !note.isEmpty {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(formatDate(expense.date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing) {
                        if isReadOnlyBlocked {
                            Button {
                                showReadOnlyAlert = true
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                showReadOnlyAlert = true
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                do {
                                    try store.deleteExpense(expense)
                                } catch {
                                    debugPrint("❌ deleteExpense error:", error.localizedDescription)
                                }
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }

                            Button {
                                editingExpense = expense
                            } label: {
                                Label("Изменить", systemImage: "pencil")
                            }
                        }
                    }
                }
            }
        } header: {
            Text("История расходов")
        }
    }

    /// Стейт когда ещё нет расходов
    private var emptyState: some View {
        Section {
            VStack(spacing: 12) {
                Text("Расходов пока нет")
                    .font(.headline)

                Text("Добавьте первый расход, чтобы начать вести учёт по этому проекту.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    if project != nil {
                        if isReadOnlyBlocked {
                            showReadOnlyAlert = true
                        } else {
                            showAddSheet = true
                        }
                    }
                } label: {
                    Text("Добавить расход")
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
        }
    }
}

// MARK: - Formatting

private func formatAmount(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.decimalSeparator = ","
    formatter.maximumFractionDigits = 0

    let number = amount as NSDecimalNumber
    return formatter.string(from: number) ?? "\(amount)"
}

private func formatDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

// MARK: - Фильтры

struct ExpenseFilters {
    var category: ExpenseCategory? = nil
    var subCategory: ExpenseSubCategory? = nil
    var dateFrom: Date? = nil
    var dateTo: Date? = nil
    var query: String = ""

    var isEmpty: Bool {
        category == nil &&
        subCategory == nil &&
        dateFrom == nil &&
        dateTo == nil &&
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Краткое текстовое резюме активных фильтров
    var summaryText: String {
        var parts: [String] = []

        if let category {
            parts.append(category.shortTitle)
        }
        if let subCategory {
            parts.append(subCategory.title)
        }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if let from = dateFrom, let to = dateTo {
            let df = Self.dateFormatter
            parts.append("от \(df.string(from: from)) до \(df.string(from: to))")
        } else if let from = dateFrom {
            let df = Self.dateFormatter
            parts.append("с \(df.string(from: from))")
        } else if let to = dateTo {
            let df = Self.dateFormatter
            parts.append("до \(df.string(from: to))")
        }

        if !trimmedQuery.isEmpty {
            parts.append("поиск: \"\(trimmedQuery)\"")
        }

        return parts.joined(separator: " • ")
    }

    mutating func reset() {
        category = nil
        subCategory = nil
        dateFrom = nil
        dateTo = nil
        query = ""
    }

    // Отдельный форматтер, чтобы не создавать DateFormatter на каждый вызов
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .none
        return df
    }()
}
