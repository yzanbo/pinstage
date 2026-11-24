import AppKit
import PinstageCore

/// macOS の帯（Dock・メニューバー）の出し方
///
/// 常に出ている Dock・メニューバーは、ディスプレイの使える範囲（visibleFrame）から除かれているので、
/// ストリップを同じ辺に置いても、その内側に並ぶ。自動で隠れる設定のものは除かれていないので、出てきたときにストリップの上に重なる。
/// 自動で隠れるかは、使える範囲からは分からないので、macOS の設定（com.apple.dock・すべてのアプリに共通の設定）を読む。
enum SystemBars {
    private static let dockDomain = "com.apple.dock" as CFString

    /// Dock のある辺（左・下・右）
    static var dockEdge: StripEdge {
        StripEdgeConflict.dockEdge(orientation: dockValue("orientation") as? String)
    }

    /// Dock を自動で隠す設定か
    static var dockAutoHides: Bool {
        dockValue("autohide") as? Bool ?? false
    }

    /// メニューバーを、デスクトップでも自動で隠す設定か
    static var menuBarAutoHides: Bool {
        UserDefaults.standard.bool(forKey: "_HIHideMenuBar")
    }

    /// その辺に置いたストリップに重なるもの（なければ nil）
    static func conflict(for edge: StripEdge) -> StripEdgeConflict? {
        CFPreferencesAppSynchronize(dockDomain)
        return StripEdgeConflict.conflict(
            edge: edge,
            dockEdge: dockEdge,
            dockAutoHides: dockAutoHides,
            menuBarAutoHides: menuBarAutoHides
        )
    }

    /// システム設定の「デスクトップと Dock」を開く（Dock の位置・自動で隠すか・ステージマネージャを変えられる）
    static func openDockSettings() {
        NSWorkspace.shared.open(urlString: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")
    }

    /// システム設定の「メニューバー」（なければ「コントロールセンター」）を開く
    static func openMenuBarSettings() {
        NSWorkspace.shared.open(urlString: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
    }

    private static func dockValue(_ key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, dockDomain)
    }
}

extension StripEdgeConflict {
    /// 設定に出す説明
    var message: String {
        switch self {
        case .autoHidingDock:
            "この辺には、自動で隠れる Dock があります。Dock が出ている間は、ストリップが Dock の後ろに隠れます。ほかの辺を選ぶか、Dock を常に表示すると、重なりません（常に表示した Dock の内側に並びます）。"
        case .autoHidingMenuBar:
            "メニューバーが自動で隠れる設定です。メニューバーが出ている間は、ストリップの上の端がメニューバーの後ろに隠れます。"
        }
    }
}
