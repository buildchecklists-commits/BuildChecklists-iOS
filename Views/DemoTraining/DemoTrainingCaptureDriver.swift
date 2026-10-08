import SwiftUI
import UIKit

#if DEBUG
/// DEBUG-only driver for live screenshots on real DEMO screens (not the fake gallery).
/// Compiled in DEBUG only and inert unless launched with capture arguments:
/// `-DemoTrainingAutoEnterDemo` and/or `-DemoTrainingShot=<name>` /
/// `-DemoTrainingTour=<tour>` (`-DemoTrainingStep=<index>`). Ordinary launches never depend on it.
enum DemoTrainingCaptureDriver {
    enum Shot: String {
        case entry
        case menu
        case step1
        case dashboard
        case scrollBelow
        case stagesVisible
        case finish
    }

    static var requestedShot: Shot? {
        let prefix = "-DemoTrainingShot="
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count) else { return nil }
        return Shot(rawValue: String(raw))
    }

    static var requestedTour: DemoTrainingTourID? {
        let prefix = "-DemoTrainingTour="
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count) else { return nil }
        return DemoTrainingTourID(rawValue: String(raw))
    }

    static var requestedStepIndex: Int {
        let prefix = "-DemoTrainingStep="
        guard let raw = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count), let value = Int(raw) else { return 0 }
        return max(0, value)
    }

    static var shouldAutoEnterDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("-DemoTrainingAutoEnterDemo")
    }

    @MainActor
    static func runIfNeeded(store: AppStore) async {
        guard shouldAutoEnterDemo || requestedShot != nil || requestedTour != nil else { return }
        // Wait for bootstrap to finish first. Early enterDemoMode() raced StoreKit and
        // was wiped by bootstrap's demo branch («Нет проектов»).
        if shouldAutoEnterDemo {
            for _ in 0..<50 where !store.isMainDataReady {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        if shouldAutoEnterDemo, !store.isDemoMode {
            store.enterDemoMode()
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        // Ensure the in-memory DEMO project exists before any dashboard shot / tour arrive.
        if store.isDemoMode {
            for _ in 0..<25 where store.projects.isEmpty || store.sessionDemoProjectID == nil {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
        guard store.isDemoMode else { return }
        let training = DemoTrainingController.shared

        if let tour = requestedTour {
            training.dismissMenu()
            training.startTour(tour)
            let index = min(requestedStepIndex, max(0, training.steps.count - 1))
            training.debugJumpToStep(index)
            training.pendingArrive = training.steps[index].arriveAction
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            // `-DemoTrainingAutoPlay`: press «Далее» through to «Завершить» (navigation smoke test).
            if ProcessInfo.processInfo.arguments.contains("-DemoTrainingAutoPlay") {
                while training.activeTour != nil {
                    training.next()
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                }
            }
            return
        }

        guard let shot = requestedShot else { return }

        switch shot {
        case .entry:
            training.dismissMenu()
            training.exitTour()
            store.setSelectedTab(.projects)

        case .menu:
            training.exitTour()
            store.setSelectedTab(.projects)
            training.openMenu()

        case .step1:
            store.setSelectedTab(.projects)
            training.startTour(.projects)
            training.debugJumpToStep(0)

        case .dashboard:
            store.setSelectedTab(.projects)
            training.startTour(.projects)
            training.debugJumpToStep(2)
            training.pendingArrive = .openDemoProjectDashboard
            try? await Task.sleep(nanoseconds: 1_800_000_000)

        case .scrollBelow:
            store.setSelectedTab(.projects)
            training.startTour(.projects)
            training.debugJumpToStep(3)
            training.pendingArrive = .openDemoProjectDashboard
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            // Pin to top so the stages target stays mostly below the fold.
            topScrollView()?.setContentOffset(.zero, animated: false)
            try? await Task.sleep(nanoseconds: 300_000_000)

        case .stagesVisible:
            store.setSelectedTab(.projects)
            training.startTour(.projects)
            training.debugJumpToStep(3)
            training.pendingArrive = .openDemoProjectDashboard
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            scrollUntilAnchorVisible(.projectsDashboardStages)
            try? await Task.sleep(nanoseconds: 350_000_000)

        case .finish:
            store.setSelectedTab(.projects)
            training.startTour(.projects)
            training.debugJumpToStep(4)
            training.pendingArrive = .openDemoProjectDashboard
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            scrollUntilAnchorVisible(.projectsQuickActions)
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    private static func scrollUntilAnchorVisible(_ id: DemoTrainingAnchorID) {
        guard let scroll = topScrollView() else { return }
        let training = DemoTrainingController.shared
        for _ in 0..<12 {
            guard let rect = training.anchorFrames[id], rect.height > 1 else {
                scroll.setContentOffset(
                    CGPoint(x: 0, y: min(scroll.contentOffset.y + 180, maxY(scroll))),
                    animated: false
                )
                RunLoop.main.run(until: Date().addingTimeInterval(0.05))
                continue
            }
            let visible = scroll.convert(scroll.bounds, to: nil)
            let insetVisible = visible.insetBy(dx: 0, dy: 80)
            if insetVisible.contains(CGPoint(x: rect.midX, y: rect.midY))
                || rect.intersection(insetVisible).height >= min(rect.height * 0.7, 120) {
                return
            }
            if rect.midY > insetVisible.maxY {
                scroll.setContentOffset(
                    CGPoint(x: 0, y: min(scroll.contentOffset.y + 160, maxY(scroll))),
                    animated: false
                )
            } else if rect.midY < insetVisible.minY {
                scroll.setContentOffset(
                    CGPoint(x: 0, y: max(scroll.contentOffset.y - 160, -scroll.adjustedContentInset.top)),
                    animated: false
                )
            } else {
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func maxY(_ scroll: UIScrollView) -> CGFloat {
        max(-scroll.adjustedContentInset.top,
            scroll.contentSize.height + scroll.adjustedContentInset.bottom - scroll.bounds.height)
    }

    private static func topScrollView() -> UIScrollView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        guard let root = window?.rootViewController?.view else { return nil }
        var found: [UIScrollView] = []
        collect(root, into: &found)
        return found
            .filter { $0.bounds.height > 100 && $0.contentSize.height > $0.bounds.height + 40 }
            .sorted { $0.contentSize.height > $1.contentSize.height }
            .first
    }

    private static func collect(_ view: UIView, into result: inout [UIScrollView]) {
        if let scroll = view as? UIScrollView, !(scroll is UITextView) {
            result.append(scroll)
        }
        for child in view.subviews {
            collect(child, into: &result)
        }
    }
}
#endif
