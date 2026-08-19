import XCTest
@testable import MacCapCore

final class LongScreenshotStitcherTests: XCTestCase {
    func testStitchesFramesIncrementallyAndStopsOnIdenticalFrame() throws {
        let content = syntheticContent(width: 6, height: 10)
        let first = try frame(from: content, startRow: 0, height: 6)
        let second = try frame(from: content, startRow: 2, height: 6)
        let third = try frame(from: content, startRow: 4, height: 6)
        var stitcher = LongScreenshotStitcher(configuration: configuration(maximumHeight: 20))

        XCTAssertEqual(try stitcher.append(first), .started(totalHeight: 6))

        let secondResult = try stitcher.append(second)
        guard case let .appended(secondMatch, secondHeight) = secondResult else {
            return XCTFail("Expected the second frame to be appended")
        }
        XCTAssertEqual(secondMatch.displacement, 2)
        XCTAssertEqual(secondHeight, 8)

        let thirdResult = try stitcher.append(third)
        guard case let .appended(thirdMatch, thirdHeight) = thirdResult else {
            return XCTFail("Expected the third frame to be appended")
        }
        XCTAssertEqual(thirdMatch.displacement, 2)
        XCTAssertEqual(thirdHeight, 10)
        XCTAssertEqual(stitcher.output, content)
        XCTAssertEqual(stitcher.acceptedFrameCount, 3)

        XCTAssertEqual(try stitcher.append(third), .reachedBottom(totalHeight: 10))
        XCTAssertTrue(stitcher.reachedBottom)
        XCTAssertEqual(stitcher.output, content)
        XCTAssertEqual(stitcher.acceptedFrameCount, 3)
    }

    func testIdenticalSecondFrameMeansAlreadyAtBottom() throws {
        let frame = syntheticContent(width: 4, height: 6)
        var stitcher = LongScreenshotStitcher(configuration: configuration(maximumHeight: 10))

        _ = try stitcher.append(frame)
        let result = try stitcher.append(frame)

        XCTAssertEqual(result, .reachedBottom(totalHeight: 6))
        XCTAssertTrue(stitcher.reachedBottom)
        XCTAssertEqual(stitcher.output, frame)
    }

    func testMaximumHeightFailureDoesNotMutateState() throws {
        let content = syntheticContent(width: 5, height: 8)
        let first = try frame(from: content, startRow: 0, height: 6)
        let second = try frame(from: content, startRow: 2, height: 6)
        var stitcher = LongScreenshotStitcher(configuration: configuration(maximumHeight: 7))
        _ = try stitcher.append(first)

        XCTAssertThrowsError(try stitcher.append(second)) { error in
            XCTAssertEqual(
                error as? LongScreenshotError,
                .maximumHeightExceeded(limit: 7, attempted: 8)
            )
        }
        XCTAssertEqual(stitcher.output, first)
        XCTAssertEqual(stitcher.acceptedFrameCount, 1)
        XCTAssertFalse(stitcher.reachedBottom)
    }

    func testBatchStitchReturnsCombinedImageAndBottomStatus() throws {
        let content = syntheticContent(width: 5, height: 8)
        let first = try frame(from: content, startRow: 0, height: 6)
        let second = try frame(from: content, startRow: 2, height: 6)

        let result = try XCTUnwrap(
            LongScreenshotStitcher.stitch(
                frames: [first, second, second],
                configuration: configuration(maximumHeight: 20)
            )
        )

        XCTAssertEqual(result.image, content)
        XCTAssertTrue(result.reachedBottom)
        XCTAssertEqual(result.acceptedFrameCount, 2)
    }

    private func configuration(maximumHeight: Int) -> LongScreenshotConfiguration {
        LongScreenshotConfiguration(
            match: exactMatchConfiguration(maximumDisplacement: 4),
            maximumOutputHeight: maximumHeight,
            identicalFrameMaximumMeanError: 0
        )
    }
}
