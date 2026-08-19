import AppKit

@MainActor
public final class CaptureHUDController: NSObject {
    public private(set) var didRequestStop = false

    public var isVisible: Bool {
        panel.isVisible
    }

    private let onStop: () -> Void
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private lazy var stopButton = NSButton(
        title: "停止",
        target: self,
        action: #selector(stopPressed)
    )
    private lazy var panel: NSPanel = makePanel()

    public init(onStop: @escaping () -> Void) {
        self.onStop = onStop
        super.init()
    }

    public func show(
        on screen: NSScreen? = nil,
        status: String = "正在生成长截图…",
        detail: String = "已截取 0 帧"
    ) {
        didRequestStop = false
        stopButton.isEnabled = true
        stopButton.title = "停止"
        statusLabel.stringValue = status
        setDetail(detail)

        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens.first
        if let targetScreen {
            positionPanel(on: targetScreen)
        }
        panel.orderFrontRegardless()
    }

    public func update(status: String? = nil, detail: String? = nil) {
        if let status {
            statusLabel.stringValue = status
        }
        if let detail {
            setDetail(detail)
        }
    }

    public func update(capturedFrameCount: Int) {
        setDetail("已截取 \(max(0, capturedFrameCount)) 帧")
    }

    public func close() {
        panel.orderOut(nil)
    }

    @objc
    private func stopPressed() {
        guard !didRequestStop else {
            return
        }
        didRequestStop = true
        statusLabel.stringValue = "正在停止…"
        stopButton.isEnabled = false
        onStop()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 310, height: 88),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let visualEffect = NSVisualEffectView(frame: panel.contentView?.bounds ?? .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = visualEffect

        statusLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor

        stopButton.bezelStyle = .rounded
        stopButton.keyEquivalent = "."
        stopButton.keyEquivalentModifierMask = .command

        let titleRow = NSStackView(views: [statusLabel, stopButton])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 12

        let stack = NSStackView(views: [titleRow, detailLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),
            stack.centerYAnchor.constraint(equalTo: visualEffect.centerYAnchor),
            titleRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return panel
    }

    private func setDetail(_ text: String) {
        detailLabel.stringValue = text
        detailLabel.isHidden = text.isEmpty
    }

    private func positionPanel(on screen: NSScreen) {
        let frame = panel.frame
        let visibleFrame = screen.visibleFrame
        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.maxX - frame.width - 20,
                y: visibleFrame.maxY - frame.height - 20
            )
        )
    }
}
