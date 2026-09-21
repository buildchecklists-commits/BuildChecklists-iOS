import SwiftUI
import Charts

/// Точка данных для графика
private struct ExpenseChartPoint: Identifiable {
    let id = UUID()
    let category: ExpenseCategory
    let subCategory: ExpenseSubCategory
    let amount: Decimal

    var amountDouble: Double {
        (amount as NSDecimalNumber).doubleValue
    }
}

struct ProjectExpensesChartView: View {
    @EnvironmentObject var store: AppStore
    let projectID: UUID

    private var project: Project? {
        store.project(by: projectID)
    }

    /// Все расходы по проекту
    private var projectExpenses: [ExpenseItem] {
        store.expenses(for: projectID)
    }

    /// Категории, по которым реально есть расходы
    private var categoriesWithData: [ExpenseCategory] {
        var used: Set<ExpenseCategory> = []
        for exp in projectExpenses {
            if exp.amount != 0 {
                used.insert(exp.category)
            }
        }
        // Сохраняем порядок, в котором объявлены категории
        return ExpenseCategory.allCases.filter { used.contains($0) }
    }

    /// Все точки для графика (каждому сочетанию этап + тип расхода — своя колонка в стэке)
    private var chartData: [ExpenseChartPoint] {
        var map: [ExpenseCategory: [ExpenseSubCategory: Decimal]] = [:]

        for expense in projectExpenses {
            var subMap = map[expense.category] ?? [:]
            subMap[expense.subCategory, default: 0] += expense.amount
            map[expense.category] = subMap
        }

        var result: [ExpenseChartPoint] = []

        for cat in ExpenseCategory.allCases {
            guard let subMap = map[cat] else { continue }

            for sub in ExpenseSubCategory.allCases {
                let sum = subMap[sub] ?? 0
                if sum > 0 {
                    result.append(
                        ExpenseChartPoint(
                            category: cat,
                            subCategory: sub,
                            amount: sum
                        )
                    )
                }
            }
        }

        return result
    }

    /// Всего по проекту
    private var total: Decimal {
        projectExpenses.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(project: project)

                        if chartData.isEmpty {
                            Text("Пока нечего отображать на графике.\nДобавьте расходы по проекту.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else {
                            chartSection
                            legendSection
                        }

                        Spacer(minLength: 12)
                    }
                    .padding()
                }
                .navigationTitle("График расходов")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("Проект не найден")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Subviews

    private func header(project: Project) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.headline)
            Text("Всего расходов: \(formatAmount(total))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Горизонтально скроллируемый столбчатый график
    private var chartSection: some View {
        // Сколько этапов реально есть
        let count = max(categoriesWithData.count, 3)
        // Ширина под один этап (можно подрегулировать, если захочешь крупнее/мельче)
        let stepWidth: CGFloat = 80
        let chartWidth: CGFloat = CGFloat(count) * stepWidth

        return VStack(alignment: .leading, spacing: 12) {
            Text("По этапам и типам расходов")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: true) {
                Chart(chartData) { point in
                    BarMark(
                        x: .value("Этап", point.category.shortTitle),
                        y: .value("Сумма", point.amountDouble)
                    )
                    .foregroundStyle(by: .value("Тип", point.subCategory.title))
                    .position(by: .value("Тип", point.subCategory.title))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(width: chartWidth, height: 260)
            }
        }
    }

    /// Легенда: суммарно по каждому типу расхода
    private var legendSection: some View {
        let totalsBySub: [(ExpenseSubCategory, Decimal)] = {
            var map: [ExpenseSubCategory: Decimal] = [:]
            for exp in projectExpenses {
                map[exp.subCategory, default: 0] += exp.amount
            }
            return ExpenseSubCategory.allCases.compactMap { sub in
                let sum = map[sub] ?? 0
                return sum > 0 ? (sub, sum) : nil
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            Text("По типам расходов")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(totalsBySub, id: \.0.id) { sub, amount in
                HStack {
                    Text(sub.title)
                        .font(.subheadline)
                    Spacer()
                    Text(formatAmount(amount))
                        .font(.subheadline.bold())
                }
            }
        }
    }
}

// MARK: - Formatting helpers (локальные для этого файла)

private func formatAmount(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.groupingSeparator = " "
    formatter.decimalSeparator = ","
    formatter.maximumFractionDigits = 0

    let number = amount as NSDecimalNumber
    return formatter.string(from: number) ?? "\(amount)"
}

private func shortAmount(_ amount: Decimal) -> String {
    // Небольшая укороченная форма (если захочешь добавить подписи на столбцы)
    let number = (amount as NSDecimalNumber).doubleValue

    if number >= 1_000_000 {
        return String(format: "%.1fM", number / 1_000_000)
    } else if number >= 1_000 {
        return String(format: "%.0fK", number / 1_000)
    } else {
        return String(format: "%.0f", number)
    }
}
