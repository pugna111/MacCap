import XCTest
@testable import MacCapCore

final class PixelImageTests: XCTestCase {
    func testRGBA8UsesCompactChannelOrder() {
        var pixel = RGBA8(red: 1, green: 2, blue: 3, alpha: 4)
        let bytes = withUnsafeBytes(of: &pixel) { Array($0) }

        XCTAssertEqual(MemoryLayout<RGBA8>.size, 4)
        XCTAssertEqual(MemoryLayout<RGBA8>.stride, 4)
        XCTAssertEqual(bytes, [1, 2, 3, 4])
    }

    func testSyntheticRowsUseTopToBottomRowMajorOrder() throws {
        let red = RGBA8(red: 255, green: 0, blue: 0)
        let green = RGBA8(red: 0, green: 255, blue: 0)
        let blue = RGBA8(red: 0, green: 0, blue: 255)
        let white = RGBA8(red: 255, green: 255, blue: 255)

        let image = try RGBAImage(rows: [
            [red, green],
            [blue, white],
        ])

        XCTAssertEqual(image.width, 2)
        XCTAssertEqual(image.height, 2)
        XCTAssertEqual(image[0, 0], red)
        XCTAssertEqual(image[1, 0], green)
        XCTAssertEqual(image[0, 1], blue)
        XCTAssertEqual(image[1, 1], white)
        XCTAssertEqual(image.grayscale().pixels, [77, 149, 29, 255])
    }

    func testSyntheticRowsRejectUnevenWidths() {
        XCTAssertThrowsError(try GrayImage(rows: [[1, 2], [3]])) { error in
            XCTAssertEqual(
                error as? PixelImageError,
                .inconsistentRowWidth(row: 1, expected: 2, actual: 1)
            )
        }
    }

    func testFlatPixelInitializerRejectsWrongCount() {
        XCTAssertThrowsError(
            try RGBAImage(
                width: 2,
                height: 2,
                pixels: [RGBA8(red: 0, green: 0, blue: 0)]
            )
        ) { error in
            XCTAssertEqual(
                error as? PixelImageError,
                .pixelCountMismatch(expected: 4, actual: 1)
            )
        }
    }
}
