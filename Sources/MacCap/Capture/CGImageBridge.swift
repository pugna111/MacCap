import CoreGraphics
import Foundation
import MacCapCore

enum CGImageBridgeError: LocalizedError {
    case invalidDimensions
    case pixelBudgetExceeded(actual: Int, limit: Int)
    case unsupportedPixelLayout
    case bitmapContextCreationFailed
    case imageCreationFailed

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            return "截图尺寸无效。"
        case let .pixelBudgetExceeded(actual, limit):
            return "截图包含 \(actual) 个像素，超过单帧上限 \(limit)。"
        case .unsupportedPixelLayout:
            return "当前系统不支持所需的像素布局。"
        case .bitmapContextCreationFailed:
            return "无法读取截图像素。"
        case .imageCreationFailed:
            return "无法生成拼接图片。"
        }
    }
}

enum CGImageBridge {
    private static var usesCompactRGBAChannelLayout: Bool {
        MemoryLayout<RGBA8>.size == 4
            && MemoryLayout<RGBA8>.stride == 4
            && MemoryLayout<RGBA8>.offset(of: \RGBA8.red) == 0
            && MemoryLayout<RGBA8>.offset(of: \RGBA8.green) == 1
            && MemoryLayout<RGBA8>.offset(of: \RGBA8.blue) == 2
            && MemoryLayout<RGBA8>.offset(of: \RGBA8.alpha) == 3
    }

    static func rgbaImage(
        from image: CGImage,
        maximumPixelCount: Int? = nil
    ) throws -> RGBAImage {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              width <= Int.max / height,
              width * height <= Int.max / 4 else {
            throw CGImageBridgeError.invalidDimensions
        }
        let pixelCount = width * height
        if let maximumPixelCount, pixelCount > maximumPixelCount {
            throw CGImageBridgeError.pixelBudgetExceeded(
                actual: pixelCount,
                limit: maximumPixelCount
            )
        }

        guard usesCompactRGBAChannelLayout else {
            throw CGImageBridgeError.unsupportedPixelLayout
        }

        // Draw directly into the stitcher's pixel array. The previous
        // implementation allocated a second byte array and copied every pixel.
        var pixels = [RGBA8](
            repeating: RGBA8(red: 0, green: 0, blue: 0, alpha: 0),
            count: pixelCount
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                return false
            }

            // Store scanlines from top to bottom, matching MacCapCore's model.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            throw CGImageBridgeError.bitmapContextCreationFailed
        }

        return try RGBAImage(width: width, height: height, pixels: pixels)
    }

    static func cgImage(from image: RGBAImage) throws -> CGImage {
        guard image.width > 0, image.height > 0,
              image.width <= Int.max / image.height,
              image.width * image.height <= Int.max / 4 else {
            throw CGImageBridgeError.invalidDimensions
        }
        guard usesCompactRGBAChannelLayout else {
            throw CGImageBridgeError.unsupportedPixelLayout
        }

        // Copy the contiguous RGBA storage directly into the provider's Data.
        // This keeps only one save-stage byte copy instead of an intermediate
        // [UInt8] followed by another Data allocation.
        let data = image.pixels.withUnsafeBytes { buffer in
            Data(buffer)
        }
        guard let provider = CGDataProvider(data: data as CFData) else {
            throw CGImageBridgeError.imageCreationFailed
        }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        guard let output = CGImage(
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: image.width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw CGImageBridgeError.imageCreationFailed
        }
        return output
    }
}
