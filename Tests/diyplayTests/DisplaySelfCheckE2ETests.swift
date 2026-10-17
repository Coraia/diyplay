import AppKit
import CoreGraphics
import Foundation
import XCTest
@testable import diyplay

final class DisplaySelfCheckE2ETests: XCTestCase {
    @MainActor
    func testCurrentMenuOnlyOffersModesExposedByTheTargetDisplay() throws {
        guard ProcessInfo.processInfo.environment["DIYPLAY_DISPLAY_SELF_CHECK"] == "1" else {
            throw XCTSkip("Set DIYPLAY_DISPLAY_SELF_CHECK=1 for the read-only on-device check.")
        }
        let displayID = try XCTUnwrap(DisplayControl.mainExternalDisplay())
        let snapshot = try XCTUnwrap(DisplayControl.snapshot())
        let available = DisplayControl.availableLooksLike(display: displayID)
        let proposed = DisplayControl.slider(
            for: snapshot.display,
            native: snapshot.native,
            presetId: snapshot.presetId
        ).map { "\($0.w)x\($0.h)" }
        let menu = NSMenu()
        MenuBarApp.shared.menuNeedsUpdate(menu)
        let offered = menu.items.compactMap { item -> String? in
            guard item.action == NSSelectorFromString("pick:") else { return nil }
            return item.representedObject as? String
        }
        let unsupported = offered.filter { !available.contains($0) }
        let excluded = proposed.filter { !available.contains($0) }

        XCTAssertEqual(snapshot.display.vendor, Int(CGDisplayVendorNumber(displayID)))
        XCTAssertEqual(snapshot.display.product, Int(CGDisplayModelNumber(displayID)))
        XCTAssertFalse(offered.isEmpty)
        XCTAssertTrue(unsupported.isEmpty, "Menu offered unavailable modes: \(unsupported)")

        if let path = ProcessInfo.processInfo.environment["DIYPLAY_E2E_ARTIFACT"] {
            let current = try XCTUnwrap(snapshot.ui)
            let artifact: [String: Any] = [
                "check": "Every normal resolution shown by the real menu exists in the target display's CoreGraphics mode table.",
                "display": [
                    "name": snapshot.display.name,
                    "vendor": snapshot.display.vendor,
                    "product": snapshot.display.product,
                    "detectedPhysical": "\(snapshot.display.pixelsW)x\(snapshot.display.pixelsH)",
                    "selectedPhysical": "\(snapshot.native.w)x\(snapshot.native.h)",
                ],
                "currentLooksLike": "\(current.pointsW)x\(current.pointsH)",
                "availableModeCount": available.count,
                "proposedNormalModesBeforeSelfCheck": proposed,
                "offeredNormalModes": offered,
                "excludedUnavailableModes": excluded,
                "unsupportedOfferedModes": unsupported,
                "passed": unsupported.isEmpty,
            ]
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: artifact, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            print("E2E artifact: \(url.path)")
        }
    }
}
