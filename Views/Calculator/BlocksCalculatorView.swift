import SwiftUI

/// Калькулятор блоков / кирпича
/// Расчёт по периметру и высоте с вычетом проёмов (м²)
/// Толщина стены — в мм
struct BlocksCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Inputs

    @State private var perimeterText: String = ""
    @State private var heightText: String = ""

    @State private var wallThicknessMmText: String = "300"

    @State private var openingsAreaText: String = "0"

    // Запас
    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    // Параметры блока (универсально)
    @State private var blockLengthMmText: String = "600"
    @State private var blockHeightMmText: String = "200"

    @FocusState private var focusedField: Field?

    private enum Field {
        case perimeter, height, thickness
        case openings
        case reserve
        case blockLength, blockHeight
    }

    // MARK: - Parsing

    private func parseDouble(_ s: String) -> Double {
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    // MARK: - Reserve

    private var reservePercent: Double { max(0, parseDouble(reservePercentText)) }
    private var reserveMultiplier: Double { includeReserve ? (1.0 + reservePercent / 100.0) : 1.0 }

    // MARK: - Calculations

    private var perimeter: Double { parseDouble(perimeterText) }
    private var height: Double { parseDouble(heightText) }
    private var thicknessM: Double { parseDouble(wallThicknessMmText) / 1000.0 }
    private var openingsArea: Double { parseDouble(openingsAreaText) }

    /// Общая площадь стен
    private var wallsArea: Double {
        max(0, perimeter * height)
    }

    /// Чистая площадь кладки
    private var netArea: Double {
        max(0, wallsArea - openingsArea)
    }

    /// Чистая площадь кладки с запасом
    private var netAreaWithReserve: Double {
        netArea * reserveMultiplier
    }

    /// Площадь одного блока (фасад)
    private var blockFaceArea: Double {
        let l = parseDouble(blockLengthMmText) / 1000.0
        let h = parseDouble(blockHeightMmText) / 1000.0
        guard l > 0 && h > 0 else { return 0 }
        return l * h
    }

    /// Количество блоков (без запаса)
    private var blocksCount: Int {
        guard netArea > 0 && blockFaceArea > 0 else { return 0 }
        return Int(ceil(netArea / blockFaceArea))
    }

    /// Количество блоков (с запасом)
    private var blocksCountWithReserve: Int {
        guard netAreaWithReserve > 0 && blockFaceArea > 0 else { return 0 }
        return Int(ceil(netAreaWithReserve / blockFaceArea))
    }

    /// Объём кладки (без запаса)
    private var masonryVolume: Double {
        netArea * thicknessM
    }

    /// Объём кладки (с запасом)
    private var masonryVolumeWithReserve: Double {
        netAreaWithReserve * thicknessM
    }

    private var isValid: Bool {
        perimeter > 0 && height > 0 && thicknessM > 0
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
                    metricRow(title: "Периметр", text: $perimeterText, focused: .perimeter, unit: "м")
                    metricRow(title: "Высота стены", text: $heightText, focused: .height, unit: "м")
                } header: {
                    Text("Геометрия")
                }

                Section {
                    metricRow(title: "Толщина стены", text: $wallThicknessMmText, focused: .thickness, unit: "мм")
                } header: {
                    Text("Толщина")
                }

                Section {
                    metricRow(title: "Площадь проёмов", text: $openingsAreaText, focused: .openings, unit: "м²")

                    Text(
                        "Площадь окон и дверей можно взять из проекта дома. "
                        + "В проектах она обычно указана отдельной строкой — сложите значения и введите одной цифрой."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Проёмы")
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

                            Button {
                                reservePercentText = "10"
                                focusedField = nil
                            } label: {
                                Text("10%")
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
                    metricRow(title: "Длина блока", text: $blockLengthMmText, focused: .blockLength, unit: "мм")
                    metricRow(title: "Высота блока", text: $blockHeightMmText, focused: .blockHeight, unit: "мм")
                } header: {
                    Text("Размер блока")
                }

                Section {
                    if isValid {
                        VStack(alignment: .leading, spacing: 10) {
                            resultRow(title: "Площадь стен", value: format(wallsArea), unit: "м²")
                            resultRow(title: "Чистая площадь кладки", value: format(netArea), unit: "м²")

                            if includeReserve {
                                resultRow(title: "Площадь с запасом", value: format(netAreaWithReserve), unit: "м²")
                            }

                            Divider().padding(.vertical, 2)

                            resultRow(title: "Количество блоков", value: "\(blocksCount)", unit: "шт")

                            if includeReserve {
                                resultRow(title: "С запасом", value: "\(blocksCountWithReserve)", unit: "шт")
                            }

                            resultRow(title: "Объём кладки", value: format(masonryVolume, maxFrac: 2), unit: "м³")

                            if includeReserve {
                                resultRow(title: "С запасом", value: format(masonryVolumeWithReserve, maxFrac: 2), unit: "м³")
                            }
                        }
                        .padding(.vertical, 4)
                    } else {
                        Text("Введите периметр, высоту и толщину стены, чтобы увидеть расчёт.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Результат")
                }
            }
        }
        .navigationTitle("Блоки / кирпич")
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
                Text("Расчёт кладки")
                    .font(.headline)
                Text("По периметру и высоте с вычетом проёмов")
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
