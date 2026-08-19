public enum PixelImageError: Error, Equatable, Sendable {
    case invalidDimensions(width: Int, height: Int)
    case pixelCountMismatch(expected: Int, actual: Int)
    case inconsistentRowWidth(row: Int, expected: Int, actual: Int)
}

/// A single 8-bit RGBA pixel.
@frozen
public struct RGBA8: Equatable, Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A small platform-independent image value used by the stitching core.
/// Pixels are stored in row-major order, from top-left to bottom-right.
public struct RGBAImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [RGBA8]

    public init(width: Int, height: Int, pixels: [RGBA8]) throws {
        let expectedCount = try Self.validatedPixelCount(width: width, height: height)
        guard pixels.count == expectedCount else {
            throw PixelImageError.pixelCountMismatch(
                expected: expectedCount,
                actual: pixels.count
            )
        }

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, repeating pixel: RGBA8) throws {
        let count = try Self.validatedPixelCount(width: width, height: height)
        self.width = width
        self.height = height
        self.pixels = Array(repeating: pixel, count: count)
    }

    /// Convenience initializer intended for fixtures and synthetic image input.
    public init(rows: [[RGBA8]]) throws {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            throw PixelImageError.invalidDimensions(
                width: rows.first?.count ?? 0,
                height: rows.count
            )
        }

        let width = firstRow.count
        for (index, row) in rows.enumerated() where row.count != width {
            throw PixelImageError.inconsistentRowWidth(
                row: index,
                expected: width,
                actual: row.count
            )
        }

        try self.init(width: width, height: rows.count, pixels: rows.flatMap { $0 })
    }

    public subscript(x: Int, y: Int) -> RGBA8 {
        get { pixels[(y * width) + x] }
        set { pixels[(y * width) + x] = newValue }
    }

    public func grayscale() -> GrayImage {
        // Integer BT.601 coefficients scaled by 256.
        let values = pixels.map { pixel -> UInt8 in
            let luminance = (77 * Int(pixel.red))
                + (150 * Int(pixel.green))
                + (29 * Int(pixel.blue))
                + 128
            return UInt8(luminance >> 8)
        }

        // Dimensions are already validated by RGBAImage.
        return try! GrayImage(width: width, height: height, pixels: values)
    }

    private static func validatedPixelCount(width: Int, height: Int) throws -> Int {
        guard width > 0, height > 0 else {
            throw PixelImageError.invalidDimensions(width: width, height: height)
        }

        let (count, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw PixelImageError.invalidDimensions(width: width, height: height)
        }
        return count
    }
}

/// An 8-bit luminance image used for fast matching.
public struct GrayImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0 else {
            throw PixelImageError.invalidDimensions(width: width, height: height)
        }

        let (expectedCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw PixelImageError.invalidDimensions(width: width, height: height)
        }
        guard pixels.count == expectedCount else {
            throw PixelImageError.pixelCountMismatch(
                expected: expectedCount,
                actual: pixels.count
            )
        }

        self.width = width
        self.height = height
        self.pixels = pixels
    }

    /// Convenience initializer intended for fixtures and synthetic image input.
    public init(rows: [[UInt8]]) throws {
        guard let firstRow = rows.first, !firstRow.isEmpty else {
            throw PixelImageError.invalidDimensions(
                width: rows.first?.count ?? 0,
                height: rows.count
            )
        }

        let width = firstRow.count
        for (index, row) in rows.enumerated() where row.count != width {
            throw PixelImageError.inconsistentRowWidth(
                row: index,
                expected: width,
                actual: row.count
            )
        }

        try self.init(width: width, height: rows.count, pixels: rows.flatMap { $0 })
    }

    public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[(y * width) + x] }
        set { pixels[(y * width) + x] = newValue }
    }
}
