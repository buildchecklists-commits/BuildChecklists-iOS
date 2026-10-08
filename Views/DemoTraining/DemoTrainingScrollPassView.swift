import SwiftUI
import UIKit

/// Absorbs taps on the dimmed area while forwarding vertical pans to the underlying scroll view.
struct DemoTrainingScrollPassView: UIViewRepresentable {
    var isEnabled: Bool

    func makeUIView(context: Context) -> DemoTrainingScrollPassUIView {
        let view = DemoTrainingScrollPassUIView()
        view.isEnabled = isEnabled
        return view
    }

    func updateUIView(_ uiView: DemoTrainingScrollPassUIView, context: Context) {
        uiView.isEnabled = isEnabled
    }
}

final class DemoTrainingScrollPassUIView: UIView {
    var isEnabled = true {
        didSet { isUserInteractionEnabled = isEnabled }
    }

    private var pan: UIPanGestureRecognizer!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isAccessibilityElement = false
        pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isEnabled, bounds.contains(point) else { return nil }
        // Capture all touches here so dimmed controls do not activate; pans scroll below.
        return self
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard isEnabled, let scrollView = nearestScrollView() else { return }
        let translation = gesture.translation(in: self)
        gesture.setTranslation(.zero, in: self)

        var offset = scrollView.contentOffset
        let minY = -scrollView.adjustedContentInset.top
        let maxY = max(
            minY,
            scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - scrollView.bounds.height
        )
        offset.y = min(max(offset.y - translation.y, minY), maxY)
        scrollView.setContentOffset(offset, animated: false)
    }

    private func nearestScrollView() -> UIScrollView? {
        var responder: UIView? = superview
        var found: [UIScrollView] = []
        while let view = responder {
            collectScrollViews(in: view, into: &found)
            responder = view.superview
        }
        // Prefer the scroll view that currently intersects this overlay.
        let overlayFrame = convert(bounds, to: nil)
        return found
            .filter { $0.window != nil && $0.bounds.height > 0 }
            .sorted { lhs, rhs in
                let l = lhs.convert(lhs.bounds, to: nil).intersection(overlayFrame).height
                let r = rhs.convert(rhs.bounds, to: nil).intersection(overlayFrame).height
                return l > r
            }
            .first
    }

    private func collectScrollViews(in root: UIView, into result: inout [UIScrollView]) {
        if let scroll = root as? UIScrollView, !(scroll is UITextView) {
            result.append(scroll)
        }
        for child in root.subviews {
            collectScrollViews(in: child, into: &result)
        }
    }
}
