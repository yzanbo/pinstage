import AppKit
import ApplicationServices

/// Dock のアプリのアイコンに付いている、macOS 標準のバッジ（Slack の赤い点・メールの未読の数など）を読む。
///
/// Dock は、アイコンごとのバッジの文字を、アクセシビリティの情報（AXStatusLabel）として出している。
/// Pinstage はアクセシビリティの許可を持っているので、それを読む（メニューバーにバッジを出すアプリと同じやり方）。
/// アプリが自分のアイコンの絵に描き込んだ印（Kickoff の角の丸など）は、絵の一部なので読めない
enum DockBadges {
    /// アプリ（bundle ID）ごとのバッジの文字（"•"・"3" など）。Dock に出ていないアプリ・バッジのないアプリは入らない
    static func read() -> [String: String] {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return [:] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        // Dock が応えないときに、待ち続けない
        AXUIElementSetMessagingTimeout(app, 0.2)
        var badges: [String: String] = [:]
        for list in children(of: app) where AXWindow.attribute(list, kAXRoleAttribute) as String? == kAXListRole {
            for item in children(of: list) {
                guard AXWindow.attribute(item, kAXSubroleAttribute) as String? == "AXApplicationDockItem",
                      let label: String = AXWindow.attribute(item, "AXStatusLabel"), !label.isEmpty,
                      let url = bundleURL(of: item), let bundleID = Bundle(url: url)?.bundleIdentifier
                else { continue }
                badges[bundleID] = label
            }
        }
        return badges
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        AXWindow.attribute(element, kAXChildrenAttribute) ?? []
    }

    /// Dock のアイコンのアプリの場所
    private static func bundleURL(of item: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFURLGetTypeID()
        else { return nil }
        return (value as! CFURL) as URL
    }
}
