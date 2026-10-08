import SwiftUI

struct DemoTrainingMenuView: View {
    @ObservedObject private var training = DemoTrainingController.shared
    @Environment(\.dismiss) private var dismiss

    private var mainTours: [DemoTrainingTourID] {
        DemoTrainingTourID.allCases.filter { !$0.isTool }
    }

    private var toolTours: [DemoTrainingTourID] {
        DemoTrainingTourID.allCases.filter(\.isTool)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Короткие туры по реальным экранам. Любой можно пройти снова.")
                        .font(.subheadline)
                        .foregroundStyle(ProjectUXColors.secondaryText)
                        .listRowBackground(Color.clear)
                }

                Section("Разделы") {
                    ForEach(mainTours) { tour in
                        tourRow(tour)
                    }
                }

                Section("Инструменты") {
                    ForEach(toolTours) { tour in
                        tourRow(tour)
                    }
                }
            }
            .navigationTitle("Что хотите освоить?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") {
                        training.dismissMenu()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func tourRow(_ tour: DemoTrainingTourID) -> some View {
        Button {
            guard tour.isImplemented else { return }
            training.startTour(tour)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: tour.systemImage)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.accentAction)
                    .frame(width: 28, alignment: .center)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tour.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(ProjectUXColors.primaryText)
                    }
                    Text(tour.blurb)
                        .font(.footnote)
                        .foregroundStyle(ProjectUXColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tour.title). \(tour.blurb)")
        .accessibilityHint("Запускает тур")
        .accessibilityIdentifier("demo.training.menu.\(tour.rawValue)")
    }
}
