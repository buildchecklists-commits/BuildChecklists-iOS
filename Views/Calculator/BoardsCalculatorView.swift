import SwiftUI

/// Калькулятор доски / пиломатериалов
/// Режимы:
/// 1) По размерам доски (мм) + количество → м³
/// 2) По площади (м²) + толщина (мм) → м³
struct BoardsCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Mode

    private enum Mode: String, CaseIterable, Identifiable {
        case byBoard = "По размерам"
        case byArea = "По площади"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .byBoard

    // MARK: - By board inputs

    @State private var thicknessMmText: String = "50"
    @State private var widthMmText: String = "150"
    @State private var lengthMText: String = "6"
    @State private var quantityText: String = "1"

    // MARK: - By area inputs

    @State private var areaText: String = ""
    @State private var areaThicknessMmText: String = "50"

    // MARK: - Focus

    @FocusState private var focusedField: Field?

    private enum Field {
        case thickness, width, length, qty
        case area, areaThickness
    }

    // MARK: - Parsing

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private func parseInt(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Calculations

    /// м³ одной доски
    private var oneBoardVolume: Double {
        let t = parseDouble(thicknessMmText) / 1000.0
        let w = parseDouble(widthMmText) / 1000.0
        let l = parseDouble(lengthMText)
        guard t > 0 && w > 0 && l > 0 else { return 0 }
        return t * w * l
    }

    /// м³ всего по количеству
    private var totalBoardsVolume: Double {
        oneBoardVolume * Double(max(0, parseInt(quantityText)))
    }

    /// м³ по площади
    private var areaVolume: Double {
        let area = parseDouble(areaText)
        let t = parseDouble(areaThicknessMmText) / 1000.0
        guard area > 0 && t > 0 else { return 0 }
        return area * t
    }

    // MARK: - Formatting

    private func format(_ value: Double) -> String {
        let v = max(0, value)
        if v == 0 { return "0" }

        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = v < 1 ? 4 : 3
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.3f", v)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            header

            Form {
                Section {
                    Picker("Режим", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .byBoard {
                    byBoardSection
                    byBoardResult
                } else {
                    byAreaSection
                    byAreaResult
                }
            }
        }
        .navigationTitle("Доска")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Готово") { focusedField = nil }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Расчёт объёма пиломатериала")
                    .font(.headline)
                Text("Результат в кубических метрах (м³)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - By board UI

    private var byBoardSection: some View {
        Section {
            metricRow(title: "Толщина", text: $thicknessMmText, focused: .thickness, unit: "мм")
            metricRow(title: "Ширина", text: $widthMmText, focused: .width, unit: "мм")
            metricRow(title: "Длина", text: $lengthMText, focused: .length, unit: "м")

            HStack {
                Text("Количество")
                Spacer()
                TextField("например 20", text: $quantityText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($focusedField, equals: .qty)
                Text("шт")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Параметры доски")
        }
    }

    private var byBoardResult: some View {
        Section {
            if totalBoardsVolume > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    resultRow(title: "Объём 1 доски", value: format(oneBoardVolume), unit: "м³")
                    resultRow(title: "Итого", value: format(totalBoardsVolume), unit: "м³")
                }
                .padding(.vertical, 4)
            } else {
                Text("Введите размеры доски и количество.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
    }

    // MARK: - By area UI

    private var byAreaSection: some View {
        Section {
            HStack {
                Text("Площадь")
                Spacer()
                TextField("например 45", text: $areaText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .focused($focusedField, equals: .area)
                Text("м²")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Толщина")
                Spacer()
                TextField("например 50", text: $areaThicknessMmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .focused($focusedField, equals: .areaThickness)
                Text("мм")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("По площади")
        }
    }

    private var byAreaResult: some View {
        Section {
            if areaVolume > 0 {
                resultRow(title: "Итого", value: format(areaVolume), unit: "м³")
            } else {
                Text("Введите площадь и толщину.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
    }

    // MARK: - Small helpers

    private func metricRow(
        title: String,
        text: Binding<String>,
        focused: Field,
        unit: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
                .focused($focusedField, equals: focused)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(title: String, value: String, unit: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}
