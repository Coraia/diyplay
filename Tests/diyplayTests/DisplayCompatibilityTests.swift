import XCTest
@testable import diyplay

final class DisplayCompatibilityTests: XCTestCase {
    func testActiveDisplayFollowsTheMainDisplayInsteadOfAPreferredModel() throws {
        let oldPreferred = DisplayRecord(
            name: "32C1U", vendor: 9699, product: 65535,
            pixelsW: 3840, pixelsH: 2160, timingId: nil
        )
        let actualMain = DisplayRecord(
            name: "Different Monitor", vendor: 1234, product: 5678,
            pixelsW: 2560, pixelsH: 1440, timingId: nil
        )

        let selected = try XCTUnwrap(DisplayControl.selectActiveDisplay(
            from: [oldPreferred, actualMain],
            mainVendor: actualMain.vendor,
            mainProduct: actualMain.product
        ))

        XCTAssertEqual(selected.vendor, actualMain.vendor)
        XCTAssertEqual(selected.product, actualMain.product)
    }

    func testGenericResolutionChoicesAreLimitedToModesExposedByTheDisplay() {
        let display = DisplayRecord(
            name: "Different Monitor",
            vendor: 1234,
            product: 5678,
            pixelsW: 2560,
            pixelsH: 1440,
            timingId: nil
        )
        let exposedModes: Set<String> = ["1280x720", "1920x1080", "2560x1440"]

        let choices = DisplayControl.slider(
            for: display,
            native: (2560, 1440),
            presetId: nil,
            availableLooksLike: exposedModes
        )

        XCTAssertFalse(choices.isEmpty)
        XCTAssertTrue(choices.allSatisfy { exposedModes.contains("\($0.w)x\($0.h)") })
        XCTAssertEqual(choices.last?.w, 2560)
        XCTAssertEqual(choices.last?.h, 1440)
    }

    /// When the monitor's OSD switches PBP layouts, macOS reports a different
    /// pane size under the same vendor/product. Each of the three 32C1U pane
    /// sizes must map to its preset so `reconcilePane` can switch automatically.
    func testPaneSizeChangeMapsToManaged32C1UPresets() {
        XCTAssertEqual(
            DisplayControl.panePreset(vendor: 9699, product: 65535, detected: (w: 1920, h: 2160))?.id,
            "half"
        )
        XCTAssertEqual(
            DisplayControl.panePreset(vendor: 9699, product: 65535, detected: (w: 2824, h: 2160))?.id,
            "phone"
        )
        XCTAssertEqual(
            DisplayControl.panePreset(vendor: 9699, product: 65535, detected: (w: 3840, h: 2160))?.id,
            "full"
        )
    }

    /// Auto-adapt must never fire for a generic monitor or for a custom crop
    /// size, otherwise it would undo a deliberate physical-resolution override.
    func testGenericAndCustomPaneSizesAreNotAutoAdopted() {
        XCTAssertNil(DisplayControl.panePreset(vendor: 1234, product: 5678, detected: (w: 3840, h: 2160)))
        XCTAssertNil(DisplayControl.panePreset(vendor: 9699, product: 65535, detected: (w: 2560, h: 1440)))
        XCTAssertNil(DisplayControl.panePreset(vendor: 9699, product: 65535, detected: (w: 1600, h: 1800)))
    }

    /// A remembered "日常" size is kept per preset, and only for known presets,
    /// so restoring one PBP layout never leaks into another or into custom sizes.
    func testRememberedUIIsScopedPerPreset() {
        let display = DisplayRecord(
            name: "32C1U", vendor: 9699, product: 65535,
            pixelsW: 1920, pixelsH: 2160, timingId: nil
        )
        let full = "test-preset-full"
        let half = "test-preset-half"
        func cleanup() {
            for key in UserDefaults.standard.dictionaryRepresentation().keys
            where key.contains(".test-preset-") {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        cleanup()
        defer { cleanup() }

        DisplayControl.rememberUI((2560, 1440), for: display, presetId: full)
        DisplayControl.rememberUI((1600, 1800), for: display, presetId: half)

        XCTAssertEqual(DisplayControl.rememberedUI(for: display, presetId: full)?.w, 2560)
        XCTAssertEqual(DisplayControl.rememberedUI(for: display, presetId: full)?.h, 1440)
        XCTAssertEqual(DisplayControl.rememberedUI(for: display, presetId: half)?.w, 1600)
        // No preset id (custom / use-detected) is never remembered.
        XCTAssertNil(DisplayControl.rememberedUI(for: display, presetId: nil))
        XCTAssertNil(DisplayControl.rememberedUI(for: display, presetId: "test-preset-missing"))
    }
}
