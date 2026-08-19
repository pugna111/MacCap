public struct LongScreenshotConfiguration: Equatable, Sendable {
    public var match: VerticalMatchConfiguration
    public var maximumOutputHeight: Int
    /// Maximum same-position mean grayscale error for declaring that scrolling
    /// no longer changed the captured frame.
    public var identicalFrameMaximumMeanError: Double

    public init(
        match: VerticalMatchConfiguration = .init(),
        maximumOutputHeight: Int = 30_000,
        identicalFrameMaximumMeanError: Double = 0
    ) {
        self.match = match
        self.maximumOutputHeight = maximumOutputHeight
        self.identicalFrameMaximumMeanError = identicalFrameMaximumMeanError
    }
}

public enum StitchAppendResult: Equatable, Sendable {
    case started(totalHeight: Int)
    case appended(match: VerticalMatch, totalHeight: Int)
    case reachedBottom(totalHeight: Int)
}

public struct LongScreenshotResult: Equatable, Sendable {
    public let image: RGBAImage
    public let reachedBottom: Bool
    public let acceptedFrameCount: Int

    public init(image: RGBAImage, reachedBottom: Bool, acceptedFrameCount: Int) {
        self.image = image
        self.reachedBottom = reachedBottom
        self.acceptedFrameCount = acceptedFrameCount
    }
}

public enum LongScreenshotError: Error, Equatable, Sendable {
    case invalidConfiguration
    case frameDimensionMismatch(
        expectedWidth: Int,
        expectedHeight: Int,
        actualWidth: Int,
        actualHeight: Int
    )
    case maximumHeightExceeded(limit: Int, attempted: Int)
}

public struct LongScreenshotStitcher: Sendable {
    public let configuration: LongScreenshotConfiguration
    public private(set) var reachedBottom = false
    public private(set) var acceptedFrameCount = 0

    private var previousFrame: RGBAImage?
    private var previousGrayFrame: GrayImage?
    private var accumulatedPixels: [RGBA8] = []
    private var outputWidth: Int?
    private var outputHeight = 0

    /// A snapshot of the rows accepted so far. Creating this value is O(1)
    /// until either its pixels or the stitcher's internal buffer are mutated.
    public var output: RGBAImage? {
        guard let outputWidth else { return nil }
        // Internal state only comes from already validated RGBAImage values.
        return try! RGBAImage(
            width: outputWidth,
            height: outputHeight,
            pixels: accumulatedPixels
        )
    }

    public init(configuration: LongScreenshotConfiguration = .init()) {
        self.configuration = configuration
    }

    /// Adds one fixed-size viewport capture to the result.
    /// The receiver is unchanged when this method throws.
    @discardableResult
    public mutating func append(_ frame: RGBAImage) throws -> StitchAppendResult {
        try validateConfiguration()

        if reachedBottom {
            return .reachedBottom(totalHeight: outputHeight)
        }

        guard let previousFrame else {
            guard frame.height <= configuration.maximumOutputHeight else {
                throw LongScreenshotError.maximumHeightExceeded(
                    limit: configuration.maximumOutputHeight,
                    attempted: frame.height
                )
            }

            self.previousFrame = frame
            previousGrayFrame = frame.grayscale()
            accumulatedPixels = frame.pixels
            outputWidth = frame.width
            outputHeight = frame.height
            acceptedFrameCount = 1
            return .started(totalHeight: frame.height)
        }

        guard previousFrame.width == frame.width, previousFrame.height == frame.height else {
            throw LongScreenshotError.frameDimensionMismatch(
                expectedWidth: previousFrame.width,
                expectedHeight: previousFrame.height,
                actualWidth: frame.width,
                actualHeight: frame.height
            )
        }

        if previousFrame == frame {
            reachedBottom = true
            return .reachedBottom(totalHeight: outputHeight)
        }

        let currentGray = frame.grayscale()
        let previousGray = previousGrayFrame ?? previousFrame.grayscale()
        if configuration.identicalFrameMaximumMeanError > 0,
           meanAbsoluteError(previousGray, currentGray)
            <= configuration.identicalFrameMaximumMeanError {
            reachedBottom = true
            return .reachedBottom(totalHeight: outputHeight)
        }

        let matcher = VerticalDisplacementMatcher(configuration: configuration.match)
        let match = try matcher.match(previous: previousGray, current: currentGray)
        let (attemptedHeight, heightOverflow) = outputHeight.addingReportingOverflow(
            match.displacement
        )
        guard !heightOverflow, attemptedHeight <= configuration.maximumOutputHeight else {
            throw LongScreenshotError.maximumHeightExceeded(
                limit: configuration.maximumOutputHeight,
                attempted: heightOverflow ? Int.max : attemptedHeight
            )
        }

        let appendedRowCount = match.displacement
        let firstAppendedPixel = (frame.height - appendedRowCount) * frame.width
        accumulatedPixels.append(contentsOf: frame.pixels[firstAppendedPixel...])

        self.previousFrame = frame
        previousGrayFrame = currentGray
        outputHeight = attemptedHeight
        acceptedFrameCount += 1
        return .appended(match: match, totalHeight: attemptedHeight)
    }

    public static func stitch(
        frames: [RGBAImage],
        configuration: LongScreenshotConfiguration = .init()
    ) throws -> LongScreenshotResult? {
        var stitcher = LongScreenshotStitcher(configuration: configuration)
        for frame in frames {
            let result = try stitcher.append(frame)
            if case .reachedBottom = result {
                break
            }
        }

        guard let image = stitcher.output else { return nil }
        return LongScreenshotResult(
            image: image,
            reachedBottom: stitcher.reachedBottom,
            acceptedFrameCount: stitcher.acceptedFrameCount
        )
    }

    private func validateConfiguration() throws {
        guard configuration.maximumOutputHeight > 0,
              configuration.identicalFrameMaximumMeanError.isFinite,
              (0...255).contains(configuration.identicalFrameMaximumMeanError) else {
            throw LongScreenshotError.invalidConfiguration
        }
    }

    private func meanAbsoluteError(_ lhs: GrayImage, _ rhs: GrayImage) -> Double {
        var total: Int64 = 0
        for index in lhs.pixels.indices {
            total += Int64(abs(Int(lhs.pixels[index]) - Int(rhs.pixels[index])))
        }
        return Double(total) / Double(lhs.pixels.count)
    }
}
