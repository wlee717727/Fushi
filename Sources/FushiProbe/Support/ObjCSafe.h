#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 執行 block；若裡面丟出 Objective-C 例外 (NSException)，攔下來回傳 NO，而不是讓 App 當掉。
/// 為什麼需要？NSEvent 的某些屬性 (例如 subtype、pressure) 對不支援的事件類型會丟例外，
/// Swift 的 do/catch 接不住 Objective-C 例外，偵測工具又要讀「所有」事件，所以用這個保護。
BOOL FPTry(NS_NOESCAPE void (^block)(void));

NS_ASSUME_NONNULL_END
