import SwiftUI

/// MVP: Калькулятор арматуры
/// - Режимы: Плита / Лента
/// - Шаг сетки/хомутов: мм (с быстрым пресетом 200 мм)
/// - Считает общий метраж и вес (кг) по диаметру (кг/м)
struct RebarCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Mode

    private enum Mode: String, CaseIterable, Identifiable {
        case slab = "Плита"
        case strip = "Лента"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .slab

    // MARK: - Common (reserve)

    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    // MARK: - Slab inputs

    @State private var slabLengthText: String = ""
    @State private var slabWidthText: String = ""
    @State private var slabStepMmText: String = "200"
    @State private var slabLayers: Int = 2
    @State private var slabDiameter: RebarDiameter = .d12

    // MARK: - Strip inputs

    @State private var stripLengthText: String = ""
    @State private var stripLongBarsCount: Int = 4
    @State private var stripLongDiameter: RebarDiameter = .d12

    @State private var stripStirrupStepMmText: String = "200"
    @State private var stripStirrupDiameter: RebarDiameter = .d8

    // Сечение ленты для длины хомута
    @State private var stripWidthMmText: String = "400"
    @State private var stripHeightMmText: String = "600"
    @State private var stripHooksCmText: String = "20" // добавка на загибы (см)

    // MARK: - Focus

    @FocusState private var focusedField: Field?

    private enum Field {
        case slabLength, slabWidth, slabStep
        case stripLength, stripStep
        case stripWidth, stripHeight, stripHooks
        case reserve
    }

    // MARK: - Diameter table

    enum RebarDiameter: String, CaseIterable, Identifiable {
        case d6 = "6"
        case d8 = "8"
        case d10 = "10"
        case d12 = "12"
        case d14 = "14"
        case d16 = "16"
        case d18 = "18"
        case d20 = "20"

        var id: String { rawValue }

        /// кг/м (приближённые табличные значения)
        var kgPerMeter: Double {
            switch self {
            case .d6: return 0.222
            case .d8: return 0.395
            case .d10: return 0.617
            case .d12: return 0.888
            case .d14: return 1.210
            case .d16: return 1.580
            case .d18: return 2.000
            case .d20: return 2.470
            }
        }

        var title: String { "⌀\(rawValue) мм" }
    }

    // MARK: - Parsing helpers

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private func parseInt(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private func formatNumber(_ value: Double, maxFrac: Int = 2) -> String {
        let v = max(0, value)
        if v == 0 { return "0" }

        let f = NumberFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.numberStyle = .decimal
        f.maximumFractionDigits = maxFrac
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(maxFrac)f", v)
    }

    // MARK: - Reserve

    private var reservePercent: Double { max(0, parseDouble(reservePercentText)) }
    private var reserveMultiplier: Double { includeReserve ? (1.0 + reservePercent / 100.0) : 1.0 }

    // MARK: - Slab calculations

    private var slabLength: Double { parseDouble(slabLengthText) }
    private var slabWidth: Double { parseDouble(slabWidthText) }
    private var slabStepM: Double {
        let mm = parseDouble(slabStepMmText)
        return mm > 0 ? (mm / 1000.0) : 0
    }

    private var slabIsValid: Bool {
        slabLength > 0 && slabWidth > 0 && slabStepM > 0
    }

    /// Количество стержней по длине (стержни идут вдоль длины, раскладка по ширине)
    private var slabBarsAlongLengthCount: Int {
        guard slabIsValid else { return 0 }
        // раскладка по ширине с шагом step: N = floor(W/step) + 1
        return Int(floor(slabWidth / slabStepM)) + 1
    }

    /// Количество стержней по ширине (стержни идут вдоль ширины, раскладка по длине)
    private var slabBarsAlongWidthCount: Int {
        guard slabIsValid else { return 0 }
        return Int(floor(slabLength / slabStepM)) + 1
    }

    private var slabTotalLengthMeters: Double {
        guard slabIsValid else { return 0 }
        let oneLayer = Double(slabBarsAlongLengthCount) * slabLength
                    + Double(slabBarsAlongWidthCount) * slabWidth
        let layers = max(1, slabLayers)
        return oneLayer * Double(layers) * reserveMultiplier
    }

    private var slabWeightKg: Double {
        slabTotalLengthMeters * slabDiameter.kgPerMeter
    }

    // MARK: - Strip calculations

    private var stripLength: Double { parseDouble(stripLengthText) }

    private var stripStirrupStepM: Double {
        let mm = parseDouble(stripStirrupStepMmText)
        return mm > 0 ? (mm / 1000.0) : 0
    }

    private var stripWidthM: Double { parseDouble(stripWidthMmText) / 1000.0 }
    private var stripHeightM: Double { parseDouble(stripHeightMmText) / 1000.0 }
    private var stripHooksM: Double { parseDouble(stripHooksCmText) / 100.0 } // см -> м

    private var stripIsValid: Bool {
        stripLength > 0 && stripLongBarsCount > 0 && stripStirrupStepM > 0 && stripWidthM > 0 && stripHeightM > 0
    }

    private var stripLongitudinalLengthMeters: Double {
        guard stripIsValid else { return 0 }
        return stripLength * Double(max(1, stripLongBarsCount)) * reserveMultiplier
    }

    private var stripLongitudinalWeightKg: Double {
        stripLongitudinalLengthMeters * stripLongDiameter.kgPerMeter
    }

    private var stirrupCount: Int {
        guard stripIsValid else { return 0 }
        return Int(floor(stripLength / stripStirrupStepM)) + 1
    }

    /// Длина одного хомута: 2*(B+H) + загибы
    private var oneStirrupLengthMeters: Double {
        guard stripWidthM > 0 && stripHeightM > 0 else { return 0 }
        return 2.0 * (stripWidthM + stripHeightM) + max(0, stripHooksM)
    }

    private var stripStirrupsTotalLengthMeters: Double {
        guard stripIsValid else { return 0 }
        return Double(stirrupCount) * oneStirrupLengthMeters * reserveMultiplier
    }

    private var stripStirrupsWeightKg: Double {
        stripStirrupsTotalLengthMeters * stripStirrupDiameter.kgPerMeter
    }

    private var stripTotalLengthMeters: Double {
        stripLongitudinalLengthMeters + stripStirrupsTotalLengthMeters
    }

    private var stripTotalWeightKg: Double {
        stripLongitudinalWeightKg + stripStirrupsWeightKg
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            header

            Form {
                Section {
                    Picker("Тип", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                reserveSection

                if mode == .slab {
                    slabSection
                    slabResultSection
                } else {
                    stripSection
                    stripResultSection
                }
            }
        }
        .navigationTitle("Арматура")
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
                Text("Расчёт метража и веса")
                    .font(.headline)
                Text("Плита: сетка • Лента: продольная + хомуты")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - Reserve UI

    private var reserveSection: some View {
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
    }

    // MARK: - Slab UI

    private var slabSection: some View {
        Section {
            metricRow(title: "Длина", placeholder: "например 10", text: $slabLengthText, focused: .slabLength, unit: "м")
            metricRow(title: "Ширина", placeholder: "например 6", text: $slabWidthText, focused: .slabWidth, unit: "м")

            HStack(spacing: 10) {
                Text("Шаг сетки")
                Spacer()

                Button {
                    slabStepMmText = "200"
                    focusedField = nil
                } label: {
                    Text("200 мм")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                TextField("200", text: $slabStepMmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    .focused($focusedField, equals: .slabStep)

                Text("мм")
                    .foregroundStyle(.secondary)
            }

            Picker("Слоёв", selection: $slabLayers) {
                Text("1 слой").tag(1)
                Text("2 слоя").tag(2)
            }
            .pickerStyle(.segmented)

            Text("1 слой — одна сетка. 2 слоя — верх + низ.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Picker("Диаметр", selection: $slabDiameter) {
                ForEach(RebarDiameter.allCases) { d in
                    Text(d.title).tag(d)
                }
            }
        } header: {
            Text("Плита")
        }
    }

    private var slabResultSection: some View {
        Section {
            if slabIsValid {
                VStack(alignment: .leading, spacing: 10) {
                    resultRow(title: "Прутков вдоль длины", value: "\(slabBarsAlongLengthCount)", unit: "шт")
                    resultRow(title: "Прутков вдоль ширины", value: "\(slabBarsAlongWidthCount)", unit: "шт")

                    Divider().padding(.vertical, 2)

                    resultRow(title: "Общий метраж", value: formatNumber(slabTotalLengthMeters, maxFrac: 1), unit: "м")
                    resultRow(title: "Вес", value: formatNumber(slabWeightKg, maxFrac: 0), unit: "кг")

                    Text("Вес рассчитан по табличному значению кг/м для выбранного диаметра.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Введите длину, ширину и шаг сетки (в мм), чтобы увидеть расчёт.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
    }

    // MARK: - Strip UI

    private var stripSection: some View {
        Section {
            metricRow(title: "Длина ленты", placeholder: "например 40", text: $stripLengthText, focused: .stripLength, unit: "м")

            Stepper(value: $stripLongBarsCount, in: 1...24) {
                HStack {
                    Text("Продольных стержней")
                    Spacer()
                    Text("\(stripLongBarsCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Диаметр продольной", selection: $stripLongDiameter) {
                ForEach(RebarDiameter.allCases) { d in
                    Text(d.title).tag(d)
                }
            }

            Divider().padding(.vertical, 2)

            HStack(spacing: 10) {
                Text("Шаг хомутов")
                Spacer()

                Button {
                    stripStirrupStepMmText = "200"
                    focusedField = nil
                } label: {
                    Text("200 мм")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                TextField("200", text: $stripStirrupStepMmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 86)
                    .focused($focusedField, equals: .stripStep)

                Text("мм")
                    .foregroundStyle(.secondary)
            }

            Picker("Диаметр хомутов", selection: $stripStirrupDiameter) {
                ForEach(RebarDiameter.allCases) { d in
                    Text(d.title).tag(d)
                }
            }

            Divider().padding(.vertical, 2)

            HStack {
                Text("Сечение ленты")
                Spacer()
                Text("мм")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Ширина")
                Spacer()
                TextField("например 400", text: $stripWidthMmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($focusedField, equals: .stripWidth)
            }

            HStack {
                Text("Высота")
                Spacer()
                TextField("например 600", text: $stripHeightMmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($focusedField, equals: .stripHeight)
            }

            HStack {
                Text("Загибы, см")
                Spacer()
                TextField("например 20", text: $stripHooksCmText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                    .focused($focusedField, equals: .stripHooks)
            }
        } header: {
            Text("Лента")
        }
    }

    private var stripResultSection: some View {
        Section {
            if stripIsValid {
                VStack(alignment: .leading, spacing: 10) {
                    resultRow(title: "Метраж продольной", value: formatNumber(stripLongitudinalLengthMeters, maxFrac: 1), unit: "м")
                    resultRow(title: "Вес продольной", value: formatNumber(stripLongitudinalWeightKg, maxFrac: 0), unit: "кг")

                    Divider().padding(.vertical, 2)

                    resultRow(title: "Хомутов", value: "\(stirrupCount)", unit: "шт")
                    resultRow(title: "Длина 1 хомута", value: formatNumber(oneStirrupLengthMeters, maxFrac: 2), unit: "м")
                    resultRow(title: "Метраж хомутов", value: formatNumber(stripStirrupsTotalLengthMeters, maxFrac: 1), unit: "м")
                    resultRow(title: "Вес хомутов", value: formatNumber(stripStirrupsWeightKg, maxFrac: 0), unit: "кг")

                    Divider().padding(.vertical, 2)

                    resultRow(title: "Итого метраж", value: formatNumber(stripTotalLengthMeters, maxFrac: 1), unit: "м")
                    resultRow(title: "Итого вес", value: formatNumber(stripTotalWeightKg, maxFrac: 0), unit: "кг")

                    Text("Длина хомута = 2×(ширина+высота) + загибы. Вес — по табличному кг/м.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Введите длину ленты, шаг хомутов и сечение (мм), чтобы увидеть расчёт.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
    }

    // MARK: - Small UI helpers

    private func metricRow(title: String, placeholder: String, text: Binding<String>, focused: Field, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 90)
                .focused($focusedField, equals: focused)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(title: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
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
