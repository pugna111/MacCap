import CoreGraphics

/// A rectangle selected on one display.
///
/// `sourceRect` uses ScreenCaptureKit's display-local coordinate system: its
/// origin is at the display's top-left and its values are measured in points.
public struct CaptureRegion: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    public let sourceRect: CGRect
    public let scrollPoint: CGPoint
    public let scale: CGFloat

    public init(
        displayID: CGDirectDisplayID,
        sourceRect: CGRect,
        scrollPoint: CGPoint,
        scale: CGFloat
    ) {
        self.displayID = displayID
        self.sourceRect = sourceRect.standardized
        self.scrollPoint = scrollPoint
        self.scale = max(1, scale)
    }

    public var pixelWidth: Int {
        max(1, Int((sourceRect.width * scale).rounded(.toNearestOrAwayFromZero)))
    }

    public var pixelHeight: Int {
        max(1, Int((sourceRect.height * scale).rounded(.toNearestOrAwayFromZero)))
    }
}

/// The value returned by the region-selection overlay.
public typealias SelectionResult = CaptureRegion
