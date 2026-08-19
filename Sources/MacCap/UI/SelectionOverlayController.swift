import AppKit
import CoreGraphics

@MainActor
public final class SelectionOverlayController: NSObject {
    public var minimumSelectionSize = CGSize(width: 24, height: 24)

    public private(set) var isSelecting = false

    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((SelectionResult?) -> Void)?

    public override init() {
        super.init()
    }

    /// Presents an overlay on every connected display. A drag is constrained to
    /// the display on which it started, so every result belongs to one display.
    public func selectRegion() async -> SelectionResult? {
        await withCheckedContinuation { continuation in
            beginSelection { result in
                continuation.resume(returning: result)
            }
        }
    }

    public func beginSelection(completion: @escaping (SelectionResult?) -> Void) {
        if isSelecting {
            finish(with: nil)
        }

        self.completion = completion
        isSelecting = true

        overlayWindows = NSScreen.screens.map { screen in
            let window = SelectionOverlayWindow(screen: screen)
            window.onCancel = { [weak self] in
                self?.cancel()
            }
            window.selectionView.minimumSelectionSize = minimumSelectionSize
            window.selectionView.onSelectionFinished = { [weak self, weak screen] localRect in
                guard let self, let screen else {
                    return
                }
                self.completeSelection(localRect: localRect, on: screen)
            }
            return window
        }

        guard !overlayWindows.isEmpty else {
            finish(with: nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.forEach { $0.orderFrontRegardless() }
        overlayWindows.first?.makeKey()
    }

    public func cancel() {
        guard isSelecting else {
            return
        }
        finish(with: nil)
    }

    private func completeSelection(localRect: CGRect, on screen: NSScreen) {
        let displaySize = screen.frame.size
        let displayLocalBounds = CGRect(origin: .zero, size: displaySize)
        let selectedRect = localRect.standardized.integral.intersection(displayLocalBounds)
        guard selectedRect.width >= minimumSelectionSize.width,
              selectedRect.height >= minimumSelectionSize.height,
              let displayID = Self.displayID(for: screen) else {
            return
        }

        // AppKit view coordinates start at the bottom-left. ScreenCaptureKit's
        // source rectangle starts at the top-left of the chosen display.
        let sourceRect = CGRect(
            x: selectedRect.minX,
            y: displaySize.height - selectedRect.maxY,
            width: selectedRect.width,
            height: selectedRect.height
        )

        let quartzDisplayBounds = CGDisplayBounds(displayID)
        let scrollPoint = CGPoint(
            x: quartzDisplayBounds.minX + sourceRect.midX,
            y: quartzDisplayBounds.minY + sourceRect.midY
        )
        let result = SelectionResult(
            displayID: displayID,
            sourceRect: sourceRect,
            scrollPoint: scrollPoint,
            scale: screen.backingScaleFactor
        )
        finish(with: result)
    }

    private func finish(with result: SelectionResult?) {
        let callback = completion
        completion = nil
        isSelecting = false

        overlayWindows.forEach { window in
            window.onCancel = nil
            window.selectionView.onSelectionFinished = nil
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        callback?(result)
    }

    private static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}

@MainActor
private final class SelectionOverlayWindow: NSWindow {
    let selectionView = SelectionOverlayView(frame: .zero)
    var onCancel: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        isReleasedWhenClosed = false
        ignoresMouseEvents = false
        sharingType = .none
        contentView = selectionView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

@MainActor
private final class SelectionOverlayView: NSView {
    var minimumSelectionSize = CGSize(width: 24, height: 24)
    var onSelectionFinished: ((CGRect) -> Void)?

    private var dragStart: CGPoint?
    private var dragCurrent: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(convert(event.locationInWindow, from: nil))
        dragStart = point
        dragCurrent = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragStart != nil else {
            return
        }
        dragCurrent = clampedPoint(convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStart else {
            return
        }
        let end = clampedPoint(convert(event.locationInWindow, from: nil))
        let rect = CGRect(
            x: min(dragStart.x, end.x),
            y: min(dragStart.y, end.y),
            width: abs(end.x - dragStart.x),
            height: abs(end.y - dragStart.y)
        )

        if rect.width >= minimumSelectionSize.width,
           rect.height >= minimumSelectionSize.height {
            onSelectionFinished?(rect)
        } else {
            self.dragStart = nil
            dragCurrent = nil
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.34).setFill()
        bounds.fill()

        if let selectionRect {
            guard let context = NSGraphicsContext.current?.cgContext else {
                return
            }
            context.saveGState()
            context.setBlendMode(.copy)
            context.setFillColor(NSColor.clear.cgColor)
            context.fill(selectionRect)
            context.restoreGState()

            NSColor.white.setStroke()
            let border = NSBezierPath(rect: selectionRect.insetBy(dx: 1, dy: 1))
            border.lineWidth = 2
            border.stroke()

            drawSizeLabel(for: selectionRect)
        } else {
            drawInstruction()
        }
    }

    private var selectionRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else {
            return nil
        }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func clampedPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func drawInstruction() {
        let text = "拖动选择长截图区域 · Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let textOrigin = CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        let backgroundRect = CGRect(origin: textOrigin, size: size).insetBy(dx: -14, dy: -9)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 8, yRadius: 8).fill()
        text.draw(at: textOrigin, withAttributes: attributes)
    }

    private func drawSizeLabel(for rect: CGRect) {
        let scale = window?.screen?.backingScaleFactor ?? 1
        let width = Int((rect.width * scale).rounded())
        let height = Int((rect.height * scale).rounded())
        let text = "\(width) × \(height) px"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 14)
        if origin.y < 8 {
            origin.y = min(bounds.maxY - size.height - 8, rect.maxY + 10)
        }
        origin.x = min(max(8, origin.x), bounds.maxX - size.width - 8)

        let backgroundRect = CGRect(origin: origin, size: size).insetBy(dx: -6, dy: -4)
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: backgroundRect, xRadius: 4, yRadius: 4).fill()
        text.draw(at: origin, withAttributes: attributes)
    }
}
