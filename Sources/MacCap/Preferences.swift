import Foundation

/// User-adjustable settings shared by capture and preferences UI.
final class Preferences {
    static let shared = Preferences()
    static let defaultCaptureInterval: TimeInterval = 0.35
    static let minimumCaptureInterval: TimeInterval = 0.15
    static let maximumCaptureInterval: TimeInterval = 1.0

    private enum Key {
        static let shortcut = "MacCap.shortcut"
        static let captureInterval = "MacCap.captureInterval"
        static let maxFrames = "MacCap.maxFrames"
    }

    private let defaults: UserDefaults
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shortcut: KeyboardShortcut {
        get {
            guard
                let data = defaults.data(forKey: Key.shortcut),
                let shortcut = try? decoder.decode(KeyboardShortcut.self, from: data),
                shortcut.hasRequiredModifier
            else {
                return .defaultShortcut
            }
            return shortcut
        }
        set {
            guard newValue.hasRequiredModifier,
                  let data = try? encoder.encode(newValue) else { return }
            defaults.set(data, forKey: Key.shortcut)
        }
    }

    /// Delay between two capture samples, in seconds.
    var captureInterval: TimeInterval {
        get {
            guard defaults.object(forKey: Key.captureInterval) != nil else {
                return Self.defaultCaptureInterval
            }
            return min(
                max(defaults.double(forKey: Key.captureInterval), Self.minimumCaptureInterval),
                Self.maximumCaptureInterval
            )
        }
        set {
            defaults.set(
                min(max(newValue, Self.minimumCaptureInterval), Self.maximumCaptureInterval),
                forKey: Key.captureInterval
            )
        }
    }

    var maxFrames: Int {
        get {
            guard defaults.object(forKey: Key.maxFrames) != nil else { return 300 }
            return min(max(defaults.integer(forKey: Key.maxFrames), 10), 2_000)
        }
        set {
            defaults.set(min(max(newValue, 10), 2_000), forKey: Key.maxFrames)
        }
    }
}
