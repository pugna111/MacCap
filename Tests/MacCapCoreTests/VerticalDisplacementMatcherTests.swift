import XCTest
@testable import MacCapCore

final class VerticalDisplacementMatcherTests: XCTestCase {
    func testFindsDownwardVerticalDisplacement() throws {
        let content = syntheticContent(width: 7, height: 14)
        let previous = try frame(from: content, startRow: 0, height: 9)
        let current = try frame(from: content, startRow: 3, height: 9)
        let matcher = VerticalDisplacementMatcher(
            configuration: exactMatchConfiguration(maximumDisplacement: 6)
        )

        let result = try matcher.match(previous: previous, current: current)

        XCTAssertEqual(result.displacement, 3)
        XCTAssertEqual(result.overlapRows, 6)
        XCTAssertEqual(result.meanAbsoluteError, 0)
        XCTAssertEqual(result.confidence, 1)
        XCTAssertEqual(result.comparedSampleCount, 42)
    }

    func testRejectsLowConfidenceMatch() throws {
        let black = try GrayImage(width: 5, height: 8, pixels: Array(repeating: 0, count: 40))
        let white = try GrayImage(width: 5, height: 8, pixels: Array(repeating: 255, count: 40))
        let matcher = VerticalDisplacementMatcher(
            configuration: exactMatchConfiguration(maximumDisplacement: 5)
        )

        XCTAssertThrowsError(try matcher.match(previous: black, current: white)) { error in
            guard let matchError = error as? VerticalMatchError,
                  case let .lowConfidence(best, required) = matchError else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(best, 0)
            XCTAssertEqual(required, 0.999)
        }
    }

    func testRejectsFramesWithDifferentDimensions() throws {
        let previous = try GrayImage(width: 2, height: 5, pixels: Array(repeating: 0, count: 10))
        let current = try GrayImage(width: 3, height: 5, pixels: Array(repeating: 0, count: 15))
        let matcher = VerticalDisplacementMatcher(
            configuration: exactMatchConfiguration(maximumDisplacement: 3)
        )

        XCTAssertThrowsError(try matcher.match(previous: previous, current: current)) { error in
            XCTAssertEqual(
                error as? VerticalMatchError,
                .dimensionMismatch(
                    previousWidth: 2,
                    previousHeight: 5,
                    currentWidth: 3,
                    currentHeight: 5
                )
            )
        }
    }

    func testFindsExactPixelDisplacementInTallFrame() throws {
        let width = 20
        let frameHeight = 600
        let displacement = 138
        let content = try GrayImage(rows: (0..<(frameHeight + displacement)).map { y in
            Array(repeating: UInt8(y % 251), count: width)
        })
        let previous = try grayFrame(from: content, startRow: 0, height: frameHeight)
        let current = try grayFrame(
            from: content,
            startRow: displacement,
            height: frameHeight
        )
        let matcher = VerticalDisplacementMatcher(
            configuration: VerticalMatchConfiguration(
                maximumDisplacement: 300,
                minimumOverlapRows: 100,
                horizontalSampleStride: 1,
                verticalSampleStride: 1,
                ignoredHorizontalEdgeFraction: 0,
                ignoredTopFraction: 0,
                targetSampleCountPerCandidate: 2_048,
                minimumConfidence: 0.999
            )
        )

        let result = try matcher.match(previous: previous, current: current)

        XCTAssertEqual(result.displacement, displacement)
        XCTAssertEqual(result.meanAbsoluteError, 0)
        XCTAssertLessThanOrEqual(result.comparedSampleCount, 2_048)
    }

    func testCanIgnoreFixedHeaderWhenMatching() throws {
        let width = 8
        let height = 12
        let displacement = 3
        let fixedHeaderRows = 2
        let header = Array(repeating: UInt8(240), count: width)
        func contentRow(_ globalY: Int) -> [UInt8] {
            (0..<width).map { x in UInt8((globalY * 17 + x * 11) % 230) }
        }
        let previous = try GrayImage(rows: (0..<height).map { y in
            y < fixedHeaderRows ? header : contentRow(y)
        })
        let current = try GrayImage(rows: (0..<height).map { y in
            y < fixedHeaderRows ? header : contentRow(y + displacement)
        })
        let matcher = VerticalDisplacementMatcher(
            configuration: VerticalMatchConfiguration(
                maximumDisplacement: 6,
                minimumOverlapRows: 3,
                horizontalSampleStride: 1,
                verticalSampleStride: 1,
                ignoredHorizontalEdgeFraction: 0,
                ignoredTopFraction: 0.2,
                targetSampleCountPerCandidate: 2_048,
                minimumConfidence: 0.999
            )
        )

        let result = try matcher.match(previous: previous, current: current)

        XCTAssertEqual(result.displacement, displacement)
        XCTAssertEqual(result.meanAbsoluteError, 0)
    }

    func testRejectsAmbiguousRepeatingRows() throws {
        let width = 12
        let height = 24
        let previous = try GrayImage(rows: (0..<height).map { y in
            Array(repeating: UInt8((y % 6) * 30), count: width)
        })
        let current = try GrayImage(rows: (0..<height).map { y in
            Array(repeating: UInt8(((y + 2) % 6) * 30), count: width)
        })
        let matcher = VerticalDisplacementMatcher(
            configuration: VerticalMatchConfiguration(
                maximumDisplacement: 10,
                minimumOverlapRows: 8,
                horizontalSampleStride: 1,
                verticalSampleStride: 1,
                ignoredHorizontalEdgeFraction: 0,
                ignoredTopFraction: 0,
                minimumDistinctDisplacement: 4,
                minimumAbsoluteErrorSeparation: 2,
                minimumRelativeErrorSeparation: 0.15,
                minimumConfidence: 0.999
            )
        )

        XCTAssertThrowsError(try matcher.match(previous: previous, current: current)) { error in
            guard let matchError = error as? VerticalMatchError,
                  case .ambiguousMatch = matchError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testAcceptsUniqueMatchWhenOnlyImmediateNeighborsAreSimilar() throws {
        let width = 10
        let frameHeight = 40
        let displacement = 10
        let content = try GrayImage(rows: (0..<(frameHeight + displacement)).map { y in
            Array(repeating: UInt8(y), count: width)
        })
        let previous = try grayFrame(from: content, startRow: 0, height: frameHeight)
        let current = try grayFrame(
            from: content,
            startRow: displacement,
            height: frameHeight
        )
        let matcher = VerticalDisplacementMatcher(
            configuration: VerticalMatchConfiguration(
                maximumDisplacement: 20,
                minimumOverlapRows: 10,
                horizontalSampleStride: 1,
                verticalSampleStride: 1,
                ignoredHorizontalEdgeFraction: 0,
                ignoredTopFraction: 0,
                minimumConfidence: 0.99
            )
        )

        let result = try matcher.match(previous: previous, current: current)

        XCTAssertEqual(result.displacement, displacement)
    }
}

func exactMatchConfiguration(maximumDisplacement: Int) -> VerticalMatchConfiguration {
    VerticalMatchConfiguration(
        minimumDisplacement: 1,
        maximumDisplacement: maximumDisplacement,
        minimumOverlapRows: 2,
        horizontalSampleStride: 1,
        verticalSampleStride: 1,
        minimumConfidence: 0.999
    )
}

func syntheticContent(width: Int, height: Int) -> RGBAImage {
    var pixels: [RGBA8] = []
    pixels.reserveCapacity(width * height)
    for y in 0..<height {
        for x in 0..<width {
            let value = UInt8((y * 37 + x * 19 + y * x * 3) % 251)
            pixels.append(RGBA8(red: value, green: value, blue: value))
        }
    }
    return try! RGBAImage(width: width, height: height, pixels: pixels)
}

func frame(from content: RGBAImage, startRow: Int, height: Int) throws -> RGBAImage {
    let firstPixel = startRow * content.width
    let endPixel = (startRow + height) * content.width
    return try RGBAImage(
        width: content.width,
        height: height,
        pixels: Array(content.pixels[firstPixel..<endPixel])
    )
}

func grayFrame(from content: GrayImage, startRow: Int, height: Int) throws -> GrayImage {
    let firstPixel = startRow * content.width
    let endPixel = (startRow + height) * content.width
    return try GrayImage(
        width: content.width,
        height: height,
        pixels: Array(content.pixels[firstPixel..<endPixel])
    )
}
