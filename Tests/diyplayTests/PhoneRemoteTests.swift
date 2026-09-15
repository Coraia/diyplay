import AppKit
import CoreGraphics
import XCTest
@testable import diyplay

final class PhoneRemoteTests: XCTestCase {
    func testPortraitPresetFitsBothPhones() {
        let ratio = Double(PhoneRemote.height) / Double(PhoneRemote.width)
        XCTAssertGreaterThan(ratio, 2)
        XCTAssertGreaterThanOrEqual(PhoneRemote.width, 640)
        for phoneRatio in [2556.0 / 1179, 2670.0 / 1200] {
            let fractionFilled = min(ratio, phoneRatio) / max(ratio, phoneRatio)
            XCTAssertGreaterThan(fractionFilled, 0.97)
        }
    }

    /// Opt-in because this actually changes the attached display, then restores
    /// its starting mode. Stop the installed app first to avoid its older repair
    /// callback undoing the test's temporary configuration.
    @MainActor
    func testLivePortraitAndReturnThroughNormalResolution() async throws {
        guard ProcessInfo.processInfo.environment["DIYPLAY_LIVE_DISPLAY_TEST"] == "1" else {
            throw XCTSkip("Set DIYPLAY_LIVE_DISPLAY_TEST=1 for the reversible on-device check.")
        }
        _ = NSApplication.shared
        let display = try XCTUnwrap(DisplayControl.activeDisplay())
        let initial = try XCTUnwrap(DisplayControl.currentUI())
        let initialMain = CGMainDisplayID()
        let overrideURL = URL(fileURLWithPath: OverrideFile.path(vendor: display.vendor, product: display.product))
        let initialOverride = try? Data(contentsOf: overrideURL)
        let initialDefaults = UserDefaults.standard.dictionaryRepresentation().filter { $0.key.hasPrefix("diyplay.") }
        defer {
            try? PhoneRemote.shared.restore()
            try? DisplayControl.apply(looksLike: (initial.pointsW, initial.pointsH))
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("diyplay.") {
                UserDefaults.standard.removeObject(forKey: key)
            }
            for (key, value) in initialDefaults { UserDefaults.standard.set(value, forKey: key) }
        }

        try PhoneRemote.shared.enable()
        XCTAssertTrue(PhoneRemote.shared.isActive)
        let portrait = try XCTUnwrap(DisplayControl.currentUI())
        XCTAssertEqual(portrait.pointsW, 720)
        XCTAssertEqual(portrait.pointsH, 1560)
        XCTAssertTrue(portrait.hidpi)
        print("LIVE portrait: \(portrait.pointsW)x\(portrait.pointsH), backing \(portrait.pixelsW)x\(portrait.pixelsH), \(portrait.hz) Hz")

        let portraitMain = CGMainDisplayID()
        try PhoneRemote.shared.enable()
        DisplayControl.applyIfNeeded()
        XCTAssertEqual(CGMainDisplayID(), portraitMain, "Clicking the same preset and auto-repair must keep portrait active")

        let menu = NSMenu()
        MenuBarApp.shared.menuNeedsUpdate(menu)
        let remoteItem = try XCTUnwrap(menu.items.first { $0.title == PhoneRemote.title })
        XCTAssertEqual(remoteItem.state, .on)
        XCTAssertEqual(menu.items.filter { $0.state == .on && $0.action == NSSelectorFromString("pick:") }.count, 0)

        let native = DisplayControl.selectedNative(display)
        let daily = DisplayControl.daily(from: DisplayControl.slider(for: display, native: native,
                                                                    presetId: DisplayControl.resolvedPreset(display)?.id), native: native)
        try DisplayControl.apply(looksLike: daily)
        XCTAssertFalse(PhoneRemote.shared.ownsConfiguration)
        XCTAssertEqual(CGMainDisplayID(), initialMain)
        XCTAssertEqual(DisplayControl.currentUI()?.pointsW, daily.w)
        XCTAssertEqual(DisplayControl.currentUI()?.pointsH, daily.h)
        XCTAssertEqual(CGDisplayMirrorsDisplay(initialMain), kCGNullDirectDisplay)
        XCTAssertEqual(try? Data(contentsOf: overrideURL), initialOverride)
        MenuBarApp.shared.menuNeedsUpdate(menu)
        XCTAssertEqual(menu.items.first { $0.title == PhoneRemote.title }?.state, .off)
        XCTAssertEqual(menu.items.first { $0.title.hasPrefix("日常") }?.state, .on)
        print("LIVE returned through daily: \(daily.w)x\(daily.h); physical override unchanged")
    }
}
