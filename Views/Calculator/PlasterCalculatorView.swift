import SwiftUI

/// Калькулятор штукатурки
/// Ввод: площадь (м²), толщина (мм)
/// Вывод: кг и мешки (25 кг)
/// Расход: кг/м² на 10 мм (редактируемый) + быстрый пресет
struct PlasterCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Inputs

    @State private var areaText: String = ""
    @State private var thicknessMmText: String = "10"

    /// Расход в кг/м² на 10 мм (по умолчанию часто 8–10 для цементных/гипсовых, зависит от смеси)
    @State private var consumptionPer10mmText: String = "9"

    @State private var bagWeightKgText: String = "25"

    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    @FocusState private var focusedField: Field?

    private enum Field {
        case area, thickness, consumption, bag, reserve
    }

    // MARK: - Parsing

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private var area: Double { parseDouble(areaText) }
    private var thicknessMm: Double { parseDouble(thicknessMmText) }
    private var consumptionPer10mm: Double { parseDouble(consumptionPer10mmText) }
    private var bagWeightKg: Double { max(1, parseDouble(bagWeightKgText)) }

    private var reservePercent: Double { max(0, parseDouble(reservePercentText)) }
    private var reserveMultiplier: Double { includeReserve ? (1.0 + reservePercent / 100.0) : 1.0 }

    // MARK: - Calculations

    private var isValid: Bool {
        area > 0 && thicknessMm > 0 && consumptionPer10mm > 0
    }

    /// кг без запаса
    private var totalKgBase: Double {
        guard isValid else { return 0 }
        // расход задан на 10 мм: total = area * (thickness/10) * consumption
        return area * (thicknessMm / 10.0) * consumptionPer10mm
    }

    /// кг с запасом (если включен)
    private var totalKg: Double {
        totalKgBase * reserveMultiplier
    }

    private var bagsCount: Int {
        guard totalKg > 0 else { return 0 }
        return Int(ceil(totalKg / bagWeightKg))
    }

    // MARK: - Formatting

    private func format(_ value: Double, maxFrac: Int = 1) -> String {
        let v = max(0, value)
        if v == 0 { return "0" }

        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxFrac
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(maxFrac)f", v)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            header

            Form {
                Section {
                    metricRow(title: "Площадь", text: $areaText, focused: .area, unit: "м²", placeholder: "например 120")
                    metricRow(title: "Толщина слоя", text: $thicknessMmText, focused: .thickness, unit: "мм", placeholder: "например 15")
                } header: {
                    Text("Параметры")
                }

                Section {
                    HStack(spacing: 10) {
                        Text("Расход на 10 мм")
                        Spacer()

                        Button {
                            consumptionPer10mmText = "9"
                            focusedField = nil
                        } label: {
                            Text("9")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        TextField("9", text: $consumptionPer10mmText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .consumption)

                        Text("кг/м²")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Вес мешка")
                        Spacer()
                        TextField("25", text: $bagWeightKgText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($focusedField, equals: .bag)
                        Text("кг")
                            .foregroundStyle(.secondary)
                    }

                    Text("Расход зависит от смеси. При необходимости замените значение на то, что указано на мешке.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Расход")
                }

                Section {
                    Toggle("Добавить запас", isOn: $includeReserve)

                    if includeReserve {
                        HStack(spacing: 10) {
                            Text("Запас, %")
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button {
                                reservePercentText = "5"
                                focusedField = nil
                            } label: {
                                Text("5%")
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(.thinMaterial)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)

                            TextField("5", text: $reservePercentText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 72)
                                .focused($focusedField, equals: .reserve)

                            Text("%")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Запас")
                }

                Section {
                    if isValid {
                        VStack(alignment: .leading, spacing: 10) {
                            resultRow(title: "Итого", value: format(totalKg, maxFrac: 0), unit: "кг")
                            resultRow(title: "Мешков", value: "\(bagsCount)", unit: "шт")

                            Text("Округление по мешкам идёт в большую сторону.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("Введите площадь и толщину слоя, чтобы увидеть расчёт.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Результат")
                }
            }
        }
        .navigationTitle("Штукатурка")
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
                Text("Расчёт расхода смеси")
                    .font(.headline)
                Text("Площадь × толщина → кг и мешки")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - UI helpers

    private func metricRow(
        title: String,
        text: Binding<String>,
        focused: Field,
        unit: String,
        placeholder: String
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 140)
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
