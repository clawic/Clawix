import XCTest
@testable import Clawix

final class SyncSettingsTests: XCTestCase {
    private let defaults = UserDefaults(suiteName: appPrefsSuite) ?? .standard
    private let autoReloadKey = "AutoReloadOnFocus"
    private var previousAutoReloadValue: Any?

    override func setUp() {
        super.setUp()
        previousAutoReloadValue = defaults.object(forKey: autoReloadKey)
        defaults.removeObject(forKey: autoReloadKey)
    }

    override func tearDown() {
        if let previousAutoReloadValue {
            defaults.set(previousAutoReloadValue, forKey: autoReloadKey)
        } else {
            defaults.removeObject(forKey: autoReloadKey)
        }
        previousAutoReloadValue = nil
        super.tearDown()
    }

    func testAutoReloadOnFocusDefaultsOffWhenUnset() {
        XCTAssertFalse(SyncSettings.autoReloadOnFocus)
    }

    func testAutoReloadOnFocusPersistsTrue() {
        SyncSettings.autoReloadOnFocus = true

        XCTAssertTrue(SyncSettings.autoReloadOnFocus)
    }

    func testAutoReloadOnFocusPersistsFalse() {
        SyncSettings.autoReloadOnFocus = true
        SyncSettings.autoReloadOnFocus = false

        XCTAssertFalse(SyncSettings.autoReloadOnFocus)
    }
}
