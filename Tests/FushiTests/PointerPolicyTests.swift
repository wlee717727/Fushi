import XCTest

/// 指標來源判斷與擋法：用偵測工具在實機上讀到的真實資料當測試資料。
final class PointerPolicyTests: XCTestCase {
    // 實機紀錄 (2026-11-21，MacBook Pro M5 Max 觸控螢幕機型)
    let trackpad = SenderInfo(builtIn: true, className: "AppleMultitouchDevice",
                              product: "Apple Internal Keyboard / Trackpad", usagePage: 1, usage: 2)
    let mxMaster = SenderInfo(builtIn: nil, className: "AppleUserHIDEventService",
                              product: "MX Master 3", usagePage: 1, usage: 2)
    let kiwi = SenderInfo(builtIn: true, className: "AppleHIDTransportHIDDevice",
                          product: "Kiwi", usagePage: 0x0D, usage: 0x04)

    func testClassify() {
        XCTAssertEqual(PointerSource.classify(trackpad), .builtInTrackpad)
        XCTAssertEqual(PointerSource.classify(mxMaster), .externalPointer)
        XCTAssertEqual(PointerSource.classify(kiwi), .touchScreen)
        XCTAssertEqual(PointerSource.classify(nil), .unknown)
        // 外接觸控板 (Magic Trackpad) 不是內建，算外接，放行
        let magic = SenderInfo(builtIn: false, className: "AppleMultitouchDevice", product: "Magic Trackpad", usagePage: 1, usage: 2)
        XCTAssertEqual(PointerSource.classify(magic), .externalPointer)
        // 內建但不是觸控板的不明裝置：不擋
        let other = SenderInfo(builtIn: true, className: "Something", product: "Sensor", usagePage: 0xFF00, usage: 3)
        XCTAssertEqual(PointerSource.classify(other), .unknown)
    }

    func testTrackpadOnlyPolicy() {
        let p = PointerBlockPolicy(blockBuiltInTrackpad: true, blockTouchScreen: false)
        XCTAssertTrue(p.shouldBlock(.builtInTrackpad))
        XCTAssertFalse(p.shouldBlock(.externalPointer), "外接滑鼠是解鎖手段，永遠放行")
        XCTAssertFalse(p.shouldBlock(.touchScreen), "C 面鎖觸控板時，觸控螢幕要能按解鎖")
        XCTAssertFalse(p.shouldBlock(.unknown), "查不到來源一律放行，避免鎖死")
    }

    func testFullLockPolicy() {
        let p = PointerBlockPolicy(blockBuiltInTrackpad: true, blockTouchScreen: true)
        XCTAssertTrue(p.shouldBlock(.builtInTrackpad))
        XCTAssertTrue(p.shouldBlock(.touchScreen))
        XCTAssertFalse(p.shouldBlock(.externalPointer))
    }

    func testRecentSourceFallback() {
        var r = RecentPointerSource()
        XCTAssertEqual(r.resolve(.unknown, at: 0), .unknown, "一開始沒有紀錄就放行")
        XCTAssertEqual(r.resolve(.builtInTrackpad, at: 10), .builtInTrackpad)
        XCTAssertEqual(r.resolve(.unknown, at: 10.3), .builtInTrackpad, "0.5 秒內查不到來源，沿用觸控板")
        XCTAssertEqual(r.resolve(.unknown, at: 10.9), .unknown, "超過 0.5 秒就不再沿用")
        XCTAssertEqual(r.resolve(.externalPointer, at: 11), .externalPointer)
        XCTAssertEqual(r.resolve(.unknown, at: 11.2), .externalPointer)
    }
}
