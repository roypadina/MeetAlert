import XCTest
@testable import MeetAlert

final class KeychainTests: XCTestCase {
    func testPasswordParsesSecurityOutput() {
        XCTAssertEqual(Keychain.password("password: \"tk_abc\"\n"), "tk_abc")
        XCTAssertEqual(Keychain.password("password: \"deadbeef\"\n"), "deadbeef")  // hex-looking text stays text
        XCTAssertEqual(Keychain.password("password: \"a\"b c\"\n"), "a\"b c")
        XCTAssertEqual(Keychain.password("password: 0xD7A9D79CD795D79D \n"), "שלום")
        XCTAssertNil(Keychain.password("security: SecKeychainSearchCopyNext: not found\n"))
    }
}
