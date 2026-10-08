import SwiftUI
import Combine

private struct DemoTrainingAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [DemoTrainingAnchorID: CGRect] = [:]
    static func reduce(value: inout [DemoTrainingAnchorID: CGRect], nextValue: () -> [DemoTrainingAnchorID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Last measured frame, kept outside SwiftUI state so scrolling never invalidates the host view.
private final class DemoTrainingAnchorBox {
    var rect: CGRect?
}

/// Marks a real UI element as a tour target. Frames are reported in the global (window) space.
///
/// The modifier is a no-op for the controller until a tour is running (tours only run in DEMO),
/// so a normal registered profile pays only for a passive geometry read.
struct DemoTrainingAnchorModifier: ViewModifier {
    let id: DemoTrainingAnchorID
    var isEnabled: Bool = true

    @State private var box = DemoTrainingAnchorBox()

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { geo in
                    Color.clear.preference(
                        key: DemoTrainingAnchorPreferenceKey.self,
                        value: isEnabled ? [id: geo.frame(in: .global)] : [:]
                    )
                }
            }
            .onPreferenceChange(DemoTrainingAnchorPreferenceKey.self) { values in
                guard let rect = values[id] else { return }
                box.rect = rect
                let training = DemoTrainingController.shared
                if training.activeTour != nil {
                    training.updateAnchor(id, rect: rect)
                }
            }
            // A tour started after this element was already on screen: report its last frame.
            .onReceive(
                DemoTrainingController.shared.$activeTour
                    .receive(on: DispatchQueue.main)
            ) { tour in
                guard tour != nil, isEnabled, let rect = box.rect else { return }
                DemoTrainingController.shared.updateAnchor(id, rect: rect)
            }
            .onChange(of: isEnabled) { _, enabled in
                if !enabled {
                    box.rect = nil
                    DemoTrainingController.shared.clearAnchor(id)
                }
            }
            .onDisappear {
                DemoTrainingController.shared.clearAnchor(id)
            }
    }
}

extension View {
    func demoTrainingAnchor(_ id: DemoTrainingAnchorID) -> some View {
        modifier(DemoTrainingAnchorModifier(id: id))
    }

    /// Anchor only while `condition` holds (e.g. the DEMO project card, the first photo group).
    func demoTrainingAnchor(_ id: DemoTrainingAnchorID, when condition: Bool) -> some View {
        modifier(DemoTrainingAnchorModifier(id: id, isEnabled: condition))
    }
}

/// Applies the demo-card tour anchor only for the session DEMO project.
struct DemoTrainingDemoCardAnchorModifier: ViewModifier {
    let isDemoCard: Bool
    var anchor: DemoTrainingAnchorID = .projectsDemoCard

    func body(content: Content) -> some View {
        content.demoTrainingAnchor(anchor, when: isDemoCard)
    }
}
