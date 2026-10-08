import SwiftUI

/// MVP: калькулятор бетона (прямоугольный объём)
/// Всё в метрах. Запас: редактируемый + быстрый пресет 5%.
///
/// `trainingExample`: temporary DEMO-tour seed (10×6×0.2 м → 12 м³ / 12,6 м³ с 5%).
/// Only the tour-pushed instance uses it; the normal calculator entry stays empty.
struct ConcreteCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    /// Isolated to the calculator instance opened by the DEMO training tour.
    private let trainingExample: Bool

    @State private var lengthText: String
    @State private var widthText: String
    @State private var heightText: String

    @State private var includeReserve: Bool
    @State private var reservePercentText: String

    @FocusState private var focusedField: Field?

    private enum Field {
        case length, width, height, reserve
    }

    init(trainingExample: Bool = false) {
        self.trainingExample = trainingExample
        if trainingExample {
            _lengthText = State(initialValue: "10")
            _widthText = State(initialValue: "6")
            _heightText = State(initialValue: "0.2")
            _includeReserve = State(initialValue: true)
            _reservePercentText = State(initialValue: "5")
        } else {
            _lengthText = State(initialValue: "")
            _widthText = State(initialValue: "")
            _heightText = State(initialValue: "")
            _includeReserve = State(initialValue: true)
            _reservePercentText = State(initialValue: "5")
        }
    }

    private var length: Double { parseDouble(lengthText) }
    private var width: Double { parseDouble(widthText) }
    private var height: Double { parseDouble(heightText) }

    private var baseVolume: Double {
        max(0, length) * max(0, width) * max(0, height)
    }

    private var reservePercent: Double {
        max(0, parseDouble(reservePercentText))
    }

    private var volumeWithReserve: Double {
        guard includeReserve else { return baseVolume }
        return baseVolume * (1.0 + reservePercent / 100.0)
    }

    private var isValid: Bool {
        length > 0 && width > 0 && height > 0
    }

    var body: some View {
        VStack(spacing: 14) {
            header

            Form {
                Section {
                    metricRow(title: "Длина", placeholder: "например 10", text: $lengthText, focused: .length)
                        .demoTrainingAnchor(.calculatorConcreteParams)
                    metricRow(title: "Ширина", placeholder: "например 6", text: $widthText, focused: .width)
                    metricRow(title: "Толщина / высота", placeholder: "например 0.2", text: $heightText, focused: .height)
                } header: {
                    Text("Параметры")
                }

                Section {
                    Toggle("Добавить запас", isOn: $includeReserve)

                    if includeReserve {
                        HStack(spacing: 10) {
                            Text("Запас, %")
                                .foregroundStyle(.secondary)

                            Spacer()

                            // Быстрые пресеты
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
                    VStack(alignment: .leading, spacing: 10) {
                        resultRow(title: "Объём бетона", value: format(baseVolume), unit: "м³")

                        if includeReserve {
                            resultRow(title: "С запасом", value: format(volumeWithReserve), unit: "м³")
                        }

                        if trainingExample {
                            Text("Учебный пример тура. В обычном калькуляторе поля остаются вашими.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if !isValid {
                            Text("Введите длину, ширину и толщину (в метрах), чтобы увидеть расчёт.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else if includeReserve {
                            Text("Рекомендация: запас обычно 5–10% (потери, погрешности, подрезка).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .demoTrainingAnchor(.calculatorConcreteResult)
                } header: {
                    Text("Результат")
                }
            }
        }
        .navigationTitle("Бетон")
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
                Text("Расчёт объёма")
                    .font(.headline)
                Text("Плита / лента / прямоугольный участок")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }

    // MARK: - UI Helpers

    private func metricRow(title: String, placeholder: String, text: Binding<String>, focused: Field) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .focused($focusedField, equals: focused)
                .frame(minWidth: 90)
            Text("м")
                .foregroundStyle(.secondary)
        }
    }

    private func resultRow(title: String, value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.title3.weight(.semibold))
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Parsing & Formatting

    private func parseDouble(_ s: String) -> Double {
        // Поддержка запятой
        let cleaned = s
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        return Double(cleaned) ?? 0
    }

    private func format(_ value: Double) -> String {
        let v = max(0, value)
        if v == 0 { return "0" }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = v < 10 ? 3 : 2
        formatter.minimumFractionDigits = 0

        return formatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    }
}
