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
}
