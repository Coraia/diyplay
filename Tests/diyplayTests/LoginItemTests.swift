import Foundation
import XCTest
@testable import diyplay

final class LoginItemTests: XCTestCase {
    func testBackgroundMigrationPreservesSettingsAndIsIdempotent() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".plist")
        defer { try? FileManager.default.removeItem(at: url) }
        let executable = "/Applications/Diyplay.app/Contents/MacOS/diyplay"
        let initial: [String: Any] = [
            "Label": "com.coraia.diyplay", "ProgramArguments": [executable],
            "RunAtLoad": true, "KeepAlive": false, "EnvironmentVariables": ["CUSTOM": "preserve me"],
        ]
        try PropertyListSerialization.data(fromPropertyList: initial, format: .xml, options: 0).write(to: url)
        LoginItem.ensureBackgroundLaunch(at: url, executable: executable)
        let updated = try Data(contentsOf: url)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: updated, format: nil) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [executable, "--background"])
        for key in ["Label", "RunAtLoad", "KeepAlive", "EnvironmentVariables"] {
            XCTAssertEqual(plist[key] as? NSObject, initial[key] as? NSObject)
        }
        LoginItem.ensureBackgroundLaunch(at: url, executable: executable)
        XCTAssertEqual(try Data(contentsOf: url), updated)
        LoginItem.ensureBackgroundLaunch(at: url, executable: "/another/diyplay")
        XCTAssertEqual(try Data(contentsOf: url), updated)
    }
}
