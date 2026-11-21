import XCTest

final class AppLanguageTests: XCTestCase {
    func testNoSettingFollowsSystem() {
        XCTAssertEqual(AppLanguage.from(appleLanguages: nil), .system)
        XCTAssertEqual(AppLanguage.from(appleLanguages: []), .system)
    }

    func testRecognisesSupportedLanguages() {
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["en"]), .en)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["en-US"]), .en)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["zh-Hant"]), .zhHant)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["zh-Hant-TW"]), .zhHant)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["zh-MO"]), .zhHant)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["zh-Hans-CN"]), .zhHans)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["ja-JP"]), .ja)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["ko"]), .ko)
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["es-419"]), .es)
    }

    func testUnsupportedLanguageFallsBackToSystem() {
        XCTAssertEqual(AppLanguage.from(appleLanguages: ["de-DE"]), .system)
    }

    func testCodesAndNames() {
        XCTAssertNil(AppLanguage.system.code)
        XCTAssertNil(AppLanguage.system.nativeName)
        XCTAssertEqual(AppLanguage.zhHant.code, "zh-Hant")
        XCTAssertEqual(AppLanguage.allCases.compactMap(\.code), ["en", "zh-Hant", "zh-Hans", "ja", "ko", "es"])
    }
}
