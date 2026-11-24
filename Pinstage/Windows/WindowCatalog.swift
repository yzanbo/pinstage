import AppKit
import ApplicationServices
import PinstageCore

/// ほかのアプリのウインドウ 1 つ
struct WindowItem: Identifiable, Equatable {
    /// アクセシビリティの要素（同じウインドウなら、読み直しても同じと見なされる）
    let id: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let appName: String
    let title: String
    let icon: NSImage?
    let isMinimized: Bool
    /// macOS のウインドウの番号（非公開の API で得る。得られなければ nil で、アプリ・名前・位置で照らし合わせる）
    var windowID: CGWindowID?

    /// ストリップに出す名前（名前のないウインドウは、アプリの名前）
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    /// 読み直したときに、ストリップを描き直す必要があるか（アイコンは同じアプリなら同じなので比べない）
    static func == (lhs: WindowItem, rhs: WindowItem) -> Bool {
        lhs.id == rhs.id && lhs.pid == rhs.pid && lhs.title == rhs.title && lhs.isMinimized == rhs.isMinimized
    }

    /// 再起動のあとも見つけるための手がかり（識別名のないアプリは覚えられない）
    var signature: WindowSignature? {
        bundleID.map { WindowSignature(bundleID: $0, title: title) }
    }

    /// 画面に出ているウインドウの一覧・画面収録の一覧と照らし合わせるための手がかり（frame は読んでおいた枠）
    func matchKey(frame: CGRect?) -> CaptureWindowMatcher.Window {
        CaptureWindowMatcher.Window(pid: pid, title: title, frame: frame ?? .zero)
    }
}

/// いま開いているウインドウを集める
enum WindowCatalog {
    static func enumerate() -> [WindowItem] {
        var items: [WindowItem] = []
        for app in NSWorkspace.shared.runningApplications where app.hasManageableWindows {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            guard let windows: [AXUIElement] = AXWindow.attribute(axApp, kAXWindowsAttribute) else { continue }
            for window in windows {
                // ふつうのウインドウだけ（パネル・ダイアログ・ツールチップなどは除く）
                let subrole: String? = AXWindow.attribute(window, kAXSubroleAttribute)
                guard subrole == kAXStandardWindowSubrole else { continue }
                items.append(WindowItem(
                    id: window,
                    pid: app.processIdentifier,
                    bundleID: app.bundleIdentifier,
                    appName: app.localizedName ?? "名前のないアプリ",
                    title: AXWindow.attribute(window, kAXTitleAttribute) ?? "",
                    icon: app.icon,
                    isMinimized: AXWindow.attribute(window, kAXMinimizedAttribute) ?? false,
                    windowID: SkyLight.windowID(of: window)
                ))
            }
        }
        return items
    }
}

extension NSScreen {
    /// ディスプレイの番号（つなぎ直すと変わることがある）
    var displayNumber: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// ディスプレイの UUID（つなぎ直しても、再起動しても変わらない。グループに覚えさせる）
    var displayUUID: String? {
        guard let number = displayNumber, let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// いちばん目の画面（メニューバーのある画面。座標の原点がある）
    static var primary: NSScreen? {
        screens.first
    }

    /// その UUID のディスプレイ（つながっていなければ nil）
    static func screen(withDisplayUUID id: String) -> NSScreen? {
        screens.first { $0.displayUUID == id }
    }

    /// その UUID のディスプレイの名前（グループを出すディスプレイとして見せる）
    static func displayName(forDisplayUUID id: String) -> String {
        screen(withDisplayUUID: id)?.localizedName ?? "つながっていないディスプレイ"
    }
}

extension NSRunningApplication {
    /// ウインドウを扱うアプリか（Dock に出るふつうのアプリ。Pinstage 自身は除く）
    var hasManageableWindows: Bool {
        activationPolicy == .regular && processIdentifier != ProcessInfo.processInfo.processIdentifier
    }
}

extension NSWorkspace {
    /// いま動いているアプリの識別名
    var runningBundleIDs: Set<String> {
        Set(runningApplications.compactMap(\.bundleIdentifier))
    }

    /// URL の文字列を開く（システム設定の画面・ほかのアプリ）
    func open(urlString: String) {
        if let url = URL(string: urlString) { open(url) }
    }
}
