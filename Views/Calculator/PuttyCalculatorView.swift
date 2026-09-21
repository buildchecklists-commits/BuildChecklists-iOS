import SwiftUI

/// Калькулятор шпаклёвки
/// Ввод: площадь (м²), слоёв (1/2/3)
/// Расход: кг/м² на 1 слой (редактируемый)
/// Вывод: кг и мешки (мешок редактируемый, быстрые пресеты 20/25)
struct PuttyCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Inputs

    @State private var areaText: String = ""

    @State private var layers: Int = 2

    /// Расход кг/м² на 1 слой (по умолчанию условно 1.0 — пользователь может заменить по упаковке)
    @State private var consumptionPerLayerText: String = "1"

    @State private var bagWeightKgText: String = "25"

    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    @FocusState private var focusedField: Field?

    private enum Field {
        case area, consumption, bag, reserve
    }

    // MARK: - Parsing

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private var area: Double { parseDouble(areaText) }
    private var consumptionPerLayer: Double { parseDouble(consumptionPerLayerText) }
    private var bagWeightKg: Double { max(1, parseDouble(bagWeightKgText)) }

    private var reservePercent: Double { max(0, parseDouble(reservePercentText)) }
    private var reserveMultiplier: Double { includeReserve ? (1.0 + reservePercent / 100.0) : 1.0 }

    // MARK: - Calculations

    private var isValid: Bool {
        area > 0 && consumptionPerLayer > 0 && layers > 0
    }

    private var totalKgBase: Double {
        guard isValid else { return 0 }
        return area * Double(layers) * consumptionPerLayer
    }

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
                    metricRow(title: "Площадь", placeholder: "например 80", text: $areaText, focused: .area, unit: "м²")

                    Picker("Слоёв", selection: $layers) {
                        Text("1").tag(1)
                        Text("2").tag(2)
                        Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Параметры")
                }

                Section {
                    HStack {
                        Text("Расход на слой")
                        Spacer()
                        TextField("например 1", text: $consumptionPerLayerText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused($focusedField, equals: .consumption)
                        Text("кг/м²")
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Text("Вес мешка")
                        Spacer()

                        Button {
                            bagWeightKgText = "20"
                            focusedField = nil
                        } label: {
                            Text("20")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            bagWeightKgText = "25"
                            focusedField = nil
                        } label: {
                            Text("25")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.thinMaterial)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        TextField("25", text: $bagWeightKgText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .focused($focusedField, equals: .bag)

                        Text("кг")
                            .foregroundStyle(.secondary)
                    }

                    Text("Расход зависит от состава и основания. Уточните значение на упаковке и при необходимости замените.")
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

                            Text("Мешки округляются в большую сторону.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("Введите площадь и расход, чтобы увидеть расчёт.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Результат")
                }
            }
        }
        .navigationTitle("Шпаклёвка")
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
                Text("Площадь × слои → кг и мешки")
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
        placeholder: String,
        text: Binding<String>,
        focused: Field,
        unit: String
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
