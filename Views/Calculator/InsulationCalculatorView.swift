import SwiftUI

/// Калькулятор утеплителя
/// Режимы:
/// 1) По площади: м² → упаковки (м² в упаковке)
/// 2) По объёму: площадь (м²) × толщина (мм) → м³
struct InsulationCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Mode

    private enum Mode: String, CaseIterable, Identifiable {
        case byPacks = "По упаковкам"
        case byVolume = "По объёму"

        var id: String { rawValue }
    }

    @State private var mode: Mode = .byPacks

    // MARK: - Inputs (common)

    @State private var areaText: String = ""

    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    // MARK: - By packs

    @State private var packAreaText: String = "6"   // м² в упаковке

    // MARK: - By volume

    @State private var thicknessMmText: String = "50"

    // MARK: - Focus

    @FocusState private var focusedField: Field?

    private enum Field {
        case area, reserve
        case packArea
        case thickness
    }

    // MARK: - Parsing

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private var area: Double { parseDouble(areaText) }
    private var packArea: Double { parseDouble(packAreaText) }
    private var thicknessMm: Double { parseDouble(thicknessMmText) }

    private var reservePercent: Double { max(0, parseDouble(reservePercentText)) }
    private var reserveMultiplier: Double { includeReserve ? (1.0 + reservePercent / 100.0) : 1.0 }

    // MARK: - Calculations

    private var isAreaValid: Bool { area > 0 }
    private var adjustedArea: Double {
        guard isAreaValid else { return 0 }
        return area * reserveMultiplier
    }

    private var packsCount: Int {
        guard adjustedArea > 0 && packArea > 0 else { return 0 }
        return Int(ceil(adjustedArea / packArea))
    }

    private var volumeM3: Double {
        guard adjustedArea > 0 && thicknessMm > 0 else { return 0 }
        let thicknessM = thicknessMm / 1000.0
        return adjustedArea * thicknessM
    }

    // MARK: - Formatting

    private func format(_ value: Double, maxFrac: Int = 2) -> String {
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
                    Picker("Режим", selection: $mode) {
                        ForEach(Mode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    metricRow(title: "Площадь", placeholder: "например 80", text: $areaText, focused: .area, unit: "м²")
                } header: {
                    Text("Параметры")
                }

                reserveSection

                if mode == .byPacks {
                    byPacksSection
                    byPacksResult
                } else {
                    byVolumeSection
                    byVolumeResult
                }
            }
        }
        .navigationTitle("Утеплитель")
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
                Text("Расчёт утеплителя")
                    .font(.headline)
                Text("Площадь → упаковки или объём")
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

    // MARK: - By packs

    private var byPacksSection: some View {
        Section {
            metricRow(title: "В упаковке", placeholder: "например 6", text: $packAreaText, focused: .packArea, unit: "м²")

            Text("Введите площадь, указанную на упаковке (м²).")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Упаковки")
        }
    }

    private var byPacksResult: some View {
        Section {
            if isAreaValid && packArea > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    resultRow(title: "Площадь с запасом", value: format(adjustedArea, maxFrac: 1), unit: "м²")
                    resultRow(title: "Упаковок", value: "\(packsCount)", unit: "шт")

                    Text("Упаковки округляются в большую сторону.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                Text("Введите площадь и м² в упаковке, чтобы увидеть расчёт.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
    }

    // MARK: - By volume

    private var byVolumeSection: some View {
        Section {
            metricRow(title: "Толщина", placeholder: "например 50", text: $thicknessMmText, focused: .thickness, unit: "мм")

            Text("Объём = площадь × толщина. Полезно для сравнения разных материалов.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("Объём")
        }
    }

    private var byVolumeResult: some View {
        Section {
            if isAreaValid && thicknessMm > 0 {
                VStack(alignment: .leading, spacing: 10) {
                    resultRow(title: "Площадь с запасом", value: format(adjustedArea, maxFrac: 1), unit: "м²")
                    resultRow(title: "Объём", value: format(volumeM3, maxFrac: 3), unit: "м³")
                }
                .padding(.vertical, 4)
            } else {
                Text("Введите площадь и толщину, чтобы увидеть расчёт.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Результат")
        }
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
