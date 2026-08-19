import AppKit
import Carbon.HIToolbox

final class ShortcutRecorderControl: NSControl {
    var onShortcutChange: ((KeyboardShortcut) throws -> Void)?
    var onValidationMessage: ((String?) -> Void)?

    private(set) var shortcut: KeyboardShortcut {
        didSet { needsDisplay = true }
    }

    private var isRecording = false {
        didSet { needsDisplay = true }
    }
    private var localKeyMonitor: Any?

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        focusRingType = .exterior
        toolTip = "点击后按下新的快捷键"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 190, height: 30)
    }

    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        beginRecording()
        onValidationMessage?(nil)
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    private func record(_ event: NSEvent) {
        guard !event.isARepeat else { return }

        if Int(event.keyCode) == kVK_Escape {
            finishRecording()
            onValidationMessage?(nil)
            return
        }

        let candidate = KeyboardShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: KeyboardShortcut.modifiers(from: event.modifierFlags)
        )
        guard candidate.hasRequiredModifier else {
            NSSound.beep()
            onValidationMessage?(GlobalHotKeyError.modifierRequired.localizedDescription)
            return
        }

        do {
            try onShortcutChange?(candidate)
            shortcut = candidate
            onValidationMessage?(nil)
            finishRecording()
        } catch {
            NSSound.beep()
            onValidationMessage?(error.localizedDescription)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 0.75, dy: 0.75)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        let accent = NSColor.controlAccentColor

        (isRecording
            ? accent.withAlphaComponent(0.12)
            : NSColor.controlBackgroundColor).setFill()
        path.fill()

        (isRecording ? accent : NSColor.separatorColor).setStroke()
        path.lineWidth = isRecording ? 1.5 : 1
        path.stroke()

        let title = isRecording ? "请按新的快捷键…" : shortcut.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = title.size(withAttributes: attributes)
        let origin = NSPoint(
            x: floor((bounds.width - size.width) / 2),
            y: floor((bounds.height - size.height) / 2)
        )
        title.draw(at: origin, withAttributes: attributes)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func finishRecording() {
        stopRecording()
        window?.makeFirstResponder(nil)
    }

    private func beginRecording() {
        isRecording = true
        guard localKeyMonitor == nil else { return }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self, self.isRecording else { return event }
            self.record(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }
}
