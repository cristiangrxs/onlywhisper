import AppKit
import SwiftUI

/// Gap between the menu-bar regions on either side of a camera housing.
struct NotchMetrics: Equatable {
    var width: CGFloat
    var midX: CGFloat
    var band: CGFloat

    /// Width of the housing. Gaps of 20 pt or less are not a notch.
    static func notchWidth(leftMaxX: CGFloat, rightMinX: CGFloat) -> CGFloat? {
        let width = rightMinX - leftMaxX
        guard width > 20 else { return nil }
        return width
    }

    /// Height of the menu-bar band the housing sits in. Falls back when that bar is hidden.
    static func menuBarBand(screenMaxY: CGFloat, visibleMaxY: CGFloat, safeAreaTop: CGFloat) -> CGFloat {
        let band = screenMaxY - visibleMaxY
        if band > 1 { return band }
        if safeAreaTop > 1 { return safeAreaTop }
        return 32
    }

    static func measure(
        left: CGRect?,
        right: CGRect?,
        screenFrame: CGRect,
        visibleFrame: CGRect,
        safeAreaTop: CGFloat
    ) -> NotchMetrics? {
        guard let left, let right, let width = notchWidth(leftMaxX: left.maxX, rightMinX: right.minX) else {
            return nil
        }
        let rawMid = (left.maxX + right.minX) / 2
        let midX = (screenFrame.minX...screenFrame.maxX).contains(rawMid) ? rawMid : screenFrame.midX
        let band = menuBarBand(
            screenMaxY: screenFrame.maxY,
            visibleMaxY: visibleFrame.maxY,
            safeAreaTop: safeAreaTop
        )
        return NotchMetrics(width: width, midX: midX, band: band)
    }

    /// Only the built-in display can host the island. An external screen uses the bottom capsule.
    static func usesNotch(isBuiltIn: Bool, metrics: NotchMetrics?) -> Bool {
        isBuiltIn && metrics != nil
    }
}

extension NSScreen {
    /// Camera housing on this Mac's built-in display. External screens return nil.
    var notchMetrics: NotchMetrics? {
        let metrics = NotchMetrics.measure(
            left: auxiliaryTopLeftArea,
            right: auxiliaryTopRightArea,
            screenFrame: frame,
            visibleFrame: visibleFrame,
            safeAreaTop: safeAreaInsets.top
        )
        guard NotchMetrics.usesNotch(isBuiltIn: isBuiltIn, metrics: metrics) else { return nil }
        return metrics
    }

    var isBuiltIn: Bool {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(CGDirectDisplayID(number.uint32Value)) != 0
    }
}

@MainActor
@Observable
final class OverlayPlacement {
    enum Anchor: Equatable {
        case notch(width: CGFloat, band: CGFloat)
        case bottom
    }

    var anchor: Anchor = .bottom
    /// Drives the open and close motion. False is the resting, hidden shape.
    var expanded = false
    /// The capsule, including its chrome, stays within this height. About 70% of the screen.
    var maxHeight: CGFloat = 640
}

@MainActor
final class OverlayPanel {
    static let shared = OverlayPanel()

    private var panel: NSPanel?
    private let placement = OverlayPlacement()
    private var generation = 0

    func show() {
        let panel = ensurePanel()
        guard let screen = screenUnderPointer() else { return }
        let room = Self.panelSize(on: screen)
        if panel.isVisible, placement.expanded { return }

        generation += 1
        let token = generation
        if let notch = screen.notchMetrics {
            placement.anchor = .notch(width: notch.width, band: notch.band)
            placement.maxHeight = room.height
            panel.level = .statusBar
            let origin = NSPoint(
                x: notch.midX - room.width / 2,
                y: screen.frame.maxY - room.height
            )
            panel.setFrame(NSRect(origin: origin, size: room), display: true)
        } else {
            placement.anchor = .bottom
            panel.level = .floating
            let visible = screen.visibleFrame
            let height = min(room.height, visible.height)
            placement.maxHeight = height
            let origin = NSPoint(
                x: visible.midX - room.width / 2,
                y: visible.minY
            )
            panel.setFrame(NSRect(origin: origin, size: NSSize(width: room.width, height: height)), display: true)
        }
        placement.expanded = false
        panel.orderFrontRegardless()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
            guard token == self.generation else { return }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : IslandMotion.spring) {
                self.placement.expanded = true
            }
        }
    }

    func hide() {
        generation += 1
        let token = generation
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? .easeOut(duration: 0.12) : IslandMotion.spring) {
            placement.expanded = false
        }
        let delay: Duration = reduceMotion ? .milliseconds(160) : IslandMotion.settle
        Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard token == self.generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    /// Tall enough for the transcript to grow, and no taller than about 70% of the screen.
    private static func panelSize(on screen: NSScreen) -> NSSize {
        NSSize(
            width: min(screen.frame.width - 48, 680),
            height: screen.frame.height * 0.7
        )
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let view = NSHostingView(
            rootView: RecordingOverlay()
                .environment(AppModel.shared)
                .environment(placement)
        )
        view.sizingOptions = .standardBounds
        view.autoresizingMask = [.width, .height]
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 440, height: 160)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        // The capsule draws its own shadow, a window shadow would not follow its changing width.
        panel.hasShadow = false
        panel.contentView = view
        self.panel = panel
        return panel
    }

    private func screenUnderPointer() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

struct RecordingOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(OverlayPlacement.self) private var placement
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var contentSize: CGSize = CGSize(width: 220, height: 44)
    @State private var contentVisible = false
    @State private var shownMode: CapsuleMode = .listening
    @State private var rowOpacity: Double = 1
    @State private var morphToken = 0
    @State private var shownSize: CGSize = CGSize(width: 220, height: 44)
    @State private var listeningSize: CGSize = .zero
    @State private var polishingSize: CGSize = .zero
    @State private var insertedSize: CGSize = .zero
    @State private var hintSize: CGSize = .zero

    var body: some View {
        Group {
            switch placement.anchor {
            case .notch(let width, let band):
                notchIsland(notchWidth: width, band: band)
            case .bottom:
                bottomCapsule
            }
        }
        .onChange(of: placement.expanded) { _, expanded in
            let animation: Animation = reduceMotion
                ? .easeOut(duration: 0.12)
                : (expanded ? .spring(duration: 0.38, bounce: 0.1).delay(0.05) : .easeIn(duration: 0.1))
            withAnimation(animation) {
                contentVisible = expanded
            }
        }
    }

    private var bottomCapsule: some View {
        let shown = placement.expanded
        return capsuleBody
            .fixedSize(horizontal: true, vertical: true)
            .glassPanel(cornerRadius: 22)
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            .scaleEffect(reduceMotion || shown ? 1 : 0.94, anchor: .bottom)
            .offset(y: reduceMotion || shown ? 0 : 8)
            .opacity(shown ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : IslandMotion.spring, value: placement.expanded)
            .animation(reduceMotion ? nil : IslandMotion.grow, value: model.livePreview)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Black card flush with the top of the screen. Content starts below the menu bar so the housing cannot cover it.
    private func notchIsland(notchWidth: CGFloat, band: CGFloat) -> some View {
        let opened = reduceMotion || placement.expanded
        // Short states stay a little wider than the housing, the same shoulder as the listening row.
        let openShell = CGSize(
            width: min(560, max(contentSize.width + 80, notchWidth + 96)),
            height: band + contentSize.height + 12
        )
        let shell = opened ? openShell : CGSize(width: notchWidth, height: band)
        let openRadii = IslandShape.radii(for: openShell)
        let outline = IslandShape(
            topRadius: opened ? openRadii.top : 0,
            bottomRadius: opened ? openRadii.bottom : IslandShape.closedBottomRadius
        )

        return outline
            .fill(Color.black)
            .frame(width: shell.width, height: shell.height)
            .overlay(alignment: .top) {
                capsuleBody
                    .fixedSize()
                    .padding(.top, band)
                    .opacity(contentVisible ? 1 : 0)
            }
            .clipShape(outline)
            .shadow(
                color: .black.opacity(placement.expanded ? 0.32 : 0),
                radius: placement.expanded ? 16 : 0,
                y: placement.expanded ? 8 : 0
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }

    /// Listening, polishing, and inserted share one frame. The old row fades out before the new one fades in, so the words never sit on top of each other.
    private var capsuleBody: some View {
        Group {
            switch shownMode {
            case .listening:
                listeningBlock
            case .polishing:
                polishingBlock
            case .inserted:
                insertedCapsule
            case .hint(let hint):
                hintCapsule(hint)
            }
        }
        .fixedSize()
        .opacity(rowOpacity)
        .frame(width: shownSize.width, height: shownSize.height, alignment: .center)
        .clipped()
        .background {
            ZStack {
                listeningBlock.fixedSize().onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { listeningSize = $0 }.hidden()
                polishingBlock.fixedSize().onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { polishingSize = $0 }.hidden()
                insertedCapsule.fixedSize().onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { insertedSize = $0 }.hidden()
                if let hint = model.overlayHint {
                    hintCapsule(hint).fixedSize().onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { hintSize = $0 }.hidden()
                }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: desiredMode) { _, newMode in
            morph(to: newMode)
        }
        .onChange(of: listeningSize) { _, newSize in
            guard desiredMode == .listening else { return }
            adopt(newSize)
        }
        .onChange(of: polishingSize) { _, newSize in
            guard desiredMode == .polishing else { return }
            adopt(newSize)
        }
        .onChange(of: insertedSize) { _, newSize in
            guard desiredMode == .inserted else { return }
            adopt(newSize)
        }
        .onChange(of: hintSize) { _, newSize in
            guard shownMode == desiredMode else { return }
            if case .hint = shownMode { adopt(newSize) }
        }
        .onChange(of: placement.expanded) { _, expanded in
            guard expanded else {
                morphToken += 1
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    shownMode = .listening
                    rowOpacity = 1
                }
                return
            }
            let next = measuredSize(for: desiredMode)
            guard next.width > 1 else { return }
            shownMode = desiredMode
            rowOpacity = 1
            shownSize = next
            contentSize = next
        }
    }

    private var desiredMode: CapsuleMode {
        if let hint = model.overlayHint, model.phase == .idle {
            return .hint(hint)
        }
        if model.dictationInserted, model.phase == .idle {
            return .inserted
        }
        if model.isSmoothing || isWorking {
            return .polishing
        }
        return .listening
    }

    private var isWorking: Bool {
        if case .working = model.phase { return true }
        return false
    }

    private func measuredSize(for mode: CapsuleMode) -> CGSize {
        switch mode {
        case .listening: listeningSize
        case .polishing: polishingSize
        case .inserted: insertedSize
        case .hint: hintSize
        }
    }

    /// Fades the current row out, eases the capsule, then fades the next row in.
    private func morph(to newMode: CapsuleMode) {
        guard newMode != shownMode else { return }
        morphToken += 1
        let token = morphToken
        let next = measuredSize(for: newMode)
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.12)) {
                shownMode = newMode
                rowOpacity = 1
                applySize(next)
            }
            return
        }
        withAnimation(.easeOut(duration: 0.14)) {
            rowOpacity = 0
        }
        withAnimation(IslandMotion.morph.delay(0.12)) {
            applySize(next)
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            guard token == morphToken else { return }
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) { shownMode = newMode }
            withAnimation(.easeIn(duration: 0.24)) {
                rowOpacity = 1
            }
        }
    }

    private func applySize(_ size: CGSize) {
        guard placement.expanded, size.width > 1, size.height > 1 else { return }
        shownSize = size
        contentSize = size
    }

    /// Follows the transcript while listening, without restarting the close spring.
    private func adopt(_ size: CGSize) {
        guard placement.expanded, size.width > 1, size.height > 1 else { return }
        guard abs(size.width - shownSize.width) > 0.5 || abs(size.height - shownSize.height) > 0.5 else { return }
        withAnimation(morphAnimation) {
            shownSize = size
            contentSize = size
        }
    }

    private var morphAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : IslandMotion.morph
    }

    private var insertedCapsule: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.green)
            Text(t("Inserted", "Eingefügt"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(t("Inserted", "Eingefügt"))
    }

    private func hintCapsule(_ hint: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "selection.pin.in.out")
                .font(.system(size: 13, weight: .semibold))
            Text(hint)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(hint)
    }

    private var listeningBlock: some View {
        VStack(alignment: .center, spacing: 4) {
            listeningRow
                .frame(height: 44)
            if !model.livePreview.isEmpty {
                LiveTranscript(
                    text: model.livePreview,
                    maxWidth: 400,
                    maxLines: transcriptLineLimit
                )
                .padding(.bottom, 10)
            }
        }
        .padding(.horizontal, 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var polishingBlock: some View {
        polishingRow
            .padding(.horizontal, 14)
            .frame(height: 44)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(t("Polishing…", "Poliert…"))
    }

    /// Lines that fit before the capsule would pass about 70% of the screen. Older words drop off the top.
    private var transcriptLineLimit: Int {
        let chrome: CGFloat
        switch placement.anchor {
        case .notch(_, let band):
            chrome = band + 44 + 28
        case .bottom:
            chrome = 44 + 36
        }
        let available = max(36, placement.maxHeight - chrome)
        return max(2, Int(available / 18))
    }

    private var accessibilityText: String {
        model.livePreview.isEmpty ? listeningTitle : "\(listeningTitle). \(model.livePreview)"
    }

    /// Lavender shared by the sparkle and the label, matching the landing page.
    private static let polishTint = Color(red: 176 / 255, green: 166 / 255, blue: 240 / 255)

    private var polishingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .symbolEffect(.pulse, options: .repeating, isActive: shownMode == .polishing && !reduceMotion)
            Text(t("Polishing…", "Poliert…"))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Self.polishTint)
    }

    private var listeningRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(.red)
                .symbolEffect(.pulse, isActive: shownMode == .listening && !reduceMotion)
            Waveform(level: model.level, animated: shownMode == .listening && !reduceMotion && isListening)
                .frame(width: 52, height: 22)
                .accessibilityHidden(true)
            Text(listeningTitle)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            KeyCap("esc")
        }
    }

    private var isListening: Bool {
        model.phase == .recording || model.phase == .handsFree
    }

    /// Stays on the listening words while that row fades out, so it does not flip to a spinner first.
    private var listeningTitle: String {
        switch model.phase {
        case .handsFree: t("Hands-free", "Freisprechen")
        default: t("Listening", "Hört zu")
        }
    }
}

private enum CapsuleMode: Equatable {
    case listening
    case polishing
    case inserted
    case hint(String)
}

private enum IslandMotion {
    static let spring = Animation.spring(duration: 0.5, bounce: 0.12)
    /// Crossfade between listening, polishing, and inserted. No bounce, so the width does not rebound.
    static let morph = Animation.smooth(duration: 0.46, extraBounce: 0)
    /// Follows new words without the open-and-close bounce.
    static let grow = Animation.spring(duration: 0.32, bounce: 0.04)
    /// Long enough for the spring to settle inside the housing before the window is removed.
    static let settle: Duration = .milliseconds(620)
}

/// Wraps once the line is a little wider than the status row. Past the capsule's height budget, the oldest words drop off the top.
private struct LiveTranscript: View {
    var text: String
    var maxWidth: CGFloat
    var maxLines: Int
    @State private var singleLineWidth: CGFloat = 0

    private var width: CGFloat {
        guard singleLineWidth > 1 else { return 48 }
        return min(singleLineWidth, maxWidth)
    }

    var body: some View {
        Text(text)
            .font(Self.font)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineSpacing(2)
            .lineLimit(maxLines)
            .truncationMode(.head)
            .frame(width: width, alignment: .bottomLeading)
            .background(alignment: .leading) {
                Text(text)
                    .font(Self.font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .accessibilityHidden(true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { singleLineWidth = $0 }
            }
            .accessibilityLabel(text)
    }

    private static let font = Font.system(size: 13)
}

/// Black island joined to the top of the screen.
/// Closed, the sides sit on the notch. Open, the same shoulders grow in with the frame.
struct IslandShape: Shape {
    /// Lower corners while the island is still the notch.
    static let closedBottomRadius: CGFloat = 10

    var topRadius: CGFloat
    var bottomRadius: CGFloat

    /// Shoulders for an open shell. Same curve as before, taken from the open size rather than the in-between frame.
    static func radii(for size: CGSize) -> (top: CGFloat, bottom: CGFloat) {
        let top = min(36, size.width * 0.16, size.height * 0.42)
        let bottom = min(22, size.width * 0.2, max(size.height - top, 1) * 0.72, size.height * 0.34)
        return (top, bottom)
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let tr = max(topRadius, 0)
        let br = min(max(bottomRadius, 0), max(rect.width / 2 - tr, 0), max(rect.height - tr, 0) / 2)
        let left = rect.minX
        let right = rect.maxX
        let top = rect.minY
        let bottom = rect.maxY
        let bodyLeft = left + tr
        let bodyRight = right - tr
        var path = Path()

        path.move(to: CGPoint(x: left, y: top))
        path.addLine(to: CGPoint(x: right, y: top))
        if tr > 0.5 {
            path.addArc(
                center: CGPoint(x: right, y: top + tr),
                radius: tr,
                startAngle: .degrees(-90),
                endAngle: .degrees(180),
                clockwise: true
            )
        }
        path.addLine(to: CGPoint(x: bodyRight, y: bottom - br))
        if br > 0.5 {
            path.addArc(
                center: CGPoint(x: bodyRight - br, y: bottom - br),
                radius: br,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: bodyLeft + br, y: bottom))
            path.addArc(
                center: CGPoint(x: bodyLeft + br, y: bottom - br),
                radius: br,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        } else {
            path.addLine(to: CGPoint(x: bodyRight, y: bottom))
            path.addLine(to: CGPoint(x: bodyLeft, y: bottom))
        }
        path.addLine(to: CGPoint(x: bodyLeft, y: top + tr))
        if tr > 0.5 {
            path.addArc(
                center: CGPoint(x: left, y: top + tr),
                radius: tr,
                startAngle: .degrees(0),
                endAngle: .degrees(-90),
                clockwise: true
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct Waveform: View {
    var level: Float
    var animated: Bool
    private static let weights: [CGFloat] = [0.45, 0.75, 1, 0.85, 0.6, 0.9, 0.5]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .fill(.primary.opacity(0.85))
                    .frame(width: 3, height: height(for: index))
            }
        }
        .animation(animated ? .smooth(duration: 0.12) : nil, value: level)
    }

    private func height(for index: Int) -> CGFloat {
        guard animated else { return 6 }
        let boosted = min(1, CGFloat(level) * 1.6)
        let wobble = 0.75 + 0.25 * abs(sin(Double(index) * 1.7 + Double(level) * 12))
        return 4 + 18 * boosted * Self.weights[index] * CGFloat(wobble)
    }
}
