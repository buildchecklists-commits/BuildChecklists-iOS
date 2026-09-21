import SwiftUI

struct ExpenseFilterView: View {
    @Binding var filters: ExpenseFilters
    @Environment(\.dismiss) private var dismiss

    // Локальные стейты для удобного редактирования
    @State private var selectedCategory: ExpenseCategory?
    @State private var selectedSubCategory: ExpenseSubCategory?
    @State private var useDateFrom: Bool = false
    @State private var useDateTo: Bool = false
    @State private var dateFrom: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var dateTo: Date = Date()
    @State private var query: String = ""

    @State private var selectedQuickPreset: DateQuickPreset? = nil

    var body: some View {
        Form {
            // ЭТАП
            Section("Этап строительства") {
                Picker("Этап", selection: Binding(
                    get: { selectedCategory ?? ExpenseCategory?.none },
                    set: { newValue in
                        selectedCategory = newValue
                    }
                )) {
                    Text("Все этапы").tag(ExpenseCategory?.none)

                    ForEach(ExpenseCategory.allCases) { cat in
                        Text(cat.title).tag(Optional(cat))
                    }
                }
            }

            // ТИП РАСХОДА
            Section("Тип расхода") {
                Picker("Тип", selection: Binding(
                    get: { selectedSubCategory ?? ExpenseSubCategory?.none },
                    set: { newValue in
                        selectedSubCategory = newValue
                    }
                )) {
                    Text("Все типы").tag(ExpenseSubCategory?.none)

                    ForEach(ExpenseSubCategory.allCases) { sub in
                        Text(sub.title).tag(Optional(sub))
                    }
                }
            }

            // ДАТЫ + БЫСТРЫЕ ПРЕСЕТЫ
            Section("Период") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Быстрый выбор")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(DateQuickPreset.allCases) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    Text(preset.title)
                                        .font(.caption)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            Capsule()
                                                .fill(selectedQuickPreset == preset ? Color.accentColor.opacity(0.15) : Color.clear)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedQuickPreset == preset ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                                        )
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.vertical, 4)

                Toggle("Фильтровать по дате «от»", isOn: $useDateFrom)
                if useDateFrom {
                    DatePicker("Дата от", selection: $dateFrom, displayedComponents: .date)
                }

                Toggle("Фильтровать по дате «до»", isOn: $useDateTo)
                if useDateTo {
                    DatePicker("Дата до", selection: $dateTo, displayedComponents: .date)
                }
            }

            // ПОИСК
            Section("Поиск по тексту") {
                TextField("Комментарий, этап, тип…", text: $query)
                Text("Ищем по заметке, названию этапа и типу расхода.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // СБРОС
            Section {
                Button(role: .destructive) {
                    resetLocal()
                    filters.reset()
                } label: {
                    Text("Сбросить все фильтры")
                }
            }
        }
        .navigationTitle("Фильтры расходов")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Отмена") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Готово") {
                    applyFilters()
                    dismiss()
                }
            }
        }
        .onAppear {
            syncFromFilters()
        }
    }

    // MARK: - Sync

    private func syncFromFilters() {
        selectedCategory = filters.category
        selectedSubCategory = filters.subCategory

        if let from = filters.dateFrom {
            useDateFrom = true
            dateFrom = from
        } else {
            useDateFrom = false
        }

        if let to = filters.dateTo {
            useDateTo = true
            dateTo = to
        } else {
            useDateTo = false
        }

        query = filters.query

        // При загрузке считаем, что пресет не выбран —
        // пользователь мог выставить произвольные даты.
        selectedQuickPreset = nil
    }

    private func resetLocal() {
        selectedCategory = nil
        selectedSubCategory = nil
        useDateFrom = false
        useDateTo = false
        dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        dateTo = Date()
        query = ""
        selectedQuickPreset = nil
    }

    private func applyFilters() {
        var newFilters = ExpenseFilters()

        newFilters.category = selectedCategory
        newFilters.subCategory = selectedSubCategory

        if useDateFrom {
            newFilters.dateFrom = dateFrom
        }
        if useDateTo {
            newFilters.dateTo = dateTo
        }

        if useDateFrom, useDateTo, dateFrom > dateTo {
            // если по ошибке выбрали "от" позже чем "до" — поменяем местами
            newFilters.dateFrom = dateTo
            newFilters.dateTo = dateFrom
        }

        newFilters.query = query.trimmingCharacters(in: .whitespacesAndNewlines)

        filters = newFilters
    }

    // MARK: - Пресеты периода

    private func applyPreset(_ preset: DateQuickPreset) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        selectedQuickPreset = preset

        switch preset {
        case .today:
            useDateFrom = true
            useDateTo = true
            dateFrom = startOfToday
            dateTo = now

        case .thisWeek:
            useDateFrom = true
            useDateTo = true
            // последние 7 дней, включая сегодня
            if let from = calendar.date(byAdding: .day, value: -6, to: startOfToday) {
                dateFrom = from
            } else {
                dateFrom = startOfToday
            }
            dateTo = now

        case .thisMonth:
            useDateFrom = true
            useDateTo = true
            let comps = calendar.dateComponents([.year, .month], from: startOfToday)
            if let monthStart = calendar.date(from: comps) {
                dateFrom = monthStart
            } else {
                dateFrom = startOfToday
            }
            dateTo = now

        case .allTime:
            // "Всё время" — убираем фильтры по датам
            useDateFrom = false
            useDateTo = false
        }
    }
}

// MARK: - Быстрые пресеты дат

private enum DateQuickPreset: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case thisMonth
    case allTime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:     return "Сегодня"
        case .thisWeek:  return "Неделя"
        case .thisMonth: return "Месяц"
        case .allTime:   return "Всё время"
        }
    }
}
