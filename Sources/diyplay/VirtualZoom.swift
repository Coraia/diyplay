import AppKit
import CoreGraphics
import Foundation
import VirtualDisplaySupport

/// Intermediate HiDPI sizes by mirroring.
///
/// macOS only builds a HiDPI mode when its 2× backing fits the panel, so a
/// 1920×2160 PBP half never offers e.g. 1600×1800 HiDPI. This renders the
/// desktop on a process-owned 2× virtual display (3200×3600 backing, 1600×1800
/// points) and mirrors it onto the real pane, which downscales it — the same
/// trick BetterDisplay's flexible scaling uses.
final class VirtualZoom {
    static let shared = VirtualZoom()
    private static let domain = "com.coraia.diyplay.virtual-zoom"

    struct Preset: Equatable {
        var w: Int
        var h: Int
        var title: String { "\(w)×\(h)" }
    }

    /// Ordered small canvas → large canvas. Filtered against the physical pane
    /// before being offered.
    static let presets = [
        Preset(w: 1280, h: 1440),
        Preset(w: 1600, h: 1800),
    ]

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
    private(set) var active: Preset?
    private(set) var isChanging = false

    var isActive: Bool { virtual != nil }
    var ownsConfiguration: Bool { isChanging || isActive || !saved.isEmpty }
    var normalDisplayID: CGDirectDisplayID? { ownsConfiguration ? normalDisplay : nil }
    var normalAvailableLooksLike: Set<String>? { ownsConfiguration ? normalModes : nil }

    func enable(_ preset: Preset) throws {
        if isActive {
            if active == preset { return }
            try restore()
        }
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
                try DPVirtualDisplay(width: UInt32(preset.w), height: UInt32(preset.h))
            }
            guard let virtual else { throw DisplayError.noDisplay }
            let id = virtual.displayID
            guard waitUntil({
                DisplayControl.findMode(display: id, pointsW: preset.w, pointsH: preset.h, hiDPI: true) != nil
            }), let mode = DisplayControl.findMode(display: id, pointsW: preset.w, pointsH: preset.h, hiDPI: true)
            else {
                throw NSError(domain: Self.domain, code: 5,
                              userInfo: [NSLocalizedDescriptionKey: "macOS 未提供 \(preset.w)×\(preset.h) HiDPI 模式。"])
            }

            try configure { config in
                try check(CGConfigureDisplayWithDisplayMode(config, id, mode.ref, nil))
                try check(CGConfigureDisplayOrigin(config, id, 0, 0))
                for screen in saved where screen.id == physical || screen.mirror == physical {
                    try check(CGConfigureDisplayMirrorOfDisplay(config, screen.id, id))
                }
            }
            guard waitUntil({
                guard let mode = CGDisplayCopyDisplayMode(id) else { return false }
                return mode.width == preset.w && mode.height == preset.h
                    && CGDisplayMirrorsDisplay(physical) == id
            }) else {
                throw NSError(domain: Self.domain, code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "macOS 未切换到 \(preset.w)×\(preset.h) HiDPI，已尝试恢复原设置。"])
            }
            active = preset
        } catch {
            let originalError = error
            do { try restore() }
            catch {
                throw NSError(domain: Self.domain, code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "\(originalError.localizedDescription)\n恢复原设置失败：\(error.localizedDescription)。请重新选择日常分辨率。"])
            }
            throw originalError
        }
    }

    /// Tear the virtual display down and put the physical pane back.
    func restore() throws {
        guard ownsConfiguration else { return }
        let wasChanging = isChanging
        isChanging = true
        defer { isChanging = wasChanging }
        if let id = virtual?.displayID {
            virtual?.invalidate()
            virtual = nil
            guard waitUntil({ (try? Self.onlineDisplays().contains(id)) == false }) else {
                throw NSError(domain: Self.domain, code: 4,
                              userInfo: [NSLocalizedDescriptionKey: "虚拟屏尚未断开，请再次选择日常分辨率。"])
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
        active = nil
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
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            if let app = NSApp,
               let event = app.nextEvent(matching: [.appKitDefined, .systemDefined, .applicationDefined],
                                         until: Date().addingTimeInterval(0.05),
                                         inMode: .default, dequeue: true) {
                app.sendEvent(event)
            } else {
                usleep(50_000)
            }
        }
        return condition()
    }
}
