import AppKit
import CoreGraphics
import Darwin
import Foundation

private func diyplayOnReconfigure(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    let interesting: UInt32 = 0x0000_0001 | 0x0000_0010 | 0x0000_0008 | 0x0000_1000
    guard flags.rawValue & interesting != 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        DisplayControl.applyIfNeeded()
        MenuBarApp.shared.refreshIcon()
    }
}

final class MenuBarApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static let shared = MenuBarApp()
    private var statusItem: NSStatusItem?
    private static var lockFd: Int32 = -1

    static func run() {
        guard acquireSingleton() else { exit(0) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = shared
        CGDisplayRegisterReconfigurationCallback(diyplayOnReconfigure, nil)
        app.run()
    }

    /// launchctl bootstrap / double-click must not create a second status item.
    @discardableResult
    private static func acquireSingleton() -> Bool {
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("com.coraia.diyplay.lock")
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        lockFd = fd
        return true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "diyplay"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        DisplayControl.applyIfNeeded()
        refreshIcon()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild(menu)
    }

    func refreshIcon() {
        let ok = DisplayControl.snapshot()?.healthy ?? false
        let name = ok ? "display" : "exclamationmark.triangle.fill"
        statusItem?.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "diyplay")
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let snap = DisplayControl.snapshot() else {
            menu.addItem(disabled("没有显示器"))
            return
        }

        menu.addItem(disabled(headerTitle(snap)))
        menu.addItem(disabled("识别  \(snap.display.sizeText)    物理  \(snap.native.w)×\(snap.native.h)"))
        menu.addItem(.separator())

        menu.addItem(disabled("物理分辨率"))
        let detected = NSMenuItem(
            title: "用识别到的 \(snap.display.sizeText)",
            action: #selector(useDetected),
            keyEquivalent: ""
        )
        detected.target = self
        if snap.native.w == snap.display.pixelsW, snap.native.h == snap.display.pixelsH, snap.presetId == nil {
            detected.state = .on
        }
        menu.addItem(detected)

        for preset in PresetBank.presets(vendor: snap.display.vendor, product: snap.display.product) {
            let item = NSMenuItem(
                title: "\(preset.title)    \(preset.width)×\(preset.height)",
                action: #selector(pickPreset(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.id
            if snap.presetId == preset.id { item.state = .on }
            menu.addItem(item)
        }

        let custom = NSMenuItem(title: "自定义…", action: #selector(customNative), keyEquivalent: "")
        custom.target = self
        if snap.presetId == nil,
           !(snap.native.w == snap.display.pixelsW && snap.native.h == snap.display.pixelsH)
        {
            custom.state = .on
        }
        menu.addItem(custom)
        menu.addItem(.separator())

        for step in snap.slider {
            let item = NSMenuItem(
                title: "\(step.label)    \(step.w)×\(step.h)",
                action: #selector(pick(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = "\(step.w)x\(step.h)"
            if snap.ui?.pointsW == step.w, snap.ui?.pointsH == step.h {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let fix = NSMenuItem(
            title: snap.healthy ? "重新应用" : "修复",
            action: #selector(fixNow),
            keyEquivalent: ""
        )
        fix.target = self
        menu.addItem(fix)

        let login = NSMenuItem(title: "登录时启动", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func headerTitle(_ snap: Snapshot) -> String {
        if snap.healthy {
            return "\(snap.display.name)  ·  正常"
        }
        return "\(snap.display.name)  ·  物理不匹配"
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func useDetected() {
        guard let d = DisplayControl.activeDisplay() else { return }
        runNative(d, width: d.pixelsW, height: d.pixelsH, presetId: nil)
    }

    @objc private func pickPreset(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let d = DisplayControl.activeDisplay(),
              let preset = PresetBank.presets(vendor: d.vendor, product: d.product).first(where: { $0.id == id })
        else { return }
        runNative(d, width: preset.width, height: preset.height, presetId: preset.id)
    }

    @objc private func customNative() {
        guard let d = DisplayControl.activeDisplay() else { return }
        let native = DisplayControl.selectedNative(d)
        let alert = NSAlert()
        alert.messageText = "物理分辨率"
        alert.informativeText = "按这块屏现在真正在用的像素写，不是 EDID 上的整屏。PBP 裁切后常见 2824x2160 或 1920x2160。"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = "\(native.w)x\(native.h)"
        alert.accessoryView = field
        alert.addButton(withTitle: "设定")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let parts = field.stringValue.lowercased().replacingOccurrences(of: "×", with: "x").split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0].trimmingCharacters(in: .whitespaces)),
              let h = Int(parts[1].trimmingCharacters(in: .whitespaces))
        else {
            self.alert(DisplayError.badSize.localizedDescription)
            return
        }
        runNative(d, width: w, height: h, presetId: nil)
    }

    private func runNative(_ d: DisplayRecord, width: Int, height: Int, presetId: String?) {
        do {
            try DisplayControl.setNative(d, width: width, height: height, presetId: presetId)
        } catch {
            alert(error.localizedDescription)
        }
        refreshIcon()
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard let spec = sender.representedObject as? String else { return }
        let parts = spec.split(separator: "x")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return }
        do {
            try DisplayControl.apply(looksLike: (w, h))
        } catch {
            alert(error.localizedDescription)
        }
        refreshIcon()
    }

    @objc private func fixNow() {
        do {
            guard let d = DisplayControl.activeDisplay() else { return }
            try DisplayControl.apply(looksLike: DisplayControl.preferredUI(d))
        } catch {
            alert(error.localizedDescription)
        }
        refreshIcon()
    }

    @objc private func toggleLogin() {
        LoginItem.isEnabled.toggle()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = "diyplay"
        a.informativeText = message
        a.runModal()
    }
}

enum LoginItem {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.coraia.diyplay.plist")
    }

    static var executable: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    static var isEnabled: Bool {
        get { FileManager.default.fileExists(atPath: plistURL.path) }
        set { newValue ? enable() : disable() }
    }

    private static func enable() {
        let exe = executable
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.coraia.diyplay</string>
          <key>ProgramArguments</key>
          <array>
            <string>\(exe)</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        // Do not `launchctl bootstrap`: RunAtLoad would spawn a second instance
        // and a second menu-bar icon. Login loads ~/Library/LaunchAgents next time.
    }

    private static func disable() {
        // Do not `bootout`: if launchd started us, that would quit this process.
        try? FileManager.default.removeItem(at: plistURL)
    }
}
