import Foundation

/// Esc 鍵的按鍵代碼。
///
/// 長按 Esc 3 秒緊急退出的判斷在 `EmergencyGuard` (Lock 資料夾)：第一次按下就開始計時，
/// 放開就取消，不依賴系統的「按鍵重複」。秒數在 `SessionPolicy.emergencyEscapeSeconds`。
enum EscapeKey {
    static let keyCode: Int64 = 53
}
