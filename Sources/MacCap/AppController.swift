import AppKit
import ApplicationServices
import MacCapCore

@MainActor
final class AppController: NSObject {
    private static let maximumFramePixels = 10_000_000
    private static let maximumOutputPixels = 20_000_000
    private static let maximumOutputHeight = 30_000
    private static let maximumCaptureDurationSeconds = 120

    private enum State {
        case idle
        case selecting
        case preparing
        case capturing
        case saving
    }

    private let preferences = Preferences.shared
    private let selectionOverlay = SelectionOverlayController()
    private let captureService = ScreenCaptureService()

    private var state: State = .idle
    private var stopRequested = false
    private var captureTask: Task<Void, Never>?
    private var lastTargetPID: pid_t?

    private var statusItem: NSStatusItem?
    private var captureMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var hotKeyManager: GlobalHotKeyManager?
    private var preferencesWindowController: PreferencesWindowController?
    private var captureHUD: CaptureHUDController?

    func start() {
        rememberFrontmostApplication()
        observeApplicationChanges()
        configureStatusItem()

        let manager = GlobalHotKeyManager { [weak self] in
            Task { @MainActor in self?.toggleCapture() }
        }
        hotKeyManager = manager
        updateMenuState()

        if let startupError = manager.startupError {
            Task { @MainActor [weak self] in
                self?.showError(startupError, title: "快捷键不可用")
            }
        }
    }

    func stop() {
        captureTask?.cancel()
        selectionOverlay.cancel()
        captureHUD?.close()
        captureTask = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        hotKeyManager = nil
    }

    @objc private func captureMenuPressed() {
        toggleCapture()
    }

    @objc private func showPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                preferences: preferences
            ) { [weak self] shortcut in
                guard let self, let manager = self.hotKeyManager else { return }
                try manager.register(shortcut)
                self.updateMenuState()
            }
        }
        preferencesWindowController?.showWindow(nil)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "camera.viewfinder",
                accessibilityDescription: "MacCap 长截图"
            )
            button.toolTip = "MacCap 长截图"
        }

        let menu = NSMenu()
        let captureItem = NSMenuItem(
            title: "开始长截图",
            action: #selector(captureMenuPressed),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        settingsItem.keyEquivalentModifierMask = .command
        settingsItem.target = self
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(
            title: "关于 MacCap",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 MacCap",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = .command
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
        captureMenuItem = captureItem
        settingsMenuItem = settingsItem
    }

    private func updateMenuState() {
        let shortcut = hotKeyManager?.registeredShortcut ?? preferences.shortcut
        switch state {
        case .idle:
            captureMenuItem?.title = "开始长截图（\(shortcut.displayString)）"
            captureMenuItem?.isEnabled = true
            settingsMenuItem?.isEnabled = true
        case .selecting:
            captureMenuItem?.title = "取消框选（Esc）"
            captureMenuItem?.isEnabled = true
            settingsMenuItem?.isEnabled = false
        case .preparing:
            captureMenuItem?.title = "取消准备"
            captureMenuItem?.isEnabled = true
            settingsMenuItem?.isEnabled = false
        case .capturing:
            captureMenuItem?.title = "停止长截图（\(shortcut.displayString)）"
            captureMenuItem?.isEnabled = true
            settingsMenuItem?.isEnabled = false
        case .saving:
            captureMenuItem?.title = "正在生成 PNG…"
            captureMenuItem?.isEnabled = false
            settingsMenuItem?.isEnabled = false
        }
    }

    private func toggleCapture() {
        switch state {
        case .idle:
            guard captureTask == nil else { return }
            stopRequested = false
            captureTask = Task { @MainActor [weak self] in
                await self?.runCapture()
            }
        case .selecting:
            selectionOverlay.cancel()
        case .preparing:
            captureTask?.cancel()
        case .capturing:
            requestStop()
        case .saving:
            NSSound.beep()
        }
    }

    private func requestStop() {
        guard state == .capturing else { return }
        stopRequested = true
        captureHUD?.update(status: "正在停止…")
        updateMenuState()
    }

    private func cancelPreparationOrStop() {
        if state == .preparing {
            captureHUD?.update(status: "正在取消…")
            captureTask?.cancel()
        } else {
            requestStop()
        }
    }

    private func runCapture() async {
        defer {
            captureService.invalidate()
            captureHUD?.close()
            captureHUD = nil
            state = .idle
            captureTask = nil
            stopRequested = false
            updateMenuState()
        }

        let fallbackTargetPID = captureTargetPID()
        guard ensurePermissions() else { return }

        state = .selecting
        updateMenuState()
        guard let region = await selectionOverlay.selectRegion(), !Task.isCancelled else {
            return
        }
        guard let outputHeightLimit = outputHeightLimit(for: region) else {
            showMessage(
                title: "选区过大",
                message: "为限制内存占用，单帧最多允许 1000 万像素。当前选区为 \(region.pixelWidth) × \(region.pixelHeight) px，请缩小选区后重试。"
            )
            return
        }

        guard let targetApplication = targetApplication(
            primaryPID: targetPID(at: region.scrollPoint),
            fallbackPID: fallbackTargetPID
        ) else {
            showMessage(
                title: "找不到目标应用",
                message: "请先点击需要滚动截图的应用，再按长截图快捷键。"
            )
            return
        }

        state = .preparing
        updateMenuState()

        guard targetApplication.activate(options: [.activateIgnoringOtherApps]) else {
            showMessage(
                title: "无法激活目标应用",
                message: "请确认目标应用仍在运行，然后重新框选。"
            )
            return
        }
        let targetPID = targetApplication.processIdentifier
        try? await Task.sleep(nanoseconds: 180_000_000)
        guard !Task.isCancelled else { return }

        let hud = CaptureHUDController { [weak self] in
            self?.cancelPreparationOrStop()
        }
        captureHUD = hud
        hud.show(
            on: screen(for: region.displayID),
            status: "正在准备截图…",
            detail: ""
        )

        let driver: ScrollDriver
        do {
            driver = try ScrollDriver(targetPID: targetPID)
            try driver.prepare(at: region.scrollPoint)
            try await captureService.prepare(for: region.displayID)
        } catch {
            if Task.isCancelled { return }
            hud.close()
            showError(error, title: "无法开始长截图")
            return
        }
        defer { _ = driver.restoreCursor() }
        guard !Task.isCancelled else { return }

        hud.update(status: "正在生成长截图…", detail: "已截取 0 帧")
        state = .capturing
        updateMenuState()

        let stitcher = StitchingWorker(
            stitcher: makeStitcher(
                for: region,
                maximumOutputHeight: outputHeightLimit
            ),
            maximumFramePixels: Self.maximumFramePixels
        )
        var earlyStopMessage: String?
        var capturedFrameCount = 0
        let clock = ContinuousClock()
        let captureDeadline = clock.now.advanced(
            by: .seconds(Self.maximumCaptureDurationSeconds)
        )

        do {
            let firstCapture = try await captureService.capture(region: region)
            guard !stopRequested, !Task.isCancelled else { return }
            _ = try await stitcher.append(firstCapture)
            capturedFrameCount = 1
            hud.update(capturedFrameCount: capturedFrameCount)
        } catch {
            showError(error, title: "第一帧截图失败")
            return
        }

        let maximumFrames = preferences.maxFrames
        let scrollAmount = Int32(max(12, min(600, region.sourceRect.height * 0.68)))

        while capturedFrameCount < maximumFrames,
              !stopRequested,
              !Task.isCancelled {
            if clock.now >= captureDeadline {
                earlyStopMessage = "已达到 120 秒捕获时长上限。"
                break
            }
            do {
                try driver.postScrollDown(points: scrollAmount)
                try await sleepForCaptureInterval()
                guard !stopRequested, !Task.isCancelled else { break }

                let capture = try await captureService.capture(region: region)
                guard !stopRequested, !Task.isCancelled else { break }
                capturedFrameCount += 1

                do {
                    let result = try await stitcher.append(capture)
                    hud.update(capturedFrameCount: capturedFrameCount)
                    if case .reachedBottom = result { break }
                } catch let error as VerticalMatchError {
                    earlyStopMessage = error.localizedDescription
                    break
                } catch let error as LongScreenshotError {
                    earlyStopMessage = error.localizedDescription
                    break
                }
            } catch is CancellationError {
                break
            } catch {
                earlyStopMessage = error.localizedDescription
                break
            }
        }

        let reachedBottom = await stitcher.hasReachedBottom()
        if capturedFrameCount >= maximumFrames, !reachedBottom {
            earlyStopMessage = "已达到设置中的最大帧数（\(maximumFrames)）。"
        }

        guard let stitched = await stitcher.takeOutput() else { return }
        _ = driver.restoreCursor()
        state = .saving
        updateMenuState()
        hud.close()

        guard let savedURL = ImageSaver.choosePNGDestination() else { return }
        hud.show(
            on: screen(for: region.displayID),
            status: "正在写入 PNG…",
            detail: "\(stitched.width) × \(stitched.height) px"
        )

        do {
            let saveTask = Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                try autoreleasepool {
                    let image = try CGImageBridge.cgImage(from: stitched)
                    try Task.checkCancellation()
                    try ImageSaver.writePNG(image, to: savedURL)
                }
            }
            try await withTaskCancellationHandler {
                try await saveTask.value
            } onCancel: {
                saveTask.cancel()
            }
            hud.close()
            NSSound(named: "Glass")?.play()
            if let earlyStopMessage, !stopRequested {
                showMessage(
                    title: "长截图已提前结束",
                    message: "已保存可靠拼接的部分：\(savedURL.lastPathComponent)\n\n\(earlyStopMessage)"
                )
            }
        } catch is CancellationError {
            return
        } catch {
            showError(error, title: "保存失败")
        }
    }

    private func outputHeightLimit(for region: CaptureRegion) -> Int? {
        guard region.pixelWidth > 0, region.pixelHeight > 0 else { return nil }
        let (framePixels, overflow) = region.pixelWidth.multipliedReportingOverflow(
            by: region.pixelHeight
        )
        guard !overflow, framePixels <= Self.maximumFramePixels else { return nil }

        let pixelBudgetHeight = Self.maximumOutputPixels / region.pixelWidth
        let limit = min(Self.maximumOutputHeight, pixelBudgetHeight)
        return limit >= region.pixelHeight ? limit : nil
    }

    private func makeStitcher(
        for region: CaptureRegion,
        maximumOutputHeight: Int
    ) -> LongScreenshotStitcher {
        let frameHeight = region.pixelHeight
        let match = VerticalMatchConfiguration(
            minimumDisplacement: max(2, frameHeight / 250),
            maximumDisplacement: max(3, Int(Double(frameHeight) * 0.90)),
            minimumOverlapRows: max(24, frameHeight / 10),
            targetSampleCountPerCandidate: 1_024,
            minimumConfidence: 0.94
        )
        return LongScreenshotStitcher(
            configuration: LongScreenshotConfiguration(
                match: match,
                maximumOutputHeight: maximumOutputHeight,
                identicalFrameMaximumMeanError: 0
            )
        )
    }

    private func sleepForCaptureInterval() async throws {
        let nanoseconds = UInt64(preferences.captureInterval * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func ensurePermissions() -> Bool {
        var permissions = CapturePermissions.current
        if !permissions.screenRecording {
            _ = CapturePermissions.requestScreenRecordingAccess()
        }
        if !permissions.accessibility {
            _ = CapturePermissions.requestAccessibilityAccess()
        }
        permissions = CapturePermissions.current
        guard permissions.allGranted else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要系统权限"
            var missing: [String] = []
            if !permissions.screenRecording { missing.append("屏幕与系统音频录制") }
            if !permissions.accessibility { missing.append("辅助功能") }
            alert.informativeText = "请在系统设置的“隐私与安全性”中允许 MacCap 使用：\(missing.joined(separator: "、"))。授权屏幕录制后可能需要重新启动 MacCap。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                if !permissions.screenRecording {
                    CapturePermissions.openScreenRecordingSettings()
                } else {
                    CapturePermissions.openAccessibilitySettings()
                }
            }
            return false
        }
        return true
    }

    private func captureTargetPID() -> pid_t? {
        rememberFrontmostApplication()
        return lastTargetPID
    }

    /// Resolves the application underneath the selected scroll point. This
    /// keeps menu-bar invocation and multi-window workflows from scrolling a
    /// previously focused, unrelated application.
    private func targetPID(at point: CGPoint) -> pid_t? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        let copyStatus = AXUIElementCopyElementAtPosition(
            systemWideElement,
            Float(point.x),
            Float(point.y),
            &element
        )
        guard copyStatus == .success, let element else { return nil }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              pid > 0,
              pid != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return pid
    }

    private func targetApplication(
        primaryPID: pid_t?,
        fallbackPID: pid_t?
    ) -> NSRunningApplication? {
        for pid in [primaryPID, fallbackPID].compactMap({ $0 }) {
            guard let application = NSRunningApplication(processIdentifier: pid),
                  !application.isTerminated,
                  application.activationPolicy != .prohibited,
                  application.processIdentifier
                    != ProcessInfo.processInfo.processIdentifier else {
                continue
            }
            return application
        }
        return nil
    }

    private func rememberFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        remember(application)
    }

    private func remember(_ application: NSRunningApplication) {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        guard application.processIdentifier != ownPID,
              application.bundleIdentifier != "com.apple.systemuiserver",
              !application.isTerminated,
              application.activationPolicy != .prohibited else {
            return
        }
        lastTargetPID = application.processIdentifier
    }

    private func observeApplicationChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func applicationDidActivate(_ notification: Notification) {
        guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else {
            return
        }
        remember(application)
    }

    @objc private func screenParametersDidChange(_ notification: Notification) {
        captureService.invalidate()
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
    }

    private func showError(_ error: Error, title: String) {
        showMessage(title: title, message: error.localizedDescription)
    }

    private func showMessage(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

extension VerticalMatchError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "拼接参数无效。"
        case .dimensionMismatch:
            return "滚动过程中截图区域尺寸发生了变化。"
        case .noCandidateDisplacement:
            return "没有找到足够的重叠区域。"
        case let .lowConfidence(best, required):
            return String(
                format: "页面变化较大，无法可靠拼接（置信度 %.1f%%，需要 %.1f%%）。",
                best * 100,
                required * 100
            )
        case .ambiguousMatch:
            return "页面包含大量重复内容，无法唯一确定滚动位置。"
        }
    }
}

extension LongScreenshotError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "长截图参数无效。"
        case .frameDimensionMismatch:
            return "滚动过程中截图区域尺寸发生了变化。"
        case let .maximumHeightExceeded(limit, _):
            return "长图已达到安全高度上限（\(limit) 像素）。"
        }
    }
}
