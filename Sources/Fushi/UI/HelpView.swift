import SwiftUI

/// 內建使用說明 (「說明」選單 › 拂拭 使用說明，⌘?)。
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fushi Help").font(.largeTitle.weight(.semibold))
                        Text("Locks input while you clean your Mac. Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                            .foregroundStyle(.secondary)
                    }
                }

                HelpSection(title: "What Fushi does", symbol: "sparkles") {
                    Text("When you wipe the screen or the keyboard, your hands inevitably touch keys, the trackpad, and the touch screen. Fushi temporarily locks those inputs while you clean and unlocks them automatically when time is up. The name comes from a Zen verse: “wipe it diligently, and let no dust gather.”")
                }

                HelpSection(title: "Quick start", symbol: "play.circle") {
                    HelpBullet("In the sidebar of the main window, choose Screen Cleaning, Keyboard Cleaning, Trackpad Cleaning, or Full Lock.")
                    HelpBullet("Click Start Cleaning (or press Return). Locking begins after a 3-second countdown; click Cancel or press Esc during the countdown to stop.")
                    HelpBullet("When you’re done, hold “Hold 2 s to end cleaning”, or wait for the automatic unlock.")
                    HelpBullet("Auto-unlock is 3 minutes by default. Change it from 30 seconds to 10 minutes in Fushi › Settings (⌘,).")
                }

                HelpSection(title: "Screen Cleaning", symbol: "sparkles.tv") {
                    HelpBullet("Every display turns black. With OLED the pixels go dark, so dust and fingerprints are easiest to see.")
                    HelpBullet("Taps on the touch screen land on the black screen and press nothing.")
                    HelpBullet("When you touch the keyboard, trackpad, or mouse, a gold glow slowly breathes around the edges to show the Mac is still on. No buttons appear, so wiping the screen can’t press anything.")
                    HelpBullet("To end: hold Esc for 3 s (a 3‑2‑1 countdown appears), or wait for the automatic unlock.")
                    HelpBullet("No permission needed.")
                }

                HelpSection(title: "Keyboard Cleaning", symbol: "keyboard") {
                    HelpBullet("No key does anything, including brightness, volume, and media keys. The screen stays on.")
                    HelpBullet("“Also lock the trackpad” is on by default, so your palms won’t move the pointer while you wipe. Turn it off if you want to keep using the trackpad.")
                    HelpBullet("A panel appears at the top of the screen; hold “Hold 2 s to end cleaning” to unlock. When the trackpad is locked, use the touch screen or an external mouse; without either, hold Esc for 3 s.")
                    HelpBullet("Requires Accessibility permission (the Permissions page guides you the first time).")
                }

                HelpSection(title: "Trackpad Cleaning", symbol: "rectangle.and.hand.point.up.left") {
                    HelpBullet("Only the Mac’s built-in trackpad is locked (moving, clicking, gestures). The keyboard, external mice, and the touch screen keep working.")
                    HelpBullet("To end, hold “Hold 2 s to end cleaning” with the touch screen or an external mouse, or hold Esc for 3 s.")
                    HelpBullet("Requires Accessibility permission.")
                }

                HelpSection(title: "Full Lock", symbol: "lock.fill") {
                    HelpBullet("The screen goes black and the keyboard, trackpad, and touch screen are all locked. Only an external mouse (Bluetooth or USB) still works.")
                    HelpBullet("An external mouse must be connected before you start. Move it to bring up the control panel, then hold the red button for 2 s with the mouse.")
                    HelpBullet("Unplugging the external mouse (or a Bluetooth disconnect or dead battery) unlocks everything instantly, so you can never be locked out. For mice with a USB receiver (such as Logitech Unifying or Bolt), unplug the receiver — turning off the mouse alone does not unlock.")
                }

                HelpSection(title: "Menu bar", symbol: "menubar.rectangle") {
                    HelpBullet("The Fushi icon at the top right shows the current state: sparkles when idle, a timer during the countdown, a lock while cleaning.")
                    HelpBullet("From the menu bar you can start or end cleaning and open the main window or Settings.")
                    HelpBullet("Turn on “Start the last mode when Fushi opens” in Settings, and opening the app starts the countdown right away.")
                }

                HelpSection(title: "Keyboard shortcuts", symbol: "command") {
                    HelpShortcut(keys: "Return", text: "Start cleaning (main window)")
                    HelpShortcut(keys: "Esc", text: "Cancel countdown (main window)")
                    HelpShortcut(keys: "Hold Esc for 3 s", text: "Emergency exit: ends any cleaning mode")
                    HelpShortcut(keys: "⌘ ,", text: "Open Settings")
                    HelpShortcut(keys: "⌘ ?", text: "Open Help")
                    HelpShortcut(keys: "⌘ Q", text: "Quit Fushi (disabled during screen cleaning to avoid accidents)")
                }

                HelpSection(title: "Safety", symbol: "checkmark.shield") {
                    HelpBullet("Emergency exit: in any mode, holding Esc for 3 s always ends cleaning (even with the keyboard locked). A 3‑2‑1 ring appears while you hold; release to cancel.")
                    HelpBullet("When the screen is black, touching the keyboard, trackpad, or mouse makes a gold glow breathe around the edges to remind you the Mac is on and how to finish. Wiping the touch screen does not trigger it.")
                    HelpBullet("Always unlocks: input is released when time is up, and locks have their own independent backup timers.")
                    HelpBullet("If Fushi crashes or is force-quit, the lock disappears with it and input returns immediately. Fushi never changes system settings.")
                    HelpBullet("Without the required permission, Fushi won’t lock; it takes you to the Permissions page instead.")
                }

                HelpSection(title: "FAQ", symbol: "questionmark.circle") {
                    HelpQA(q: "Are the power button and Touch ID locked too?",
                           a: "No. The power button and Touch ID are handled directly by the hardware and the system; no app can block them. Avoid the power button / Touch ID at the top right while cleaning so the Mac doesn’t sleep or shut down.")
                    HelpQA(q: "Keyboard locking fails after updating Fushi?",
                           a: "Open the Permissions page in the main window and check that Accessibility still says Allowed. If not, remove the old “Fushi” from the list in System Settings, then add it again and turn it on.")
                    HelpQA(q: "During screen cleaning, can trackpad gestures still switch desktops?",
                           a: "System gestures such as three-finger swipes and Mission Control are handled by macOS and may still work. Fushi disables ⌘Tab and hides the Dock and menu bar.")
                    HelpQA(q: "Does the Caps Lock light still turn on?",
                           a: "It may. Caps Lock is handled by the keyboard hardware, so if you touch it while cleaning, Caps Lock may be toggled after unlocking. Check the Caps Lock light when you finish.")
                    HelpQA(q: "How do I unlock in an emergency?",
                           a: "In any mode, holding Esc for 3 s always ends cleaning (a 3‑2‑1 countdown appears). In Keyboard and Trackpad Cleaning you can hold “Hold 2 s to end cleaning” with the touch screen or an external mouse; in Full Lock, unplugging the external mouse unlocks immediately. Input always unlocks when time is up, and turning off Accessibility during cleaning releases the lock at once. As a last resort, holding the power button to force a shutdown always restores input.")
                    HelpQA(q: "How do I change the language?",
                           a: "Open Fushi › Settings (⌘,) and choose a language, then click Reopen Now. “Follow System” uses the language in System Settings › General › Language & Region.")
                    HelpQA(q: "Why can’t I lock the keyboard while the cursor is in a password field?",
                           a: "Password fields turn on macOS Secure Input, which prevents any app from intercepting the keyboard (it protects your passwords). Click somewhere outside the password field first, then start cleaning.")
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 360, minHeight: 400)
    }
}

struct HelpSection<Content: View>: View {
    let title: LocalizedStringKey
    let symbol: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) { content }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpBullet: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct HelpShortcut: View {
    let keys: LocalizedStringKey
    let text: LocalizedStringKey
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(keys)
                .font(.callout)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(nsColor: .separatorColor)))
                .frame(minWidth: 130, alignment: .leading)
            Text(text)
        }
    }
}

struct HelpQA: View {
    let q: LocalizedStringKey
    let a: LocalizedStringKey
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(q).font(.callout.weight(.semibold))
            Text(a).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}
