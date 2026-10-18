import AppKit
import Foundation

/// Stable UU Remote integration: react only when the user brings the UU app
/// forward. UU's helper processes and network sockets stay alive at login, so
/// neither is a reliable signal that a phone session has started.
final class RemoteCompanion: NSObject {
    static let shared = RemoteCompanion()
    static let uuBundleIdentifier = "com.netease.uuremote"

    private static let enabledKey = "diyplay.remoteCompanion.uu.enabled"
    private let promptCooldown: TimeInterval = 15 * 60
    private var activationHandler: (() -> Void)?
    private var lastPromptAt: Date?
    private var observing = false

    var isEnabled: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Self.enabledKey) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) }
    }

    var uuApplicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.uuBundleIdentifier)
    }

    func start(onActivation: @escaping () -> Void) {
        activationHandler = onActivation
        guard !observing else { return }
        observing = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    func openUU(completion: @escaping (Error?) -> Void) -> Bool {
        guard let url = uuApplicationURL else { return false }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
        return true
    }

    @objc private func applicationActivated(_ notification: Notification) {
        guard isEnabled,
              !PhoneRemote.shared.ownsConfiguration,
              DisplayControl.snapshot() != nil,
              let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.uuBundleIdentifier
        else { return }

        let now = Date()
        if let lastPromptAt, now.timeIntervalSince(lastPromptAt) < promptCooldown { return }
        lastPromptAt = now
        activationHandler?()
    }
}

/// A permission-free native prompt. It floats above UU without stealing focus
/// and behaves like a compact notification, while keeping its actions visible.
final class CompanionPromptController: NSWindowController, NSWindowDelegate {
    private let onSwitch: () -> Void
    private let onKeep: () -> Void
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private(set) var isPresented = false

    init(onSwitch: @escaping () -> Void, onKeep: @escaping () -> Void) {
        self.onSwitch = onSwitch
        self.onKeep = onKeep

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 178),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Diyplay · 远程伴侣"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.becomesKeyOnlyIfNeeded = true
        super.init(window: panel)
        panel.delegate = self

        let content = NSView()
        panel.contentView = content

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(icon)

        let heading = NSTextField(labelWithString: "要切换到手机远程场景吗？")
        heading.font = .systemFont(ofSize: 17, weight: .semibold)
        heading.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(heading)

        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(detailLabel)

        let switchButton = NSButton(title: "切换", target: self, action: #selector(switchToPhone))
        switchButton.bezelStyle = .rounded
        switchButton.keyEquivalent = "\r"
        switchButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(switchButton)

        let keepButton = NSButton(title: "保持当前", target: self, action: #selector(keepCurrent))
        keepButton.bezelStyle = .rounded
        keepButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(keepButton)

        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            icon.widthAnchor.constraint(equalToConstant: 54),
            icon.heightAnchor.constraint(equalToConstant: 54),
            heading.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 14),
            heading.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            detailLabel.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 7),
            switchButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            switchButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            switchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
            keepButton.trailingAnchor.constraint(equalTo: switchButton.leadingAnchor, constant: -10),
            keepButton.centerYAnchor.constraint(equalTo: switchButton.centerYAnchor),
            keepButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(displayName: String) {
        guard let window else { return }
        detailLabel.stringValue = "UU 远程已打开。将 \(displayName) 切为 720×1560 竖屏。"
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        window.setFrameOrigin(NSPoint(x: frame.maxX - window.frame.width - 18,
                                      y: frame.maxY - window.frame.height - 18))
        isPresented = true
        window.orderFrontRegardless()
    }

    func dismiss() {
        isPresented = false
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        isPresented
    }

    func bringForward() {
        guard isPresented else { return }
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        isPresented = false
    }

    @objc private func switchToPhone() {
        dismiss()
        onSwitch()
    }

    @objc private func keepCurrent() {
        dismiss()
        onKeep()
    }
}
