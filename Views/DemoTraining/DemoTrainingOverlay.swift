import SwiftUI
import UIKit

/// Spotlight + coach card for DEMO training. Does not resize underlying lists.
/// `surface` selects which overlay draws: the root one, or the one inside a presented sheet.
struct DemoTrainingOverlay: View {
    var surface: DemoTrainingSurface = .root

    @ObservedObject private var training = DemoTrainingController.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var cardSize: CGSize = CGSize(width: 300, height: 140)
    /// Measured title row (lightbulb + title + close).
    @State private var headerChromeHeight: CGFloat = 44
    /// Measured counter + buttons block.
    @State private var controlsChromeHeight: CGFloat = 52

    /// Accessibility / very large typography needs nearly full width and a stacked footer.
    private var prefersExpandedCard: Bool {
        dynamicTypeSize.isAccessibilitySize || dynamicTypeSize >= .xxxLarge
    }

    /// Title + controls + card paddings + VStack spacings (no approximate constant).
    private var measuredChromeOutsideBody: CGFloat {
        let verticalPadding: CGFloat = 8 + 12
        let sectionSpacing: CGFloat = 8 + 8
        return max(44, headerChromeHeight) + max(44, controlsChromeHeight) + verticalPadding + sectionSpacing
    }

    /// Bottom band left untouched by the touch blocker so the tab bar can still end the tour.
    private func tabBarBand(safe: EdgeInsets) -> CGFloat {
        guard surface == .root, training.leavesTabBarHittable else { return 0 }
        return max(safe.bottom, 0) + 56
    }

    var body: some View {
        if training.currentSurface == surface {
            overlayBody
        }
    }

    private var overlayBody: some View {
        GeometryReader { proxy in
            let bounds = proxy.frame(in: .global)
            // The overlay ignores the safe area, which can zero the proxy insets; the root
            // overlay spans the window, so fall back to the window's real insets (island / home bar).
            let window = surface == .root ? DemoTrainingWindowInsets.current : .zero
            let safe = EdgeInsets(
                top: max(proxy.safeAreaInsets.top, window.top),
                leading: max(proxy.safeAreaInsets.leading, window.left),
                bottom: max(proxy.safeAreaInsets.bottom, window.bottom),
                trailing: max(proxy.safeAreaInsets.trailing, window.right)
            )
            let scrolling = training.scrollHint == .scrollDown || training.scrollHint == .scrollUp
            ZStack(alignment: .topLeading) {
                if training.activeTour != nil {
                    dimAndSpotlight(in: bounds)

                    let band = tabBarBand(safe: safe)
                    if scrolling {
                        DemoTrainingScrollPassView(isEnabled: true)
                            .frame(width: bounds.width, height: max(0, bounds.height - band))
                            .frame(width: bounds.width, height: bounds.height, alignment: .top)
                            .ignoresSafeArea()
                        scrollHintBadge(in: bounds, safe: safe)
                        floatingExit(in: bounds, safe: safe)
                    } else {
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(width: bounds.width, height: max(0, bounds.height - band))
                            .frame(width: bounds.width, height: bounds.height, alignment: .top)
                            .ignoresSafeArea()
                            .accessibilityHidden(true)
                        scrollOrCard(in: bounds, safe: safe)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear {
                training.updateVisibleBounds(bounds, safeInsets: safe, surface: surface)
            }
            .onChange(of: proxy.size) { _, _ in
                training.updateVisibleBounds(proxy.frame(in: .global), safeInsets: safe, surface: surface)
            }
            .onChange(of: training.stepIndex) { _, _ in
                training.updateVisibleBounds(proxy.frame(in: .global), safeInsets: safe, surface: surface)
            }
            .onChange(of: training.anchorFrames) { _, _ in
                training.updateVisibleBounds(proxy.frame(in: .global), safeInsets: safe, surface: surface)
            }
            .onChange(of: training.currentSurface) { _, _ in
                training.updateVisibleBounds(proxy.frame(in: .global), safeInsets: safe, surface: surface)
            }
        }
        .allowsHitTesting(training.activeTour != nil)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func dimAndSpotlight(in bounds: CGRect) -> some View {
        let hole = training.highlightedRect
        Canvas { context, size in
            var path = Path(CGRect(origin: .zero, size: size))
            if let hole {
                let local = CGRect(
                    x: hole.minX - bounds.minX,
                    y: hole.minY - bounds.minY,
                    width: hole.width,
                    height: hole.height
                )
                path.addRoundedRect(in: local, cornerSize: CGSize(width: 12, height: 12))
            }
            context.fill(
                path,
                with: .color(.black.opacity(colorScheme == .dark ? 0.58 : 0.42)),
                style: FillStyle(eoFill: true)
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hole?.integral)
    }

    @ViewBuilder
    private func scrollOrCard(in bounds: CGRect, safe: EdgeInsets) -> some View {
        switch training.scrollHint {
        case .scrollDown, .scrollUp:
            EmptyView()
        case .missingTarget:
            missingTargetChrome(in: bounds, safe: safe)
        case .none:
            if let step = training.currentStep {
                positionedCoach(step: step, in: bounds, safe: safe)
            }
        }
    }

    private func scrollHintBadge(in bounds: CGRect, safe: EdgeInsets) -> some View {
        let text = training.scrollHint == .scrollUp ? "Листайте выше" : "Листайте ниже"
        let icon = training.scrollHint == .scrollUp ? "chevron.up" : "chevron.down"
        return VStack {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                Text(text)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(ProjectUXColors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(text). \(training.stepCounterText)")
            .accessibilityIdentifier("demo.training.scrollHint")
            .padding(.bottom, max(safe.bottom, 12) + 56)
        }
        .frame(width: bounds.width, height: bounds.height)
        .allowsHitTesting(false)
    }

    private func floatingExit(in bounds: CGRect, safe: EdgeInsets) -> some View {
        VStack {
            HStack {
                Spacer()
                exitButton
                    .padding(.trailing, 12)
                    .padding(.top, max(safe.top, 8) + 4)
            }
            Spacer()
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func missingTargetChrome(in bounds: CGRect, safe: EdgeInsets) -> some View {
        VStack {
            HStack {
                Spacer()
                exitButton
                    .padding(.trailing, 12)
                    .padding(.top, max(safe.top, 8) + 4)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("Элемент сейчас недоступен")
                    .font(.headline)
                    .foregroundStyle(ProjectUXColors.primaryText)
                Text("Откройте нужный экран вручную или пропустите этот шаг.")
                    .font(.subheadline)
                    .foregroundStyle(ProjectUXColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    if training.skipMissingStepAvailable {
                        Button("Пропустить шаг") { training.skipMissingStep() }
                            .buttonStyle(DemoTrainingPrimaryButtonStyle())
                            .accessibilityIdentifier("demo.training.skipMissing")
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(14)
            .frame(maxWidth: min(340, bounds.width - 32), alignment: .leading)
            .background(ProjectUXColors.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.bottom, max(safe.bottom, 12) + 24)
            Spacer().frame(height: 8)
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    private func positionedCoach(step: DemoTrainingStep, in bounds: CGRect, safe: EdgeInsets) -> some View {
        let target = training.highlightedRect.map {
            CGRect(x: $0.minX - bounds.minX, y: $0.minY - bounds.minY, width: $0.width, height: $0.height)
        }
        // Clear only the highlighted target (full summary or progress focus). When focus
        // is active, the card sits just outside progress+bar so it fits on SE + XXXL;
        // dimmed dates may remain above the card but are not in the spotlight.

        let placement = DemoTrainingCardPlacement.make(
            target: target,
            occupied: target,
            cardSize: cardSize,
            canvasSize: bounds.size,
            safe: safe,
            expandedWidth: prefersExpandedCard,
            chromeOutsideBody: measuredChromeOutsideBody,
            // Photo viewer: prefer the band under the snapshot (metadata / letterbox)
            // so the coach does not cover the picture; pointer aims up at the lit image.
            preferBelow: step.anchor == .photosViewer
        )

        return ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                if placement.pointerOnTop {
                    cardBody(step: step, maxBodyHeight: placement.maxBodyHeight)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { updateCardSize($0) }
                    pointerRow(pointsUp: false, leadingInset: placement.pointerLeadingInset, width: placement.cardWidth)
                } else {
                    pointerRow(pointsUp: true, leadingInset: placement.pointerLeadingInset, width: placement.cardWidth)
                    cardBody(step: step, maxBodyHeight: placement.maxBodyHeight)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { updateCardSize($0) }
                }
            }
            // Intrinsic height only — ZStack proposes the full canvas; without fixedSize the
            // card stack stretched to fill it (huge empty band inside the coach card).
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: placement.cardWidth, alignment: .leading)
            .offset(x: placement.origin.x, y: placement.origin.y)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step.id)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: target?.integral)
            .transition(reduceMotion ? .opacity : .opacity)
        }
        .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }

    private func updateCardSize(_ newSize: CGSize) {
        if abs(newSize.width - cardSize.width) > 0.5 || abs(newSize.height - cardSize.height) > 0.5 {
            cardSize = newSize
        }
        // Pointer row is 10pt; controller uses this to choose full vs progress focus.
        training.updateCoachStackHeight(newSize.height + 10)
    }

    private func cardBody(step: DemoTrainingStep, maxBodyHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.accentAction)
                    .accessibilityHidden(true)
                    .padding(.top, 2)

                Text(step.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ProjectUXColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: training.exitTour) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(ProjectUXColors.secondaryText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть обучение")
                .accessibilityIdentifier("demo.training.exit")
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                if abs(height - headerChromeHeight) > 0.5 {
                    headerChromeHeight = height
                }
            }

            DemoTrainingExplanationBlock(text: step.body, maxHeight: maxBodyHeight)

            cardControls()
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    if abs(height - controlsChromeHeight) > 0.5 {
                        controlsChromeHeight = height
                    }
                }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(ProjectUXColors.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(ProjectUXColors.readableBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.16), radius: 10, y: 3)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func cardControls() -> some View {
        let counter = Text(training.stepCounterText)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ProjectUXColors.secondaryText)
            .accessibilityLabel("Шаг \(training.stepCounterText)")

        if prefersExpandedCard {
            VStack(alignment: .leading, spacing: 10) {
                counter
                if training.canGoBack {
                    Button("Назад") { training.back() }
                        .buttonStyle(DemoTrainingSecondaryButtonStyle(fillsWidth: true))
                        .accessibilityIdentifier("demo.training.back")
                }
                Button(training.isLastStep ? "Завершить" : "Далее") { training.next() }
                    .buttonStyle(DemoTrainingPrimaryButtonStyle(fillsWidth: true))
                    .accessibilityIdentifier(training.isLastStep ? "demo.training.finish" : "demo.training.next")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    counter
                    Spacer(minLength: 8)
                    if training.canGoBack {
                        Button("Назад") { training.back() }
                            .buttonStyle(DemoTrainingSecondaryButtonStyle())
                            .accessibilityIdentifier("demo.training.back")
                    }
                    Button(training.isLastStep ? "Завершить" : "Далее") { training.next() }
                        .buttonStyle(DemoTrainingPrimaryButtonStyle())
                        .accessibilityIdentifier(training.isLastStep ? "demo.training.finish" : "demo.training.next")
                }

                VStack(alignment: .leading, spacing: 10) {
                    counter
                    if training.canGoBack {
                        Button("Назад") { training.back() }
                            .buttonStyle(DemoTrainingSecondaryButtonStyle(fillsWidth: true))
                            .accessibilityIdentifier("demo.training.back")
                    }
                    Button(training.isLastStep ? "Завершить" : "Далее") { training.next() }
                        .buttonStyle(DemoTrainingPrimaryButtonStyle(fillsWidth: true))
                        .accessibilityIdentifier(training.isLastStep ? "demo.training.finish" : "demo.training.next")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var exitButton: some View {
        Button(action: training.exitTour) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(ProjectUXColors.primaryText)
                .frame(width: 44, height: 44)
                .background(ProjectUXColors.cardSurface.opacity(0.95), in: Circle())
                .contentShape(Circle())
                .shadow(color: .black.opacity(0.14), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Закрыть обучение")
        .accessibilityIdentifier("demo.training.exit")
    }

    /// Places the pointer in the same leading-edge coordinate system as `pointerLeadingInset`.
    private func pointerRow(pointsUp: Bool, leadingInset: CGFloat, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: max(0, leadingInset), height: 10)
            pointer(pointsUp: pointsUp)
            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
    }

    private func pointer(pointsUp: Bool) -> some View {
        let name = pointsUp ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill"
        return Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(ProjectUXColors.cardSurface)
            // Keep a readable edge on the dimmed scrim (especially dark mode).
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.18), radius: 1.5, y: 1)
            .overlay {
                Image(systemName: name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ProjectUXColors.readableBorder.opacity(colorScheme == .dark ? 0.9 : 0.55))
                    .scaleEffect(1.12)
                    .opacity(0.9)
            }
            .frame(width: 18, height: 10)
            .accessibilityHidden(true)
    }
}

/// Real device insets of the key window (status bar / Dynamic Island, home indicator).
enum DemoTrainingWindowInsets {
    static var current: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.safeAreaInsets ?? .zero
    }
}

// MARK: - Explanation (intrinsic height; scroll only when over ceiling)

/// Short copy keeps natural height. Long copy scrolls inside an exact height ceiling —
/// never `frame(maxHeight:)` alone on ScrollView (that stretched short cards).
private struct DemoTrainingExplanationBlock: View {
    let text: String
    let maxHeight: CGFloat

    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        let ceiling = max(56, maxHeight)
        let label = Text(text)
            .font(.footnote)
            .foregroundStyle(ProjectUXColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)

        Group {
            if naturalHeight > ceiling + 1 {
                ScrollView(.vertical, showsIndicators: true) {
                    label
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: ceiling)
            } else {
                label
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard height > 0, abs(height - naturalHeight) > 0.5 else { return }
                        naturalHeight = height
                    }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: text) { _, _ in
            naturalHeight = 0
        }
        .onChange(of: maxHeight) { _, _ in
            // Re-evaluate scroll vs intrinsic when the ceiling changes (chrome measured).
        }
    }
}

// MARK: - Placement

enum DemoTrainingCardPlacement {
    struct Result {
        var origin: CGPoint
        var cardWidth: CGFloat
        var pointerOnTop: Bool
        /// Distance from the card's leading edge to the pointer's leading edge (same space as the HStack inset).
        var pointerLeadingInset: CGFloat
        /// Cap for the explanation block so chrome (title, controls, exit) stays on-screen.
        var maxBodyHeight: CGFloat
    }

    private static let pointerWidth: CGFloat = 18

    static func make(
        target: CGRect?,
        occupied: CGRect? = nil,
        cardSize: CGSize,
        canvasSize: CGSize,
        safe: EdgeInsets,
        expandedWidth: Bool,
        chromeOutsideBody: CGFloat,
        preferBelow: Bool = false
    ) -> Result {
        let margin: CGFloat = 12
        // Slightly larger gap on expanded/XXXL so the pointer sits clear of the lit focus edge.
        let gap: CGFloat = expandedWidth ? 14 : 10
        let pointerH: CGFloat = 10
        let chrome = max(96, chromeOutsideBody)
        let maxCardWidth = expandedWidth
            ? max(240, canvasSize.width - margin * 2)
            : min(300, max(220, canvasSize.width - margin * 2))
        let preferredWidth = expandedWidth
            ? maxCardWidth
            : min(max(cardSize.width > 1 ? cardSize.width : 280, 240), maxCardWidth)
        let width = min(preferredWidth, maxCardWidth)
        // Prefer measured height; fall back to a compact estimate so the first frame stays near the target.
        let height = cardSize.height > 1 ? cardSize.height : (expandedWidth ? 200 : 118)
        let stackHeight = height + pointerH

        let topLimit = max(safe.top, 12) + 6
        // Home-indicator / safe clearance only — do not reserve a phantom tab-bar band
        // (pushed dashboard has no tabs; the old 58pt reserve shoved the card into the target).
        let usableBottom = canvasSize.height - max(safe.bottom, 8) - 10

        guard let target, target.width > 1, target.height > 1 else {
            let x = (canvasSize.width - width) / 2
            var y = max(topLimit, min((canvasSize.height - stackHeight) / 2, usableBottom - stackHeight))
            y = min(max(y, topLimit), max(topLimit, usableBottom - stackHeight))
            let roomForCard = max(0, usableBottom - y)
            let room = max(56, roomForCard - pointerH - chrome)
            return Result(
                origin: CGPoint(x: x, y: y),
                cardWidth: width,
                pointerOnTop: true,
                pointerLeadingInset: (width - pointerWidth) / 2,
                maxBodyHeight: room
            )
        }

        // Clear the occupied band (full summary) while aiming the pointer at `target` (focus or full).
        let block = (occupied?.width ?? 0) > 1 ? occupied!.union(target) : target
        let spaceAbove = block.minY - topLimit
        let spaceBelow = usableBottom - block.maxY
        // Minimum stack that must stay on-screen: chrome + min body + pointer.
        let minStack = chrome + 56 + pointerH
        let needed = max(stackHeight, minStack) + gap

        // Prefer the side with room that keeps the card adjacent to the cleared band.
        // For photo viewer, sit under the snapshot whenever a compact card fits there —
        // compress the body instead of covering the picture.
        let placeBelow: Bool = {
            if preferBelow {
                if spaceBelow >= minStack { return true }
                if spaceAbove >= needed { return false }
                return spaceBelow >= spaceAbove
            }
            if spaceBelow >= needed { return true }
            if spaceAbove >= needed { return false }
            return spaceBelow >= spaceAbove
        }()

        let y: CGFloat
        let pointerOnTop: Bool
        let roomForCard: CGFloat
        if placeBelow {
            // Stay strictly below the occupied band; pointer sits on top of the card and aims up.
            // Never climb onto the snapshot — if the stack is taller than the free band,
            // compress the body (`maxBodyHeight`) instead of overlapping the photo.
            y = block.maxY + gap
            pointerOnTop = false
            roomForCard = max(0, usableBottom - y)
        } else {
            // Stay strictly above the occupied band.
            roomForCard = max(0, block.minY - gap - topLimit)
            let idealY = block.minY - gap - min(stackHeight, max(roomForCard, minStack))
            y = max(topLimit, idealY)
            pointerOnTop = true
        }

        var x = target.midX - width / 2
        x = min(max(x, margin), canvasSize.width - margin - width)

        // Aim the pointer at the highlighted target center (progress focus), not the cleared band mid.
        let idealLeading = target.midX - x - pointerWidth / 2
        let pointerLeading = min(max(idealLeading, 12), width - pointerWidth - 12)

        // Cap body so chrome + buttons fit in the room outside the occupied band.
        let maxBody = max(56, roomForCard - pointerH - chrome)

        return Result(
            origin: CGPoint(x: x, y: y),
            cardWidth: width,
            pointerOnTop: pointerOnTop,
            pointerLeadingInset: pointerLeading,
            maxBodyHeight: maxBody
        )
    }
}

struct DemoTrainingPrimaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ProjectUXColors.onAccent)
            .lineLimit(1)
            .minimumScaleFactor(1)
            .padding(.horizontal, 16)

        Group {
            if fillsWidth {
                label
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                label
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .background(ProjectUXColors.accentAction, in: Capsule())
        .contentShape(Capsule())
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct DemoTrainingSecondaryButtonStyle: ButtonStyle {
    var fillsWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(ProjectUXColors.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(1)
            .padding(.horizontal, 14)

        Group {
            if fillsWidth {
                label
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                label
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
            }
        }
        .background(ProjectUXColors.secondarySurface, in: Capsule())
        .contentShape(Capsule())
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}
