import AppKit
import CoreGraphics

/// An independent entry point that stays usable when the menu bar is crowded.
final class ResolutionPanelController: NSWindowController {
    static let windowTitle = "Diyplay · 分辨率"

    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let scrollView = NSScrollView()
    private let choicesView = FlippedView()
    private let onSelect: (NSMenuItem) -> Void
    private var items: [NSMenuItem] = []

    init(onSelect: @escaping (NSMenuItem) -> Void) {
        self.onSelect = onSelect
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 410),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = Self.windowTitle
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)

        let content = NSView()
        panel.contentView = content
        let heading = NSTextField(labelWithString: "选择分辨率")
        heading.font = .systemFont(ofSize: 22, weight: .semibold)
        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabelColor
        let hint = NSTextField(wrappingLabelWithString: "选择日常等原有档位，即可退出手机远程。\n关闭面板不会改变当前分辨率。")
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = .secondaryLabelColor

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = choicesView
        for view in [heading, statusLabel, scrollView, hint] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
            view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20).isActive = true
            view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20).isActive = true
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            statusLabel.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 6),
            scrollView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: hint.topAnchor, constant: -12),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(status: String, items: [NSMenuItem], isChanging: Bool) {
        self.items = items
        statusLabel.stringValue = isChanging ? "正在切换分辨率…" : status
        guard let window else { return }
        let available = displayFrame
        let width = min(480, available.width - 32)
        let height = min(CGFloat(150 + items.count * 54), available.height - 64)
        window.setContentSize(NSSize(width: width, height: height))
        window.contentView?.layoutSubtreeIfNeeded()
        choicesView.subviews.forEach { $0.removeFromSuperview() }
        choicesView.frame = NSRect(x: 0, y: 0, width: scrollView.contentSize.width, height: CGFloat(items.count * 54))
        for (index, item) in items.enumerated() {
            let button = NSButton(title: item.title, target: self, action: #selector(selectResolution(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.controlSize = .large
            button.font = .systemFont(ofSize: 16)
            button.alignment = .left
            button.image = NSImage(systemSymbolName: item.state == .on ? "checkmark.circle.fill" : "circle",
                                   accessibilityDescription: item.state == .on ? "当前分辨率" : nil)
            button.imagePosition = .imageLeading
            button.contentTintColor = item.state == .on ? .controlAccentColor : .labelColor
            button.isEnabled = item.isEnabled && !isChanging
            button.toolTip = item.toolTip
            button.frame = NSRect(x: 0, y: CGFloat(index * 54), width: choicesView.bounds.width, height: 46)
            button.autoresizingMask = [.width]
            choicesView.addSubview(button)
        }
        keepOnScreen(center: false)
    }

    func present() {
        guard let window else { return }
        keepOnScreen(center: true)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private var displayFrame: NSRect {
        let mainID = CGMainDisplayID()
        return NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == mainID
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 720, height: 1280)
    }

    private func keepOnScreen(center: Bool) {
        guard let window else { return }
        let available = displayFrame
        let frame = window.frame
        let x = center ? available.midX - frame.width / 2 : frame.minX
        let y = center ? available.midY - frame.height / 2 : frame.minY
        window.setFrameOrigin(NSPoint(x: min(max(x, available.minX), available.maxX - frame.width),
                                      y: min(max(y, available.minY), available.maxY - frame.height)))
    }

    @objc private func selectResolution(_ sender: NSButton) {
        guard items.indices.contains(sender.tag), sender.isEnabled else { return }
        let selected = items[sender.tag]
        choicesView.subviews.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = false }
        onSelect(selected)
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
