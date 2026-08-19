import CoreGraphics
import Foundation

@MainActor
public final class ScrollDriver {
    public enum DriverError: LocalizedError {
        case eventSourceUnavailable
        case mouseEventCreationFailed
        case scrollEventCreationFailed
        case cursorMoveFailed(CGError)

        public var errorDescription: String? {
            switch self {
            case .eventSourceUnavailable:
                return "无法创建系统输入事件源。"
            case .mouseEventCreationFailed:
                return "无法创建鼠标移动事件。"
            case .scrollEventCreationFailed:
                return "无法创建滚动事件。"
            case let .cursorMoveFailed(error):
                return "无法移动鼠标指针（CGError: \(error.rawValue)）。"
            }
        }
    }

    public let targetPID: pid_t
    public private(set) var isPrepared = false
    public private(set) var currentScrollPoint: CGPoint?

    private let eventSource: CGEventSource
    private var originalCursorPosition: CGPoint?

    public init(targetPID: pid_t) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw DriverError.eventSourceUnavailable
        }
        self.targetPID = targetPID
        self.eventSource = source
    }

    /// Saves the current cursor position, moves to the capture area, and primes
    /// the target process to receive subsequent wheel events.
    @discardableResult
    public func prepare(at scrollPoint: CGPoint) throws -> CGPoint {
        if originalCursorPosition == nil {
            originalCursorPosition = CGEvent(source: nil)?.location ?? scrollPoint
        }

        let moveResult = CGWarpMouseCursorPosition(scrollPoint)
        guard moveResult == .success else {
            throw DriverError.cursorMoveFailed(moveResult)
        }

        do {
            try postMouseMove(to: scrollPoint)
        } catch {
            _ = restoreCursor()
            throw error
        }
        currentScrollPoint = scrollPoint
        isPrepared = true
        return originalCursorPosition ?? scrollPoint
    }

    /// Posts a pixel-based wheel event directly to the selected application.
    /// A negative vertical delta scrolls down; a positive delta scrolls up.
    public func postScroll(deltaY: Int32, deltaX: Int32 = 0) throws {
        guard let event = CGEvent(
            scrollWheelEvent2Source: eventSource,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            throw DriverError.scrollEventCreationFailed
        }

        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        if let currentScrollPoint {
            event.location = currentScrollPoint
        }
        event.postToPid(targetPID)
    }

    public func postScrollDown(points: Int32 = 640) throws {
        try postVerticalScrollInChunks(totalDelta: -max(1, points))
    }

    public func postScrollUp(points: Int32 = 640) throws {
        try postVerticalScrollInChunks(totalDelta: max(1, points))
    }

    /// Restores the physical cursor to where it was before `prepare(at:)`.
    @discardableResult
    public func restoreCursor() -> Bool {
        guard let originalCursorPosition else {
            isPrepared = false
            currentScrollPoint = nil
            return true
        }

        let result = CGWarpMouseCursorPosition(originalCursorPosition)
        if let moveEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: originalCursorPosition,
            mouseButton: .left
        ) {
            moveEvent.post(tap: .cghidEventTap)
        }

        self.originalCursorPosition = nil
        currentScrollPoint = nil
        isPrepared = false
        return result == .success
    }

    private func postMouseMove(to point: CGPoint) throws {
        guard let event = CGEvent(
            mouseEventSource: eventSource,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            throw DriverError.mouseEventCreationFailed
        }
        event.postToPid(targetPID)
    }

    private func postVerticalScrollInChunks(totalDelta: Int32) throws {
        let direction: Int32 = totalDelta < 0 ? -1 : 1
        var remaining = abs(totalDelta)
        let maximumChunk: Int32 = 10

        while remaining > 0 {
            let chunk = min(maximumChunk, remaining)
            try postScroll(deltaY: direction * chunk)
            remaining -= chunk
        }
    }

    deinit {
        if let originalCursorPosition {
            CGWarpMouseCursorPosition(originalCursorPosition)
        }
    }
}
