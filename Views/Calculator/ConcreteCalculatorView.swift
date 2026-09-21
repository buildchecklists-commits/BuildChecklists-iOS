import SwiftUI

/// MVP: калькулятор бетона (прямоугольный объём)
/// Всё в метрах. Запас: редактируемый + быстрый пресет 5%.
struct ConcreteCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var lengthText: String = ""
    @State private var widthText: String = ""
    @State private var heightText: String = ""

    @State private var includeReserve: Bool = true
    @State private var reservePercentText: String = "5"

    @FocusState private var focusedField: Field?

    private enum Field {
        case length, width, height, reserve
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

                        if !isValid {
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
