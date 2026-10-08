#if DEBUG
import SwiftUI

/// Standalone visual gallery for prototype review. Not linked into the normal launch path.
struct DemoTrainingPreviewGallery: View {
    enum Scene: String, CaseIterable, Identifiable {
        case entry
        case menu
        case stepOnScreen
        case scrollBelow
        case scrollAbove

        var id: String { rawValue }
        var title: String {
            switch self {
            case .entry: return "Кнопка Обучение"
            case .menu: return "Меню туров"
            case .stepOnScreen: return "Шаг с целью на экране"
            case .scrollBelow: return "Цель ниже экрана"
            case .scrollAbove: return "Цель выше экрана"
            }
        }
    }

    @State private var scene: Scene = Self.sceneFromLaunchArguments()

    private var hidesScenePicker: Bool {
        ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("-DemoTrainingGalleryScene=") })
    }

    var body: some View {
        ZStack {
            fakeProjectsChrome
            switch scene {
            case .entry:
                VStack {
                    HStack {
                        Spacer()
                        DemoTrainingEntryButton()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding()
                    }
                    Spacer()
                }
            case .menu:
                Color.black.opacity(0.25).ignoresSafeArea()
                DemoTrainingMenuView()
            case .stepOnScreen, .scrollBelow, .scrollAbove:
                DemoTrainingOverlay()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !hidesScenePicker {
                Picker("Сцена", selection: $scene) {
                    ForEach(Scene.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .padding(8)
                .background(.bar)
            }
        }
        .onAppear { apply(scene) }
        .onChange(of: scene) { _, newValue in apply(newValue) }
    }

    private static func sceneFromLaunchArguments() -> Scene {
        let prefix = "-DemoTrainingGalleryScene="
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count),
              let scene = Scene(rawValue: String(raw)) else {
            return .menu
        }
        return scene
    }

    private var fakeProjectsChrome: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Мои проекты")
                .font(.largeTitle.bold())
            RoundedRectangle(cornerRadius: 12)
                .fill(ProjectUXColors.secondarySurface)
                .frame(height: 44)
                .overlay(Text("Фильтры").foregroundStyle(.secondary))
            RoundedRectangle(cornerRadius: 18)
                .fill(ProjectUXColors.cardSurface)
                .frame(height: 160)
                .overlay(alignment: .topLeading) {
                    Text("Учебный объект")
                        .font(.headline)
                        .padding()
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
                }
            ForEach(0..<6, id: \.self) { idx in
                RoundedRectangle(cornerRadius: 12)
                    .fill(ProjectUXColors.secondarySurface.opacity(0.7))
                    .frame(height: 72)
                    .overlay(Text("Блок \(idx + 1)").foregroundStyle(.secondary))
            }
            Spacer()
        }
        .padding()
        .background(ProjectUXColors.screenBackground)
    }

    private func apply(_ scene: Scene) {
        let training = DemoTrainingController.shared
        training.dismissMenu()
        training.exitTour()
        training.anchorFrames = [:]
        training.updateVisibleBounds(
            CGRect(x: 0, y: 0, width: 390, height: 844),
            safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
            surface: .root
        )

        switch scene {
        case .entry:
            break
        case .menu:
            training.openMenu()
        case .stepOnScreen:
            training.startTour(.projects)
            training.debugJumpToStep(0)
            training.updateAnchor(
                .projectsListHeader,
                rect: CGRect(x: 24, y: 120, width: 340, height: 48)
            )
        case .scrollBelow:
            training.startTour(.projects)
            training.debugJumpToStep(3)
            training.updateAnchor(
                .projectsDashboardStages,
                rect: CGRect(x: 24, y: 980, width: 340, height: 220)
            )
        case .scrollAbove:
            training.startTour(.projects)
            training.debugJumpToStep(3)
            training.updateAnchor(
                .projectsDashboardStages,
                rect: CGRect(x: 24, y: -180, width: 340, height: 220)
            )
        }
    }
}

#Preview("Demo training gallery") {
    DemoTrainingPreviewGallery()
}
#endif
