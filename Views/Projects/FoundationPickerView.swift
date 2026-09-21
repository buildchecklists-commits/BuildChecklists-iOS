import SwiftUI

struct FoundationPickerView: View {
    let project: Project
    let onFinished: () -> Void

    @EnvironmentObject var store: AppStore
    @State private var nextPush = false
    @State private var selected: FoundationType?

    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Фундамент")
                .font(.title2).bold()

            ScrollView {
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(FoundationType.allCases) { t in
                        PickerTile(title: t.title, imageName: t.iconName, isSelected: selected == t) {
                            selected = t
                            do {
                                try store.updateProjectMeta(project.id) { $0.foundationType = t }
                                nextPush = true
                            } catch { /* можно показать алерт */ }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            NavigationLink(isActive: $nextPush) {
                SlabPickerView(project: project, onFinished: onFinished)
            } label: { EmptyView() }
            .hidden()
        }
        .padding()
        .navigationTitle("Фундамент")
    }
}
