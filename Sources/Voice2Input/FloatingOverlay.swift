import AppKit
import SwiftUI

@MainActor
final class FloatingOverlayModel: ObservableObject {
    @Published var isVisible = false
    @Published var text = "开始说话…"
    @Published var textWidth: CGFloat = 160
    @Published var bars: [CGFloat] = [0.16, 0.24, 0.32, 0.24, 0.18]
}

@MainActor
final class FloatingOverlayController {
    private enum Layout {
        static let height: CGFloat = 56
        static let minTextWidth: CGFloat = 160
        static let maxTextWidth: CGFloat = 560
        static let bottomInset: CGFloat = 48
        static let sidePadding: CGFloat = 20
        static let waveformWidth: CGFloat = 44
        static let contentSpacing: CGFloat = 14
        static let panelExtraWidth: CGFloat = sidePadding * 2 + waveformWidth + contentSpacing
    }

    private let model = FloatingOverlayModel()
    private lazy var panel = makePanel()

    func show(text: String) {
        update(text: text, animated: false)
        model.bars = [0.16, 0.24, 0.32, 0.24, 0.18]
        if !panel.isVisible {
            positionPanel(width: Layout.panelExtraWidth + model.textWidth, animated: false)
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }

        model.isVisible = false
        withAnimation(.spring(duration: 0.35, bounce: 0.26)) {
            model.isVisible = true
        }
    }

    func update(text: String, animated: Bool = true) {
        let displayText = text.isEmpty ? "开始说话…" : text
        let measuredWidth = measureTextWidth(displayText)
        model.text = displayText

        let updateBlock = {
            self.model.textWidth = measuredWidth
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.25), updateBlock)
            positionPanel(width: Layout.panelExtraWidth + measuredWidth, animated: true)
        } else {
            updateBlock()
            positionPanel(width: Layout.panelExtraWidth + measuredWidth, animated: false)
        }
    }

    func showRefining() {
        model.bars = [0.18, 0.28, 0.34, 0.28, 0.20]
        update(text: "Refining...", animated: true)
    }

    func updateBars(_ bars: [CGFloat]) {
        guard bars.count == 5 else { return }
        model.bars = bars
    }

    func flash(message: String) {
        show(text: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.hide()
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        withAnimation(.easeIn(duration: 0.22)) {
            model.isVisible = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in
            self?.panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.panelExtraWidth + Layout.minTextWidth, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow

        let effectView = NSVisualEffectView(frame: panel.contentRect(forFrameRect: panel.frame))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = Layout.height / 2
        effectView.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: FloatingOverlayView(model: model))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.setFrameSize(effectView.bounds.size)
        effectView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        panel.contentView = effectView
        return panel
    }

    private func measureTextWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium)
        ]
        let width = NSAttributedString(string: text, attributes: attributes).size().width + 12
        return max(Layout.minTextWidth, min(Layout.maxTextWidth, ceil(width)))
    }

    private func positionPanel(width: CGFloat, animated: Bool) {
        guard let screen = currentScreen() else { return }
        let visibleFrame = screen.visibleFrame
        let targetFrame = NSRect(
            x: visibleFrame.midX - width / 2,
            y: visibleFrame.minY + Layout.bottomInset,
            width: width,
            height: Layout.height
        )

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    private func currentScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    }
}

private struct FloatingOverlayView: View {
    @ObservedObject var model: FloatingOverlayModel

    var body: some View {
        HStack(spacing: 14) {
            WaveformView(bars: model.bars)
            Text(model.text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: model.textWidth, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .frame(height: 56)
        .scaleEffect(model.isVisible ? 1.0 : 0.88)
        .opacity(model.isVisible ? 1.0 : 0.0)
    }
}

private struct WaveformView: View {
    let bars: [CGFloat]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.92),
                                Color.white.opacity(0.56)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 5, height: max(6, value * 32))
            }
        }
        .frame(width: 44, height: 32, alignment: .bottom)
    }
}
