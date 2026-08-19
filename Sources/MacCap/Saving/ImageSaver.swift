import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageSaver {
    @MainActor
    static func choosePNGDestination() -> URL? {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSSavePanel()
        panel.title = "保存长截图"
        panel.prompt = "保存"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedFileName()

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try Task.checkCancellation()
        let temporaryURL = url.deletingLastPathComponent().appendingPathComponent(
            ".maccap-\(UUID().uuidString).tmp"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        guard let destination = CGImageDestinationCreateWithURL(
            temporaryURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageSavingError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else {
            throw ImageSavingError.pngEncodingFailed
        }
        try Task.checkCancellation()

        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporaryURL)
        } else {
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        }
    }

    private static func suggestedFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "MacCap-\(formatter.string(from: Date())).png"
    }
}

enum ImageSavingError: LocalizedError {
    case destinationCreationFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .destinationCreationFailed:
            return "无法创建 PNG 文件。"
        case .pngEncodingFailed:
            return "无法编码 PNG 图片。"
        }
    }
}
