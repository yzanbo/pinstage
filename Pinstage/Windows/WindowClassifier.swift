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
    /// デスクトップの名前
    var desktopNames: [UInt64: DesktopName]
    /// いまのデスクトップの見分け（「ほかのデスクトップのウインドウも出す」ときは見分けないので nil）
    var activeSpace: ActiveSpace?
    /// ウインドウごとの、あるディスプレイの鍵（ディスプレイごとに分けないときは見分けないので nil）
    var windowDisplays: [AXUIElement: String]?
}

/// 読んだウインドウを、どのデスクトップ・どのディスプレイのものか見分ける
enum WindowClassifier {
    /// - Parameters:
    ///   - showsOtherSpaces: 「ほかのデスクトップのウインドウも出す」か（出すなら、いまのデスクトップのものを見分けない）
    ///   - separatesDisplays: ストリップごとに、そのディスプレイのウインドウだけを並べるか（並べないなら、ディスプレイを見分けない）
    static func classify(_ items: [WindowItem], showsOtherSpaces: Bool, separatesDisplays: Bool) -> WindowClassification {
        // どのデスクトップのウインドウかは、非公開の API が使えれば、設定にかかわらず読む（ほかのデスクトップの印に使う）
        let displayList = SkyLight.isAvailable ? SkyLight.displays() : nil
        var spaces = displayList == nil ? nil : windowSpaces(of: items)
        var result = WindowClassification(windowSpaces: nil, desktopNames: desktopNames(displayList ?? []))
        // どちらも見分けなくてよいときは、枠を読まない（応答の遅いアプリがあると時間がかかるため）
        guard !showsOtherSpaces || separatesDisplays else {
            result.windowSpaces = spaces
            return result
        }
        let frames = AXWindow.frames(of: items)
        let displays = assignDisplays(frames)
        if !showsOtherSpaces {
            let snapshot = CurrentSpace.snapshot(among: items, frames: frames)
            var spaceIDs = snapshot.onScreen.union(snapshot.floating)
            if var known = spaces, let displayList {
                let current = Set(displayList.map(\.current))
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
            result.activeSpace = WindowClassification.ActiveSpace(
                ids: spaceIDs,
                floating: snapshot.floating,
                snapshot: DesktopSnapshot(onScreen: snapshot.onScreen, fullScreen: fullScreen, ownWindowNumbers: snapshot.ownWindowNumbers)
            )
        }
        if separatesDisplays { result.windowDisplays = displays }
        result.windowSpaces = spaces
        return result
    }

    /// デスクトップの名前（ディスプレイごとに左から「デスクトップ 1」「デスクトップ 2」…。計算は PinstageCore の DesktopNaming）
    private static func desktopNames(_ displays: [SkyLight.Display]) -> [UInt64: DesktopName] {
        DesktopNaming.names(displays: displays.map { display in
            display.spaces.map { DesktopNaming.Space(id: $0.id, isFullScreen: $0.isFullScreen) }
        })
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
