import AppKit
import CoreGraphics
import Foundation
import VirtualDisplaySupport

/// A temporary portrait desktop mirrored onto the existing screen. Physical
/// pixel overrides and the user's normal HiDPI preference remain independent.
final class PhoneRemote {
    static let shared = PhoneRemote()
    static let width = 720
    static let height = 1560
    static let title = "手机远程    720×1560（竖屏）"

    private struct SavedDisplay {
        var id: CGDirectDisplayID
        var mode: CGDisplayMode
        var origin: CGPoint
        var mirror: CGDirectDisplayID
    }

    private var virtual: DPVirtualDisplay?
    private var saved: [SavedDisplay] = []
    private var normalDisplay: CGDirectDisplayID?
    private var normalModes: Set<String>?
    private(set) var isChanging = false

    var isActive: Bool { virtual != nil }
    var ownsConfiguration: Bool { isChanging || isActive || !saved.isEmpty }
    var normalDisplayID: CGDirectDisplayID? {
        ownsConfiguration ? normalDisplay : nil
    }
    var normalAvailableLooksLike: Set<String>? {
        ownsConfiguration ? normalModes : nil
    }

    func enable() throws {
        guard !isActive else { return }
        if !saved.isEmpty { try restore() }
        guard let physical = DisplayControl.mainExternalDisplay() else { throw DisplayError.noDisplay }
        saved = try Self.onlineDisplays().map { id in
            guard let mode = CGDisplayCopyDisplayMode(id) else { throw DisplayError.noDisplay }
            return SavedDisplay(id: id, mode: mode, origin: CGDisplayBounds(id).origin,
                                mirror: CGDisplayMirrorsDisplay(id))
        }
        normalDisplay = physical
        normalModes = DisplayControl.availableLooksLike(display: physical)
        isChanging = true
        defer { isChanging = false }
        do {
            virtual = try autoreleasepool {
                try DPVirtualDisplay(width: UInt32(Self.width), height: UInt32(Self.height))
            }
            guard let virtual else { throw DisplayError.noDisplay }
            let id = virtual.displayID
            guard waitUntil({ DisplayControl.findMode(display: id, pointsW: Self.width, pointsH: Self.height) != nil }),
                  let mode = DisplayControl.findMode(display: id, pointsW: Self.width, pointsH: Self.height)
            else {
                throw NSError(domain: "com.coraia.diyplay.phone-remote", code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "macOS 未提供 720×1560 手机竖屏模式。"])
            }

            try configure { config in
                try check(CGConfigureDisplayWithDisplayMode(config, id, mode.ref, nil))
                try check(CGConfigureDisplayOrigin(config, id, 0, 0))
                // All existing mirrors of the main display should keep showing
                // the same desktop, now rendered by the portrait source.
                for screen in saved where screen.id == physical || screen.mirror == physical {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, id))
                }
            }
            guard waitUntil({
                guard let mode = CGDisplayCopyDisplayMode(CGMainDisplayID()) else { return false }
                return mode.width == Self.width && mode.height == Self.height
                    && CGDisplayMirrorsDisplay(physical) == id
            }) else {
                throw NSError(domain: "com.coraia.diyplay.phone-remote", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "macOS 未切换到手机竖屏桌面，已尝试恢复原设置。"])
            }
        } catch {
            let originalError = error
            do { try restore() }
            catch {
                throw NSError(domain: "com.coraia.diyplay.phone-remote", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "\(originalError.localizedDescription)\n恢复原设置失败：\(error.localizedDescription)。请重新选择日常分辨率。"])
            }
            throw originalError
        }
    }

    /// Restore the captured layout before a normal preset applies its own size.
    /// Retain the snapshot on failure so the next selection can retry recovery.
    func restore() throws {
        guard ownsConfiguration else { return }
        let wasChanging = isChanging
        isChanging = true
        defer { isChanging = wasChanging }
        if let id = virtual?.displayID {
            virtual?.invalidate()
            virtual = nil
            guard waitUntil({ (try? Self.onlineDisplays().contains(id)) == false }) else {
                throw NSError(domain: "com.coraia.diyplay.phone-remote", code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "手机竖屏尚未断开，请再次选择日常分辨率。"])
            }
        }
        let online = try Self.onlineDisplays()
        let connected = saved.filter { online.contains($0.id) }
        if !connected.isEmpty {
            try configure { config in
                for screen in connected {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, kCGNullDirectDisplay))
                    try check(CGConfigureDisplayWithDisplayMode(config, screen.id, screen.mode, nil))
                    try check(CGConfigureDisplayOrigin(config, screen.id,
                                                      Int32(screen.origin.x), Int32(screen.origin.y)))
                }
                for screen in connected where online.contains(screen.mirror) {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, screen.mirror))
                }
            }
        }
        saved = []
        normalDisplay = nil
        normalModes = nil
    }

    private static func onlineDisplays() throws -> [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        let error = CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count)
        guard error == .success else { throw DisplayError.configure(error) }
        return Array(ids.prefix(Int(count)))
    }

    private func configure(_ body: (CGDisplayConfigRef) throws -> Void) throws {
        var config: CGDisplayConfigRef?
        let error = CGBeginDisplayConfiguration(&config)
        guard error == .success, let config else { throw DisplayError.configure(error) }
        do { try body(config) }
        catch {
            CGCancelDisplayConfiguration(config)
            throw error
        }
        try check(CGCompleteDisplayConfiguration(config, .forSession))
    }

    private func check(_ error: CGError) throws {
        guard error == .success else { throw DisplayError.configure(error) }
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            // AppKit must consume display-change events to invalidate the
            // CoreGraphics mode cache. A RunLoop sleep alone leaves it stale.
            // Keep user input queued while the display configuration changes.
            if let event = NSApp.nextEvent(matching: [.appKitDefined, .systemDefined, .applicationDefined],
                                           until: Date().addingTimeInterval(0.05),
                                           inMode: .default, dequeue: true) {
                NSApp.sendEvent(event)
            }
        }
        return condition()
    }
}
