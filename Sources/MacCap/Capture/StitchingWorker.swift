import CoreGraphics
import Foundation
import MacCapCore

/// Keeps pixel conversion and overlap matching off AppKit's main actor so the
/// stop shortcut and capture HUD remain responsive on large Retina regions.
actor StitchingWorker {
    private var stitcher: LongScreenshotStitcher
    private let maximumFramePixels: Int

    init(stitcher: LongScreenshotStitcher, maximumFramePixels: Int) {
        self.stitcher = stitcher
        self.maximumFramePixels = maximumFramePixels
    }

    func append(_ image: CGImage) throws -> StitchAppendResult {
        try autoreleasepool {
            try Task.checkCancellation()
            let frame = try CGImageBridge.rgbaImage(
                from: image,
                maximumPixelCount: maximumFramePixels
            )
            try Task.checkCancellation()
            return try stitcher.append(frame)
        }
    }

    func hasReachedBottom() -> Bool {
        stitcher.reachedBottom
    }

    /// Transfers the final buffer and drops the retained previous frame before
    /// PNG encoding, keeping the save-stage peak lower.
    func takeOutput() -> RGBAImage? {
        let output = stitcher.output
        let configuration = stitcher.configuration
        stitcher = LongScreenshotStitcher(configuration: configuration)
        return output
    }
}
