import CoreGraphics
import Foundation
import ScreenCaptureKit

@available(macOS 14.0, *)
@MainActor
public final class ScreenCaptureService {
    public enum CaptureError: LocalizedError {
        case displayNotFound(CGDirectDisplayID)
        case ownApplicationNotFound
        case invalidRegion(CGRect)

        public var errorDescription: String? {
            switch self {
            case let .displayNotFound(displayID):
                return "找不到显示器（ID: \(displayID)）。"
            case .ownApplicationNotFound:
                return "无法从屏幕捕获列表中识别 MacCap，请重试。"
            case .invalidRegion:
                return "截图区域无效。"
            }
        }
    }

    private final class PreparedDisplay {
        let filter: SCContentFilter
        let configuration = SCStreamConfiguration()

        init(filter: SCContentFilter) {
            self.filter = filter
        }
    }

    private var preparedDisplays: [CGDirectDisplayID: PreparedDisplay] = [:]

    public init() {}

    /// Loads and caches the content filter and stream configuration for a display.
    public func prepare(for displayID: CGDirectDisplayID) async throws {
        _ = try await preparedDisplay(for: displayID)
    }

    /// Captures the selected region at native backing resolution.
    public func capture(
        region: CaptureRegion,
        showsCursor: Bool = false
    ) async throws -> CGImage {
        guard !region.sourceRect.isNull,
              !region.sourceRect.isInfinite,
              region.sourceRect.width > 0,
              region.sourceRect.height > 0 else {
            throw CaptureError.invalidRegion(region.sourceRect)
        }

        let prepared = try await preparedDisplay(for: region.displayID)
        let configuration = prepared.configuration
        configuration.sourceRect = region.sourceRect
        configuration.width = region.pixelWidth
        configuration.height = region.pixelHeight
        configuration.showsCursor = showsCursor

        return try await SCScreenshotManager.captureImage(
            contentFilter: prepared.filter,
            configuration: configuration
        )
    }

    /// Drops cached ScreenCaptureKit objects, for example after display changes.
    public func invalidate() {
        preparedDisplays.removeAll()
    }

    private func preparedDisplay(for displayID: CGDirectDisplayID) async throws -> PreparedDisplay {
        if let prepared = preparedDisplays[displayID] {
            return prepared
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: false
        )
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound(displayID)
        }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard let ownApplication = content.applications.first(where: {
            $0.processID == ownPID
        }) else {
            throw CaptureError.ownApplicationNotFound
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [ownApplication],
            exceptingWindows: []
        )

        let prepared = PreparedDisplay(filter: filter)
        preparedDisplays[displayID] = prepared
        return prepared
    }
}
