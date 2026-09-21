import SwiftUI
import UIKit

struct ExpensesExportView: View {
    @EnvironmentObject var store: AppStore
    let projectID: UUID

    @Environment(\.dismiss) private var dismiss

    @State private var showShare = false
    @State private var shareURL: URL?
    @State private var lastError: String?

    // Период для PDF-отчёта (используется в "Отчёте для заказчика")
    @State private var useDateFrom: Bool = false
    @State private var useDateTo: Bool = false
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()

    // Фильтры по этапу и типу расхода для отчёта для заказчика
    @State private var selectedCategory: ExpenseCategory? = nil
    @State private var selectedSubCategory: ExpenseSubCategory? = nil

    private var project: Project? {
        store.project(by: projectID)
    }

    var body: some View {
        Form {
            // Проект
            if let project {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(project.name)
                            .font(.headline)
                        if !project.address.isEmpty {
                            Text(project.address)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Период (для отчёта для заказчика)
            Section("Период отчёта (PDF для заказчика)") {
                Toggle("Фильтровать по дате «от»", isOn: $useDateFrom)
                if useDateFrom {
                    DatePicker("Дата от", selection: $dateFrom, displayedComponents: .date)
                }

                Toggle("Фильтровать по дате «до»", isOn: $useDateTo)
                if useDateTo {
                    DatePicker("Дата до", selection: $dateTo, displayedComponents: .date)
                }

                if useDateFrom || useDateTo {
                    Text("Если выбрать обе даты, отчёт будет только по расходам внутри этого диапазона.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Если не выбирать период, будут включены все расходы по проекту.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // Этап строительства
            Section("Этап строительства") {
                Picker("Этап", selection: Binding(
                    get: { selectedCategory },
                    set: { selectedCategory = $0 }
                )) {
                    Text("Все этапы")
                        .tag(ExpenseCategory?.none)

                    ForEach(ExpenseCategory.allCases) { category in
                        Text(category.title)
                            .tag(Optional(category))
                    }
                }
            }

            // Тип расхода
            Section("Тип расхода") {
                Picker("Тип", selection: Binding(
                    get: { selectedSubCategory },
                    set: { selectedSubCategory = $0 }
                )) {
                    Text("Все типы")
                        .tag(ExpenseSubCategory?.none)

                    ForEach(ExpenseSubCategory.allCases) { sub in
                        Text(sub.title)
                            .tag(Optional(sub))
                    }
                }
            }

            // Форматы файлов
            Section("Формат файла") {
                Button {
                    exportCSV()
                } label: {
                    HStack {
                        Image(systemName: "tablecells")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CSV для Excel / Numbers")
                            Text("Откроется в Excel, Numbers, Google Sheets")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    exportPDF()
                } label: {
                    HStack {
                        Image(systemName: "doc.richtext")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PDF-отчёт по расходам (список)")
                            Text("Сводный список всех операций")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    exportCustomerPDF()
                } label: {
                    HStack {
                        Image(systemName: "doc.text.magnifyingglass")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PDF-отчёт для заказчика")
                            Text("Группировка по этапам и типам, с учётом фильтров")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            // Ошибка
            if let lastError {
                Section("Ошибка") {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Экспорт расходов")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Закрыть") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $showShare, onDismiss: {
            shareURL = nil
        }) {
            if let url = shareURL {
                ExpensesShareSheet(activityItems: [url])
            } else {
                Text("Нет файла для экспорта")
            }
        }
    }

    // MARK: - Actions

    private func exportCSV() {
        lastError = nil
        guard let url = store.exportExpensesCSV(for: projectID) else {
            lastError = "Не удалось создать CSV. Возможно, ещё нет расходов."
            return
        }
        shareURL = url
        showShare = true
    }

    private func exportPDF() {
        lastError = nil
        guard let url = store.exportExpensesPDF(for: projectID) else {
            lastError = "Не удалось создать PDF. Возможно, ещё нет расходов."
            return
        }
        shareURL = url
        showShare = true
    }

    private func exportCustomerPDF() {
        lastError = nil

        var from: Date? = useDateFrom ? dateFrom : nil
        var to: Date? = useDateTo ? dateTo : nil

        // Если заданы обе даты, но "от" > "до" — поменяем местами
        if let f = from, let t = to, f > t {
            swap(&from, &to)
        }

        guard let url = store.exportCustomerExpensesPDF(
            for: projectID,
            dateFrom: from,
            dateTo: to
        ) else {
            lastError = "Не удалось создать PDF. Возможно, по выбранным фильтрам нет расходов."
            return
        }

        shareURL = url
        showShare = true
    }
}

// MARK: - UIKit Share Sheet

struct ExpensesShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
