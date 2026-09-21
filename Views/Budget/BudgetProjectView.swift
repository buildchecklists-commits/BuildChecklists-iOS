import SwiftUI
import Charts

/// Экран бюджета конкретного проекта.
/// Хедер (бюджет / потрачено / остаток / отклонение),
/// план/факт по этапам,
/// диаграммы по этапам и типам, сводка (сворачиваемая),
/// экспорт, фильтры (этап / тип / период) + список операций.
struct BudgetProjectView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let projectID: UUID

    // MARK: - Local state (фильтры)

    @State private var selectedStage: GlobalStageCategory? = nil
    @State private var selectedSubCategory: ExpenseSubCategory? = nil

    @State private var useDateFilter: Bool = false
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()

    // Поиск по операциям
    @State private var searchText: String = ""

    // Состояние раскрытия сводки
    @State private var isSummaryExpanded: Bool = true
    @State private var didSetInitialSummaryState: Bool = false

    // План / факт по этапам — по умолчанию закрыт
    @State private var isPlanExpanded: Bool = false

    // Плановый бюджет — показ редактора
    @State private var showPlanEditor: Bool = false

    // Read-only UX
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    // MARK: - Computed

    private var project: Project? {
        store.project(by: projectID)
    }

    private var totalSpent: Decimal {
        store.totalAmount(for: projectID)
    }

    private var totalsByStage: [GlobalStageCategory: Decimal] {
        store.totalsByStageCategory(for: projectID)
    }

    private var totalsBySubCategory: [ExpenseSubCategory: Decimal] {
        store.totalsBySubCategory(for: projectID)
    }

    /// Все расходы проекта (без фильтров) — для оценки «мало/много».
    private var allExpensesCount: Int {
        store.expenses(for: projectID).count
    }

    /// Правило авто-раскрытия сводки:
    /// - если операций ≤ 10 → раскрываем,
    /// - если > 10 → сворачиваем.
    private var summaryShouldBeExpanded: Bool {
        allExpensesCount <= 10
    }

    /// Formatter для поиска по дате.
    private static let searchDateFormatter: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "dd.MM.yyyy"
        return d
    }()

    /// Расходы проекта с учётом выбранных фильтров (этап / тип / период) и поиска.
    private var filteredExpenses: [ExpenseItem] {
        // Базовая фильтрация по этапу/типу/датам
        let base = store
            .filteredExpenses(
                for: projectID,
                stageCategory: selectedStage,
                subCategory: selectedSubCategory,
                dateFrom: useDateFilter ? dateFrom : nil,
                dateTo: useDateFilter ? dateTo : nil
            )
            .sorted { $0.date > $1.date }

        // Если строка поиска пустая — возвращаем базовый список
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        let query = trimmed.lowercased()

        // Фильтруем по названию этапа, типу, заметке и дате (dd.MM.yyyy)
        return base.filter { expense in
            let stageTitle = (expense.stageCategory?.title ?? expense.category.title)
            let typeTitle = expense.subCategory.title
            let note = expense.note ?? ""
            let dateString = Self.searchDateFormatter.string(from: expense.date)

            let haystack = [
                stageTitle,
                typeTitle,
                note,
                dateString
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(query)
        }
    }

    /// План/факт по всем этапам (используем для таблицы).
    private var planFactRows: [(stage: GlobalStageCategory, plan: Decimal, fact: Decimal, diff: Decimal)] {
        store.planFactByStage(for: projectID)
    }

    /// Отфильтровываем только те этапы, где есть план или факт.
    private var planFactRowsFiltered: [(stage: GlobalStageCategory, plan: Decimal, fact: Decimal, diff: Decimal)] {
        planFactRows.filter { $0.plan > 0 || $0.fact > 0 }
    }

    /// Суммарный план по всем этапам.
    private var totalPlannedByStages: Decimal {
        planFactRows.reduce(0) { $0 + $1.plan }
    }

    var body: some View {
        Group {
            if let project {
                content(for: project)
            } else {
                Text("Проект не найден")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(project?.name ?? "Бюджет")
        .navigationBarTitleDisplayMode(.inline)

        // Плановый бюджет — редактор
        .sheet(isPresented: $showPlanEditor) {
            BudgetPlanEditorView(projectID: projectID)
                .environmentObject(store)
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
            Text("Сейчас активен режим просмотра. Для редактирования бюджета и планов по этапам нужна подписка USER или PRO.")
        }

        .onAppear {
            if !didSetInitialSummaryState {
                isSummaryExpanded = summaryShouldBeExpanded
                didSetInitialSummaryState = true
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for project: Project) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // ✅ Баннер read-only (единый профессиональный UX)
                if store.isReadOnlyMode {
                    readOnlyBanner
                }

                // Хедер: бюджет / потрачено / остаток / отклонение
                BudgetProjectHeaderView(
                    project: project,
                    totalSpent: totalSpent
                )

                // План / факт по этапам (сворачиваемый блок)
                if !planFactRowsFiltered.isEmpty {
                    planFactBlock
                } else {
                    planEmptyBlock
                }

                // Диаграммы по этапам (Pie + Bar)
                if !totalsByStageFiltered.isEmpty {
                    chartsBlock
                }

                // Диаграмма по типам расходов (Материалы / Работа / Аренда)
                if !totalsBySubCategoryFiltered.isEmpty {
                    subCategoryChartBlock
                }

                // Блок экспорта
                if allExpensesCount > 0 {
                    exportBlock
                }

                // Краткая сводка (цифры по этапам и типам, сворачиваемая)
                summaryDebugBlock

                // Фильтры (этап / тип / период)
                filtersBlock

                // Список расходов + поиск
                expensesListBlock

                Spacer(minLength: 0)
            }
            .padding()
        }
    }

    private var readOnlyBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "lock.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text("Режим только просмотр")
                    .font(.subheadline.weight(.semibold))
            }

            Text("Сейчас активен режим просмотра. Чтобы изменять бюджет, планы по этапам и операции, нужна подписка USER или PRO.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    _ = await store.refreshRoleForCurrentUser()
                    if store.isReadOnlyMode {
                        showPaywall = true
                    }
                }
            } label: {
                Text("Разблокировать")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Blocks

    /// Блок план/факт по этапам (DisclosureGroup, по умолчанию закрыт)
    private var planFactBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isPlanExpanded) {
                VStack(alignment: .leading, spacing: 8) {

                    // Мини-сводка: план по этапам + общий бюджет проекта + разница
                    if totalPlannedByStages > 0 || (project?.budget ?? 0) > 0 {
                        VStack(alignment: .leading, spacing: 4) {
                            if totalPlannedByStages > 0 {
                                Text("План по этапам: \(format(totalPlannedByStages))")
                                    .font(.caption)
                            }
                            if let projectBudget = project?.budget, projectBudget > 0 {
                                Text("Общий бюджет проекта: \(format(projectBudget))")
                                    .font(.caption)

                                let diff = totalPlannedByStages - projectBudget
                                if diff != 0 {
                                    if diff > 0 {
                                        Text("План по этапам превышает общий бюджет на \(format(diff)). Возможен перерасход.")
                                            .font(.caption2)
                                            .foregroundStyle(.red)
                                    } else {
                                        Text("Сумма планов по этапам меньше общего бюджета на \(format(-diff)). Часть бюджета не распределена по этапам.")
                                            .font(.caption2)
                                            .foregroundStyle(.orange)
                                    }

                                    Button {
                                        if store.isReadOnlyMode {
                                            showReadOnlyAlert = true
                                            return
                                        }
                                        syncOverallBudgetToStages()
                                    } label: {
                                        Text("Сделать общий бюджет равным сумме по этапам")
                                            .font(.caption)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        // На compact (XR) уже колонки чисел — больше места под название этапа.
                        let planFactValueColWidth: CGFloat = horizontalSizeClass == .compact ? 56 : 96
                        let numFont: Font = horizontalSizeClass == .compact ? .caption2 : .caption

                        HStack(alignment: .top, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                            Text("Этап")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("План")
                                .font(numFont)
                                .foregroundStyle(.secondary)
                                .frame(width: planFactValueColWidth, alignment: .trailing)
                            Text("Факт")
                                .font(numFont)
                                .foregroundStyle(.secondary)
                                .frame(width: planFactValueColWidth, alignment: .trailing)
                            Text("Δ")
                                .font(numFont)
                                .foregroundStyle(.secondary)
                                .frame(width: planFactValueColWidth, alignment: .trailing)
                        }

                        ForEach(planFactRowsFiltered, id: \.stage.id) { row in
                            HStack(alignment: .top, spacing: horizontalSizeClass == .compact ? 6 : 8) {
                                Text(row.stage.title)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(format(row.plan))
                                    .font(numFont)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .allowsTightening(true)
                                    .frame(width: planFactValueColWidth, alignment: .trailing)
                                Text(format(row.fact))
                                    .font(numFont)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .allowsTightening(true)
                                    .frame(width: planFactValueColWidth, alignment: .trailing)
                                Text(format(row.diff))
                                    .font(numFont)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.55)
                                    .allowsTightening(true)
                                    .foregroundStyle(
                                        row.diff > 0 ? .red :
                                            (row.diff < 0 ? .green : .secondary)
                                    )
                                    .frame(width: planFactValueColWidth, alignment: .trailing)
                            }
                        }
                    }

                    Button {
                        if store.isReadOnlyMode {
                            showReadOnlyAlert = true
                            return
                        }
                        showPlanEditor = true
                    } label: {
                        Text("Настроить плановый бюджет")
                            .font(.caption)
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text("План / факт по этапам")
                        .font(.headline)
                        .foregroundStyle(Color("AccentYellow"))
                    Spacer()
                    Image(systemName: isPlanExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Блок, когда ещё нет ни плана, ни факта — только подсказка + кнопка, тоже в DisclosureGroup.
    private var planEmptyBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isPlanExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Задайте плановые суммы по этапам, чтобы видеть перерасход или экономию и сравнивать с фактическими расходами.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        if store.isReadOnlyMode {
                            showReadOnlyAlert = true
                            return
                        }
                        showPlanEditor = true
                    } label: {
                        Text("Настроить плановый бюджет")
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text("План / факт по этапам")
                        .font(.headline)
                        .foregroundStyle(Color("AccentYellow"))
                    Spacer()
                    Image(systemName: isPlanExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Круговая диаграмма по этапам (общая для compact / regular).
    private var stageExpensesDonutChart: some View {
        Chart {
            let total = totalStageExpensesSum

            ForEach(totalsByStageFiltered, id: \.0.id) { stage, value in
                let doubleValue = (value as NSDecimalNumber).doubleValue
                let share = total > 0 ? (doubleValue / total) : 0
                let percent = Int((share * 100).rounded())

                SectorMark(
                    angle: .value("Сумма", doubleValue),
                    innerRadius: .ratio(0.55),
                    angularInset: 1
                )
                .foregroundStyle(stage.color)
                .annotation(position: .overlay) {
                    if percent >= 5 {
                        Text("\(percent)%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(width: 180, height: 180)
    }

    /// Легенда к donut: на всю ширину под диаграммой на compact — без узкой правой колонки.
    private var stageExpensesLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(totalsByStageFiltered, id: \.0.id) { stage, value in
                let total = totalStageExpensesSum
                let doubleValue = (value as NSDecimalNumber).doubleValue
                let share = total > 0 ? (doubleValue / total) : 0
                let percent = Int((share * 100).rounded())

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(stage.color)
                        .frame(width: 10, height: 10)
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }

                    Text(stage.title)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(format(value))
                        .font(.caption2)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .layoutPriority(1)

                    if percent > 0 {
                        Text("\(percent)%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }
        }
    }

    /// Диаграммы по этапам: круговая + горизонтальная столбчатая.
    private var chartsBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Расходы по этапам")
                .font(.headline)

            if horizontalSizeClass == .compact {
                VStack(alignment: .leading, spacing: 14) {
                    stageExpensesDonutChart
                        .frame(maxWidth: .infinity)
                    stageExpensesLegend
                }
            } else {
                HStack(alignment: .center, spacing: 16) {
                    stageExpensesDonutChart
                    stageExpensesLegend
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Горизонтальная столбчатая диаграмма по этапам (по убыванию),
            // линии слева-направо, одна под другой.
            Chart {
                ForEach(totalsByStageFiltered, id: \.0.id) { stage, value in
                    let doubleValue = (value as NSDecimalNumber).doubleValue

                    BarMark(
                        x: .value("Сумма", doubleValue),
                        y: .value("Этап", stage.title)
                    )
                    .foregroundStyle(stage.color)
                    .annotation(position: .overlay, alignment: .leading) {
                        Text(stage.title)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.leading, 4)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine()
                    AxisTick()
                    // без AxisValueLabel: названия уже внутри баров
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom)
            }
            .frame(height: 220)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Диаграмма по типам расходов (вертикальная).
    private var subCategoryChartBlock: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Структура по типам расходов")
                .font(.headline)

            Chart {
                ForEach(totalsBySubCategoryFiltered, id: \.0.id) { sub, value in
                    let doubleValue = (value as NSDecimalNumber).doubleValue
                    BarMark(
                        x: .value("Тип", sub.title),
                        y: .value("Сумма", doubleValue)
                    )
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(totalsBySubCategoryFiltered, id: \.0.id) { sub, value in
                    HStack {
                        Text(sub.title)
                            .font(.caption)
                        Spacer()
                        Text(format(value))
                            .font(.caption)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.secondary)
                    }
                }

                if !totalsBySubCategoryFiltered.isEmpty {
                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("Итого")
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(format(totalSubCategoryExpenses))
                            .font(.caption)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Блок экспорта CSV / PDF.
    private var exportBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Экспорт")
                .font(.headline)

            HStack(spacing: 12) {
                if let csvURL = store.exportExpensesCSV(for: projectID) {
                    ShareLink(item: csvURL) {
                        Label("CSV", systemImage: "tablecells")
                            .font(.subheadline)
                    }
                }

                if let pdfURL = store.exportExpensesPDF(for: projectID) {
                    ShareLink(item: pdfURL) {
                        Label("PDF (все)", systemImage: "doc.richtext")
                            .font(.subheadline)
                    }
                }

                if let customerURL = store.exportCustomerExpensesPDF(
                    for: projectID,
                    dateFrom: useDateFilter ? dateFrom : nil,
                    dateTo: useDateFilter ? dateTo : nil
                ) {
                    ShareLink(item: customerURL) {
                        Label("PDF для заказчика", systemImage: "person.text.rectangle")
                            .font(.subheadline)
                    }
                }
            }

            Text("PDF для заказчика учитывает фильтр по датам, если он включён.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Сводка по этапам и типам — сворачиваемая карточка.
    private var summaryDebugBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $isSummaryExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !totalsByStageFiltered.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("По этапам:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(totalsByStageFiltered, id: \.0.id) { stage, value in
                                HStack {
                                    Text(stage.title)
                                        .font(.caption)
                                    Spacer()
                                    Text(format(value))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if !totalsBySubCategoryFiltered.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("По типам расходов:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)

                            ForEach(totalsBySubCategoryFiltered, id: \.0.id) { sub, value in
                                HStack {
                                    Text(sub.title)
                                        .font(.caption)
                                    Spacer()
                                    Text(format(value))
                                        .font(.caption)
                                        .monospacedDigit()
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text("Сводка по проекту")
                        .font(.headline)
                    Spacer()
                    Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Блок с фильтрами по этапу, типу расхода и периоду.
    private var filtersBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Фильтры")
                    .font(.headline)
                Spacer()
                if selectedStage != nil || selectedSubCategory != nil || useDateFilter {
                    Button("Сбросить") {
                        selectedStage = nil
                        selectedSubCategory = nil
                        useDateFilter = false
                        dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
                        dateTo = Date()
                        searchText = ""
                    }
                    .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Этап")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Этап", selection: $selectedStage) {
                    Text("Все этапы").tag(GlobalStageCategory?.none)
                    ForEach(GlobalStageCategory.allCases) { cat in
                        Text(cat.title)
                            .tag(GlobalStageCategory?.some(cat))
                    }
                }
                .pickerStyle(.menu)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Тип расхода")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Тип расхода", selection: $selectedSubCategory) {
                    Text("Все типы").tag(ExpenseSubCategory?.none)
                    ForEach(ExpenseSubCategory.allCases) { sub in
                        Text(sub.title)
                            .tag(ExpenseSubCategory?.some(sub))
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Период")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Фильтр по дате", isOn: $useDateFilter)
                    .font(.subheadline)

                if useDateFilter {
                    VStack(alignment: .leading, spacing: 8) {
                        DatePicker(
                            "С",
                            selection: $dateFrom,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "По",
                            selection: $dateTo,
                            displayedComponents: .date
                        )
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
    }

    /// Список расходов по выбранным фильтрам + поиск.
    private var expensesListBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Операции")
                .font(.headline)

            if allExpensesCount > 0 {
                // Строка поиска по операциям
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Поиск по этапу, типу, заметке или дате", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.top, 4)
            }

            if filteredExpenses.isEmpty {
                Text(allExpensesCount == 0
                     ? "Расходов по проекту пока нет."
                     : "По заданным фильтрам и поиску ничего не найдено.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredExpenses) { expense in
                        BudgetExpenseRow(expense: expense)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground).opacity(0.9))
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: Color.black.opacity(0.03), radius: 6, x: 0, y: 3)
            }
        }
    }

    // MARK: - Helpers: суммы

    /// Этапы с ненулевыми расходами, отсортированные по убыванию.
    private var totalsByStageFiltered: [(GlobalStageCategory, Decimal)] {
        GlobalStageCategory.allCases
            .compactMap { cat in
                let value = totalsByStage[cat] ?? 0
                return value == 0 ? nil : (cat, value)
            }
            .sorted { $0.1 > $1.1 }
    }

    /// Общая сумма расходов по всем этапам (для расчёта долей).
    private var totalStageExpensesSum: Double {
        totalsByStageFiltered
            .map { ($0.1 as NSDecimalNumber).doubleValue }
            .reduce(0, +)
    }

    /// Типы расходов с ненулевой суммой.
    private var totalsBySubCategoryFiltered: [(ExpenseSubCategory, Decimal)] {
        ExpenseSubCategory.allCases
            .compactMap { sub in
                let value = totalsBySubCategory[sub] ?? 0
                return value == 0 ? nil : (sub, value)
            }
    }

    /// Общая сумма по типам расходов.
    private var totalSubCategoryExpenses: Decimal {
        totalsBySubCategoryFiltered
            .map { $0.1 }
            .reduce(0, +)
    }

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    fileprivate func format(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        return Self.numberFormatter.string(from: number) ?? "\(value)"
    }

    // MARK: - Helpers: прогресс по этапу

    private func stageProgress(for stage: GlobalStageCategory) -> Double {
        func percent(_ stages: [Stage]?) -> Double {
            guard let stages, !stages.isEmpty else { return 0 }
            let items = stages.flatMap { $0.items }
            guard !items.isEmpty else { return 0 }
            let done = items.filter { $0.status == .ok }.count
            return Double(done) / Double(items.count)
        }

        switch stage {
        case .geologyAndPrep:
            return percent(GeologyProgressStore.load(projectID: projectID))
        case .foundation:
            return percent(FoundationProgressStore.load(projectID: projectID))
        case .walls:
            return percent(WallsProgressStore.load(projectID: projectID))
        case .slabs:
            return percent(SlabProgressStore.load(projectID: projectID))
        case .roof:
            return percent(RoofProgressStore.load(projectID: projectID))
        case .roofCover:
            return percent(RoofCoverProgressStore.load(projectID: projectID))
        case .engineering:
            return percent(EngineeringProgressStore.load(projectID: projectID))
        case .windows:
            return percent(WindowsProgressStore.load(projectID: projectID))
        case .doors:
            return percent(DoorsProgressStore.load(projectID: projectID))
        case .finishing:
            return percent(FinishingProgressStore.load(projectID: projectID))
        case .landscaping:
            return percent(LandscapingProgressStore.load(projectID: projectID))
        }
    }

    // MARK: - Actions

    /// Выставить общий бюджет проекта = сумме планов по этапам.
    private func syncOverallBudgetToStages() {
        guard !store.isReadOnlyMode else {
            showReadOnlyAlert = true
            return
        }

        guard var p = project else { return }
        p.budget = totalPlannedByStages
        do {
            try store.updateProject(p)
        } catch {
            #if DEBUG
            print("Failed to sync budget:", error.localizedDescription)
            #endif
        }
    }
}

/// Хедер бюджета проекта: бюджет / потрачено / остаток / отклонение.
struct BudgetProjectHeaderView: View {
    let project: Project
    let totalSpent: Decimal

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    private var budget: Decimal {
        project.budget ?? 0
    }

    private var remaining: Decimal {
        budget - totalSpent
    }

    private func format(_ value: Decimal) -> String {
        let number = value as NSDecimalNumber
        return Self.numberFormatter.string(from: number) ?? "\(value)"
    }

    /// Отклонение факта от бюджета: (Факт / Бюджет - 1) в процентах.
    private var deviationPercentText: String {
        guard budget > 0 else { return "—" }
        let spent = (totalSpent as NSDecimalNumber).doubleValue
        let total = (budget as NSDecimalNumber).doubleValue
        guard total > 0 else { return "—" }

        let ratio = spent / total - 1.0
        let percent = Int((ratio * 100).rounded())

        if percent > 0 {
            return "+\(percent)%"
        } else if percent < 0 {
            return "\(percent)%"
        } else {
            return "0%"
        }
    }

    private var deviationColor: Color {
        guard budget > 0 else { return .secondary }
        let spent = (totalSpent as NSDecimalNumber).doubleValue
        let total = (budget as NSDecimalNumber).doubleValue
        guard total > 0 else { return .secondary }
        return spent > total ? .red : .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.name)
                .font(.title3)
                .fontWeight(.semibold)

            if horizontalSizeClass == .compact {
                // iPhone в портрете: 2×2 — подписи не сжимаются до переноса по буквам.
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    budgetKPIBlock
                    spentKPIBlock
                    remainingKPIBlock
                    deviationKPIBlock
                }
            } else {
                HStack(spacing: 16) {
                    budgetKPIBlock
                    Spacer()
                    spentKPIBlock
                    Spacer()
                    remainingKPIBlock
                    Spacer()
                    deviationKPIBlock
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 4)
    }

    private var budgetKPIBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Бюджет")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if budget > 0 {
                Text(format(budget))
                    .font(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .allowsTightening(true)
            } else {
                Text("Не задан")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spentKPIBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Потрачено")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(format(totalSpent))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remainingKPIBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remaining >= 0 ? "Остаток" : "Перерасход")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(format(remaining))
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .foregroundStyle(remaining >= 0 ? .green : .red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviationKPIBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Отклонение")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(deviationPercentText)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .allowsTightening(true)
                .foregroundStyle(deviationColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка списка расходов в бюджете проекта.
struct BudgetExpenseRow: View {
    let expense: ExpenseItem

    private static let amountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let d = DateFormatter()
        d.dateFormat = "dd.MM.yyyy"
        return d
    }()

    private var amountString: String {
        let number = expense.amount as NSDecimalNumber
        return Self.amountFormatter.string(from: number) ?? "\(expense.amount)"
    }

    private var dateString: String {
        Self.dateFormatter.string(from: expense.date)
    }

    private var stageTitle: String {
        if let stage = expense.stageCategory {
            return stage.title
        } else {
            return expense.category.title
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(stageTitle) • \(expense.subCategory.title)")
                    .font(.subheadline)
                    .lineLimit(2)
                if let note = expense.note, !note.isEmpty {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(dateString)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(amountString)
                .font(.headline)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Плановый бюджет: редактор

struct BudgetPlanEditorView: View {
    @EnvironmentObject var store: AppStore
    let projectID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var localValues: [GlobalStageCategory: String] = [:]
    @State private var projectName: String = ""

    // Read-only UX (на всякий случай, даже если открытие уже заблокировано сверху)
    @State private var showReadOnlyAlert: Bool = false
    @State private var showPaywall: Bool = false

    private static let numberFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = " "
        f.maximumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            Form {
                if store.isReadOnlyMode {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Image(systemName: "lock.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("Режим только просмотр")
                                    .font(.subheadline.weight(.semibold))
                            }

                            Text("Сейчас активен режим просмотра. Для изменения планов по бюджету нужна подписка USER или PRO.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            Button {
                                Task {
                                    _ = await store.refreshRoleForCurrentUser()
                                    if store.isReadOnlyMode {
                                        showPaywall = true
                                    }
                                }
                            } label: {
                                Text("Разблокировать")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Text("Плановый бюджет по этапам. Значения задаются в условной валюте проекта.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Этапы") {
                    ForEach(GlobalStageCategory.allCases) { stage in
                        HStack {
                            Text(stage.title)
                                .font(.subheadline)
                            Spacer()
                            TextField(
                                "0",
                                text: Binding(
                                    get: { localValues[stage] ?? "" },
                                    set: { newValue in
                                        localValues[stage] = newValue
                                    }
                                )
                            )
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .allowsTightening(true)
                            .frame(minWidth: 90, maxWidth: 150, alignment: .trailing)
                            .onChange(of: localValues[stage] ?? "") { _, newValue in
                                let formatted = formatLiveInput(newValue)
                                if formatted != newValue {
                                    localValues[stage] = formatted
                                }
                            }
                            .disabled(store.isReadOnlyMode)
                        }
                    }
                }

                Section {
                    Button("Очистить все") {
                        if store.isReadOnlyMode {
                            showReadOnlyAlert = true
                            return
                        }
                        for stage in GlobalStageCategory.allCases {
                            localValues[stage] = ""
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(store.isReadOnlyMode)
                }
            }
            .navigationTitle(projectName.isEmpty ? "План по этапам" : projectName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
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
                Text("Сейчас активен режим просмотра. Для изменения планов по бюджету нужна подписка USER или PRO.")
            }

            .onAppear {
                loadInitialValues()
            }
        }
    }

    /// Живое форматирование ввода: оставляем только цифры и
    /// добавляем разделители тысяч.
    private func formatLiveInput(_ text: String) -> String {
        // Оставляем только цифры
        let digits = text.filter { $0.isNumber }
        guard !digits.isEmpty else { return "" }

        // Парсим как целое число
        guard let decimal = Decimal(string: digits) else {
            return text
        }

        let number = decimal as NSDecimalNumber
        return BudgetPlanEditorView.numberFormatter.string(from: number) ?? digits
    }

    private func loadInitialValues() {
        guard let project = store.project(by: projectID) else { return }
        projectName = project.name

        var dict: [GlobalStageCategory: String] = [:]
        for stage in GlobalStageCategory.allCases {
            let value = project.plannedBudget(for: stage)
            if value > 0 {
                let number = value as NSDecimalNumber
                let formatted = Self.numberFormatter.string(from: number) ?? "\(value)"
                dict[stage] = formatted
            } else {
                dict[stage] = ""
            }
        }
        localValues = dict
    }

    private func parseDecimal(from text: String) -> Decimal? {
        let trimmed = text
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")

        guard !trimmed.isEmpty else { return nil }
        return Decimal(string: trimmed)
    }

    private func save() {
        guard var project = store.project(by: projectID) else {
            dismiss()
            return
        }

        for stage in GlobalStageCategory.allCases {
            if let text = localValues[stage],
               let value = parseDecimal(from: text),
               value > 0 {
                project.setPlannedBudget(value, for: stage)
            } else {
                project.setPlannedBudget(nil, for: stage)
            }
        }

        do {
            try store.updateProject(project)
            dismiss()
        } catch {
            dismiss()
        }
    }
}
