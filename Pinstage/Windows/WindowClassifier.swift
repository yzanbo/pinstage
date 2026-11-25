import AppKit
import PinstageCore

/// 読んだウインドウを、どのデスクトップ・どのディスプレイのものか見分けた結果
struct WindowClassification {
    /// いまのデスクトップ（操作スペース）の見分け
    struct ActiveSpace {
        /// いま見ているデスクトップにあるウインドウ（最小化したもの・隠したアプリのものも入る）
        var ids: Set<AXUIElement>
        /// どのデスクトップのストリップにも並べるウインドウ（最小化したもの・隠したアプリのもの）
        var floating: Set<AXUIElement>
        /// 画面に出ているウインドウの一覧を 1 回読んだもの（ストリップが、自分のデスクトップの一覧を覚えるのに使う）
        var snapshot: DesktopSnapshot<AXUIElement>
    }

    /// ウインドウごとの、あるデスクトップ（非公開の API が使えないときは nil）
    var windowSpaces: [AXUIElement: Set<UInt64>]?
    /// ディスプレイごとのデスクトップの一覧と、そのうちの現在のデスクトップ
    var desktopDisplays: [SkyLight.Display]?
    /// デスクトップの名前
    var desktopNames: [UInt64: DesktopName]
    /// デスクトップの UUID（グループを出すデスクトップを覚えるのに使う。番号は再起動で変わることがあるので UUID で覚える）
    var desktopUUIDs: [UInt64: String]
    /// いまのデスクトップの見分け
    var activeSpace: ActiveSpace
    /// ウインドウごとの、あるディスプレイの鍵（ディスプレイごとに分けないときは見分けないので nil）
    var windowDisplays: [AXUIElement: String]?
    /// 隠されたウインドウ（いま見ているデスクトップにあるのに、画面に出ていない。最小化・アプリを隠したものは除く）。
    /// × で閉じてもウインドウを捨てずに隠すだけのアプリ（LINE など）のもの。非公開の API が使えないときは空
    var hiddenWindows: Set<AXUIElement>
}

/// 読んだウインドウを、どのデスクトップ・どのディスプレイのものか見分ける
enum WindowClassifier {
    /// - Parameter separatesDisplays: ウインドウバーごとに、そのディスプレイのウインドウだけを並べるか（並べないなら、ディスプレイを見分けない）
    static func classify(_ items: [WindowItem], separatesDisplays: Bool) -> WindowClassification {
        // どのデスクトップのウインドウかは、非公開の API が使えれば、設定にかかわらず読む（ほかのデスクトップの印に使う）
        let displayList = SkyLight.isAvailable ? SkyLight.displays() : nil
        var spaces = displayList == nil ? nil : windowSpaces(of: items)
        let frames = AXWindow.frames(of: items)
        let displays = assignDisplays(frames)
        let snapshot = CurrentSpace.snapshot(among: items, frames: frames)
        var spaceIDs = snapshot.onScreen.union(snapshot.floating)
        var hidden: Set<AXUIElement> = []
        if var known = spaces, let displayList {
            let current = Set(displayList.map(\.current))
            // 隠されたウインドウ（× で閉じても隠すだけのアプリのもの）。決まりは PinstageCore の HiddenWindows
            hidden = HiddenWindows.ids(spaces: known, current: current, onScreen: snapshot.onScreen, floating: snapshot.floating)
            // 番号が分からなかったウインドウは、画面に出ていれば、いま表に出ているデスクトップのものとする
            for id in snapshot.onScreen where known[id] == nil { known[id] = current }
            spaces = known
            // いま表に出ているデスクトップのウインドウ（ほかのウインドウに隠れていても入る）
            spaceIDs = Set(items.filter { !(known[$0.id] ?? []).isDisjoint(with: current) }.map(\.id)).union(snapshot.floating)
        }
        // フルスクリーンのウインドウは、デスクトップの一覧に入れないので、どのディスプレイのものかと一緒に覚える
        var fullScreen: [AXUIElement: DesktopSnapshot<AXUIElement>.Display] = [:]
        for id in snapshot.onScreen where AXWindow.isFullScreen(id) {
            fullScreen[id] = displays[id].map { .known($0) } ?? .unknown
        }
        return WindowClassification(
            windowSpaces: spaces,
            desktopDisplays: displayList,
            desktopNames: desktopNames(displayList ?? []),
            desktopUUIDs: desktopUUIDs(displayList ?? []),
            activeSpace: WindowClassification.ActiveSpace(
                ids: spaceIDs,
                floating: snapshot.floating,
                snapshot: DesktopSnapshot(onScreen: snapshot.onScreen, fullScreen: fullScreen, ownWindowNumbers: snapshot.ownWindowNumbers)
            ),
            windowDisplays: separatesDisplays ? displays : nil,
            hiddenWindows: hidden
        )
    }

    /// デスクトップの名前（ディスプレイごとに左から「デスクトップ 1」「デスクトップ 2」…。計算は PinstageCore の DesktopNaming）
    private static func desktopNames(_ displays: [SkyLight.Display]) -> [UInt64: DesktopName] {
        DesktopNaming.names(displays: displays.map { display in
            display.spaces.map { DesktopNaming.Space(id: $0.id, isFullScreen: $0.isFullScreen) }
        })
    }

    /// デスクトップの番号ごとの UUID（UUID が分からないデスクトップは入らない）
    private static func desktopUUIDs(_ displays: [SkyLight.Display]) -> [UInt64: String] {
        let pairs = displays.flatMap(\.spaces).compactMap { space in space.uuid.map { (space.id, $0) } }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    /// ウインドウごとの、あるデスクトップ（番号が分からないウインドウは入らない）
    private static func windowSpaces(of items: [WindowItem]) -> [AXUIElement: Set<UInt64>] {
        var result: [AXUIElement: Set<UInt64>] = [:]
        for item in items {
            guard let id = item.windowID else { continue }
            result[item.id] = SkyLight.spaces(ofWindow: id)
        }
        return result
    }

    /// ウインドウごとに、いちばん大きく重なっているディスプレイを決める
    private static func assignDisplays(_ frames: [AXUIElement: CGRect]) -> [AXUIElement: String] {
        let locator = DisplayLocator()
        return frames.compactMapValues(locator.key(for:))
    }
}
