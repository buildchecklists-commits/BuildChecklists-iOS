import SwiftUI

struct RoofCoverPickerView: View {
    let project: Project
    let onFinished: () -> Void

    @EnvironmentObject var store: AppStore
    @State private var selected: RoofCoverType?

    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Покрытие крыши?")
                .font(.title2).bold()

            ScrollView {
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(RoofCoverType.allCases) { t in
                        PickerTile(title: t.title, imageName: t.iconName, isSelected: selected == t) {
                            selected = t
                            do {
                                try store.updateProjectMeta(project.id) { $0.roofCoverType = t }
                                // Финиш всей цепочки
                                onFinished()
                            } catch { }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding()
        .navigationTitle("Покрытие")
    }
}
