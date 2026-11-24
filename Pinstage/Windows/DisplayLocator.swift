import AppKit
import PinstageCore

/// ウインドウの枠（アクセシビリティの座標）から、どのディスプレイのものかを決める
///
/// つながっているディスプレイを 1 回読んでおき、いくつものウインドウに使う。
struct DisplayLocator {
    private let screens: [NSScreen]
    /// ディスプレイの枠（アクセシビリティの座標。いちばん目の画面の左上が原点）
    private let frames: [CGRect]
    /// ディスプレイの鍵（StageController.displayKey）
    private let keys: [String]

    init() {
        screens = NSScreen.screens
        let primaryHeight = NSScreen.primary?.frame.height ?? 0
        frames = screens.map { ScreenCoordinates.toAccessibility($0.frame, primaryScreenHeight: primaryHeight) }
        keys = screens.map(StageController.displayKey)
    }

    /// いちばん大きく重なっているディスプレイと、その鍵（どこにも重なっていなければ、いちばん近いディスプレイ）
    func display(for frame: CGRect) -> (screen: NSScreen, key: String)? {
        DisplayAssignment.displayIndex(for: frame, displays: frames).map { (screens[$0], keys[$0]) }
    }

    /// そのウインドウがあるディスプレイの鍵
    func key(for frame: CGRect) -> String? {
        display(for: frame)?.key
    }
}
