import SwiftUI

struct CalculatorHomeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Расчёты материалов") {

                NavigationLink {
                    ConcreteCalculatorView()
                } label: {
                    Label("Бетон", systemImage: "cube.fill")
                }

                NavigationLink {
                    RebarCalculatorView()
                } label: {
                    Label("Арматура", systemImage: "circle.grid.cross")
                }

                NavigationLink {
                    BoardsCalculatorView()
                } label: {
                    Label("Доска → м³", systemImage: "ruler")
                }

                NavigationLink {
                    BlocksCalculatorView()
                } label: {
                    Label("Блоки / кирпич", systemImage: "square.grid.3x3.fill")
                }

                NavigationLink {
                    PlasterCalculatorView()
                } label: {
                    Label("Штукатурка", systemImage: "paintbrush.fill")
                }

                NavigationLink {
                    PuttyCalculatorView()
                } label: {
                    Label("Шпаклёвка", systemImage: "paintbrush")
                }

                NavigationLink {
                    InsulationCalculatorView()
                } label: {
                    Label("Утеплитель", systemImage: "thermometer.snowflake")
                }
            }
        }
        .navigationTitle("Калькулятор")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
    }
}
