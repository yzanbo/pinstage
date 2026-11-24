import AppKit
import PinstageCore

/// 画面のウインドウの一覧（CGWindowList）の 1 つ分
///
/// 一覧の読み方（どの項目を、どの型で読むか）は、ここだけに置く。
nonisolated struct WindowListEntry {
    /// macOS のウインドウの番号
    let number: Int
    let pid: pid_t
    /// 高さ（レベル）。0 がふつうのウインドウ
    let layer: Int
    /// 枠（アクセシビリティの API と同じ、いちばん目の画面の左上が原点）
    let bounds: CGRect
    /// 名前（画面収録の許可がないと空になる）
    let title: String

    init?(_ info: [String: Any]) {
        guard let number = info[kCGWindowNumber as String] as? Int,
              let pid = info[kCGWindowOwnerPID as String] as? Int32,
              let layer = info[kCGWindowLayer as String] as? Int,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary)
        else { return nil }
        self.number = number
        self.pid = pid
        self.layer = layer
        self.bounds = bounds
        title = info[kCGWindowName as String] as? String ?? ""
    }

    /// ふつうの高さにある、大きさのあるウインドウか（パネル・ツールチップ・タブのバーなどの部品ではない）
    var isNormalWindow: Bool {
        WindowEligibility.isNormalWindow(layer: layer, size: bounds.size)
    }

    /// いま画面に出ているウインドウ（前から後ろの順）
    static func onScreen() -> [WindowListEntry] {
        entries(CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID))
    }

    /// すべてのウインドウ（ほかのデスクトップのもの・隠しているだけのものも入る）
    static func all() -> [WindowListEntry] {
        entries(CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID))
    }

    /// その番号のウインドウ
    static func entry(for id: CGWindowID) -> WindowListEntry? {
        entries(CGWindowListCreateDescriptionFromArray([id] as CFArray)).first
    }

    private static func entries(_ list: CFArray?) -> [WindowListEntry] {
        (list as? [[String: Any]] ?? []).compactMap(WindowListEntry.init)
    }
}
