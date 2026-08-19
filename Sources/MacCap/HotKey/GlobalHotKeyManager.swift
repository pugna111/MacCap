import Carbon.HIToolbox
import Foundation

enum GlobalHotKeyError: LocalizedError {
    case modifierRequired
    case eventHandlerInstallationFailed(OSStatus)
    case eventHandlerUnavailable
    case registrationFailed(OSStatus)
    case previousRegistrationCouldNotBeRemoved(OSStatus)

    var errorDescription: String? {
        switch self {
        case .modifierRequired:
            return "快捷键必须包含 Command 或 Control。"
        case .eventHandlerInstallationFailed(let status):
            return "无法监听全局快捷键（错误码 \(status)）。"
        case .eventHandlerUnavailable:
            return "全局快捷键监听器不可用。"
        case .registrationFailed(let status) where status == -9878:
            return "这个快捷键已被系统或其他应用占用。"
        case .registrationFailed(let status):
            return "无法注册这个快捷键（错误码 \(status)）。"
        case .previousRegistrationCouldNotBeRemoved(let status):
            return "无法替换当前快捷键（错误码 \(status)）。"
        }
    }
}

/// Own this object for as long as the application needs its global shortcut.
final class GlobalHotKeyManager {
    private static let signature: OSType = 0x4D_434150 // "MCAP"

    private let onPressed: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?
    private var activeHotKeyID: UInt32?
    private var nextHotKeyID: UInt32 = 1

    private(set) var registeredShortcut: KeyboardShortcut?
    private(set) var startupError: GlobalHotKeyError?

    /// Installs the Carbon handler and registers the saved shortcut immediately.
    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed

        do {
            try installEventHandler()
            try register(Preferences.shared.shortcut)
        } catch let error as GlobalHotKeyError {
            startupError = error
        } catch {
            startupError = .eventHandlerUnavailable
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Atomically replaces the current shortcut.
    ///
    /// The old registration is kept when Carbon rejects the proposed shortcut.
    func register(_ shortcut: KeyboardShortcut) throws {
        guard shortcut.hasRequiredModifier else {
            throw GlobalHotKeyError.modifierRequired
        }
        guard eventHandlerRef != nil else {
            throw GlobalHotKeyError.eventHandlerUnavailable
        }
        if shortcut == registeredShortcut, hotKeyRef != nil {
            return
        }

        let candidateID = takeNextHotKeyID()
        let carbonID = EventHotKeyID(
            signature: Self.signature,
            id: candidateID
        )
        var candidateRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            carbonID,
            GetApplicationEventTarget(),
            0,
            &candidateRef
        )

        guard status == noErr, let candidateRef else {
            throw GlobalHotKeyError.registrationFailed(status)
        }

        if let oldRef = hotKeyRef {
            let unregisterStatus = UnregisterEventHotKey(oldRef)
            guard unregisterStatus == noErr else {
                UnregisterEventHotKey(candidateRef)
                throw GlobalHotKeyError.previousRegistrationCouldNotBeRemoved(unregisterStatus)
            }
        }

        hotKeyRef = candidateRef
        activeHotKeyID = candidateID
        registeredShortcut = shortcut
        Preferences.shared.shortcut = shortcut
        startupError = nil
    }

    private func installEventHandler() throws {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            globalHotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard status == noErr else {
            throw GlobalHotKeyError.eventHandlerInstallationFailed(status)
        }
    }

    private func takeNextHotKeyID() -> UInt32 {
        let result = nextHotKeyID
        nextHotKeyID &+= 1
        if nextHotKeyID == 0 { nextHotKeyID = 1 }
        return result
    }

    fileprivate func handle(hotKeyID: EventHotKeyID) {
        guard let activeHotKeyID,
              hotKeyID.signature == Self.signature,
              hotKeyID.id == activeHotKeyID else { return }
        onPressed()
    }
}

private let globalHotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let manager = Unmanaged<GlobalHotKeyManager>
        .fromOpaque(userData)
        .takeUnretainedValue()
    manager.handle(hotKeyID: hotKeyID)
    return noErr
}
