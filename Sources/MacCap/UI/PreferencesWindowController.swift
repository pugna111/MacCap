import AppKit

final class PreferencesWindowController: NSWindowController, NSTextFieldDelegate {
    typealias ShortcutChangeHandler = (KeyboardShortcut) throws -> Void

    private let preferences: Preferences
    private let onShortcutChanged: ShortcutChangeHandler
    private let shortcutRecorder: ShortcutRecorderControl
    private let validationLabel = NSTextField(labelWithString: "")
    private let intervalField: NSTextField
    private let intervalStepper: NSStepper
    private let maxFramesField: NSTextField
    private let maxFramesStepper: NSStepper

    init(
        preferences: Preferences = .shared,
        onShortcutChanged: @escaping ShortcutChangeHandler
    ) {
        self.preferences = preferences
        self.onShortcutChanged = onShortcutChanged
        shortcutRecorder = ShortcutRecorderControl(shortcut: preferences.shortcut)
        intervalField = NSTextField(string: String(format: "%.2f", preferences.captureInterval))
        intervalStepper = NSStepper()
        maxFramesField = NSTextField(string: String(preferences.maxFrames))
        maxFramesStepper = NSStepper()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 255),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureWindow() {
        guard let window else { return }
        window.title = "MacCap 设置"
        window.isReleasedWhenClosed = false

        let contentView = NSView()
        window.contentView = contentView

        let shortcutLabel = NSTextField(labelWithString: "全局快捷键：")
        let intervalLabel = NSTextField(labelWithString: "捕获间隔：")
        let maxFramesLabel = NSTextField(labelWithString: "最大帧数：")

        configureNumberControls()

        let intervalControls = makeNumberRow(
            field: intervalField,
            suffix: "秒",
            stepper: intervalStepper
        )
        let maxFramesControls = makeNumberRow(
            field: maxFramesField,
            suffix: "帧",
            stepper: maxFramesStepper
        )

        let grid = NSGridView(views: [
            [shortcutLabel, shortcutRecorder],
            [intervalLabel, intervalControls],
            [maxFramesLabel, maxFramesControls]
        ])
        grid.columnSpacing = 16
        grid.rowSpacing = 14
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).xPlacement = .leading

        let hintLabel = NSTextField(
            labelWithString: "点击快捷键框后录制；组合键需包含 ⌘ 或 ⌃。"
        )
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.font = .systemFont(ofSize: 11)

        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 11)
        validationLabel.lineBreakMode = .byTruncatingTail

        let doneButton = NSButton(
            title: "完成",
            target: self,
            action: #selector(closeWindow)
        )
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [NSView(), doneButton])
        buttonRow.orientation = .horizontal

        let stack = NSStackView(views: [grid, hintLabel, validationLabel, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
            grid.widthAnchor.constraint(equalTo: stack.widthAnchor),
            validationLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 14),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        shortcutRecorder.onShortcutChange = { [weak self] shortcut in
            guard let self else { return }
            try self.onShortcutChanged(shortcut)
            self.preferences.shortcut = shortcut
        }
        shortcutRecorder.onValidationMessage = { [weak self] message in
            self?.validationLabel.stringValue = message ?? ""
        }
    }

    private func configureNumberControls() {
        let decimalFormatter = NumberFormatter()
        decimalFormatter.numberStyle = .decimal
        decimalFormatter.minimum = NSNumber(value: Preferences.minimumCaptureInterval)
        decimalFormatter.maximum = NSNumber(value: Preferences.maximumCaptureInterval)
        decimalFormatter.minimumFractionDigits = 2
        decimalFormatter.maximumFractionDigits = 2

        intervalField.formatter = decimalFormatter
        intervalField.delegate = self
        intervalField.alignment = .right
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged)
        intervalField.widthAnchor.constraint(equalToConstant: 66).isActive = true

        intervalStepper.minValue = Preferences.minimumCaptureInterval
        intervalStepper.maxValue = Preferences.maximumCaptureInterval
        intervalStepper.increment = 0.01
        intervalStepper.doubleValue = preferences.captureInterval
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged)

        let integerFormatter = NumberFormatter()
        integerFormatter.numberStyle = .none
        integerFormatter.minimum = 10
        integerFormatter.maximum = 2_000
        integerFormatter.allowsFloats = false

        maxFramesField.formatter = integerFormatter
        maxFramesField.delegate = self
        maxFramesField.alignment = .right
        maxFramesField.target = self
        maxFramesField.action = #selector(maxFramesFieldChanged)
        maxFramesField.widthAnchor.constraint(equalToConstant: 66).isActive = true

        maxFramesStepper.minValue = 10
        maxFramesStepper.maxValue = 2_000
        maxFramesStepper.increment = 10
        maxFramesStepper.integerValue = preferences.maxFrames
        maxFramesStepper.target = self
        maxFramesStepper.action = #selector(maxFramesStepperChanged)
    }

    private func makeNumberRow(
        field: NSTextField,
        suffix: String,
        stepper: NSStepper
    ) -> NSView {
        let suffixLabel = NSTextField(labelWithString: suffix)
        let stack = NSStackView(views: [field, suffixLabel, stepper])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === intervalField {
            commitIntervalField()
        } else if field === maxFramesField {
            commitMaxFramesField()
        }
    }

    @objc private func intervalFieldChanged() {
        commitIntervalField()
    }

    @objc private func intervalStepperChanged() {
        preferences.captureInterval = intervalStepper.doubleValue
        intervalField.stringValue = String(format: "%.2f", preferences.captureInterval)
    }

    @objc private func maxFramesFieldChanged() {
        commitMaxFramesField()
    }

    @objc private func maxFramesStepperChanged() {
        preferences.maxFrames = maxFramesStepper.integerValue
        maxFramesField.integerValue = preferences.maxFrames
    }

    @objc private func closeWindow() {
        commitIntervalField()
        commitMaxFramesField()
        window?.performClose(nil)
    }

    private func commitIntervalField() {
        let value = intervalField.doubleValue
        preferences.captureInterval = value
        intervalStepper.doubleValue = preferences.captureInterval
        intervalField.stringValue = String(format: "%.2f", preferences.captureInterval)
    }

    private func commitMaxFramesField() {
        preferences.maxFrames = maxFramesField.integerValue
        maxFramesStepper.integerValue = preferences.maxFrames
        maxFramesField.integerValue = preferences.maxFrames
    }
}
