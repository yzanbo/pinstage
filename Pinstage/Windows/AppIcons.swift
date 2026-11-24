import AppKit
import SwiftUI

/// アプリの識別名から、アイコンと名前を得る（起動していないアプリも。読んだものは覚えておく）
enum AppIcons {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let icon = icons[bundleID] { return icon }
        let icon: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            // 見つからないアプリ（消したアプリなど）は、ふつうのアプリの絵にする
            icon = NSWorkspace.shared.icon(for: .application)
        }
        icons[bundleID] = icon
        return icon
    }

    static func name(for bundleID: String) -> String {
        if let name = names[bundleID] { return name }
        let name = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
        names[bundleID] = name
        return name
    }
}

/// グループの中身のアプリのアイコン（起動していないアプリは、呼び出したときに起動し直すので、薄く描く）
struct MemberIcon: View {
    let bundleID: String
    /// 一辺の大きさ
    let size: CGFloat
    var isRunning = true

    var body: some View {
        Image(nsImage: AppIcons.icon(for: bundleID))
            .resizable()
            .frame(width: size, height: size)
            .opacity(isRunning ? 1 : 0.35)
    }
}
