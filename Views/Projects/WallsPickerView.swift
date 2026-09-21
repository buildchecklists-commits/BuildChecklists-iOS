import SwiftUI

struct WallsPickerView: View {
    let project: Project
    let onFinished: () -> Void

    @EnvironmentObject var store: AppStore
    @State private var nextPush = false
    @State private var selected: WallType?

    private let cols = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Материал стен?")
                .font(.title2).bold()

            ScrollView {
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(WallType.allCases) { t in
                        PickerTile(title: t.title, imageName: t.iconName, isSelected: selected == t) {
                            selected = t
                            do {
                                try store.updateProjectMeta(project.id) { $0.wallType = t }
                                nextPush = true
                            } catch { }
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            NavigationLink(isActive: $nextPush) {
                RoofShapePickerView(project: project, onFinished: onFinished)
            } label: { EmptyView() }
            .hidden()
        }
        .padding()
        .navigationTitle("Стены")
    }
}
