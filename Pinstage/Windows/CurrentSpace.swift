import AppKit
import PinstageCore

/// いま見ているデスクトップ（操作スペース）にあるウインドウを見分ける
///
/// 操作スペースを扱う公開の API はないので、いま画面に出ているウインドウの一覧（CGWindowList）と、
/// アプリ・位置（画面収録の許可があれば名前も）で照らし合わせる。
/// しまってある（最小化した）ウインドウと、隠したアプリのウインドウは画面に出ていないので、いまのデスクトップのものとして扱う
/// （どのデスクトップのものか分からず、出すとこのデスクトップに戻ってくるため）。
enum CurrentSpace {
    /// 画面に出ているウインドウの一覧を、1 回読んだもの
    ///
    /// ウインドウと、このアプリのウインドウ（ストリップ）を同じ 1 回の一覧から見分ける。
    /// 別々に読むと、デスクトップを切り替えている途中に、ウインドウとストリップの組み合わせが食い違う。
    struct Snapshot {
        /// 画面に出ているウインドウ（最小化したもの・隠したアプリのものは入らない）
        var onScreen: Set<AXUIElement> = []
        /// どのデスクトップにも並べるウインドウ（最小化したもの・隠したアプリのもの）
        var floating: Set<AXUIElement> = []
        /// 画面に出ている、このアプリのウインドウの番号（どのストリップが画面に出ているかを見分ける）
        var ownWindowNumbers: Set<Int> = []
    }

    /// いま画面に出ているウインドウを読む（frames は読んでおいたウインドウの枠）
    static func snapshot(among items: [WindowItem], frames: [AXUIElement: CGRect]) -> Snapshot {
        let (visible, floating) = split(items)
        let list = WindowListEntry.onScreen()
        var result = Snapshot(floating: Set(floating.map(\.id)), ownWindowNumbers: ownWindowNumbers(in: list))
        for (item, match) in zip(visible, matches(visible, frames: frames, in: list)) where match != nil {
            result.onScreen.insert(item.id)
        }
        return result
    }

    /// 画面に出ている、このアプリのウインドウの番号（隠したストリップも、透明にして置いてあるので入る）
    static func ownWindowNumbersOnScreen() -> Set<Int> {
        ownWindowNumbers(in: WindowListEntry.onScreen())
    }

    /// 画面に見えているウインドウを、前から後ろの順に並べる（見えていないもの・最小化したものは入れない）。
    /// 画面に出ているウインドウの一覧（CGWindowList）は、前から後ろの順に並んでいるので、その順番を使う
    static func frontToBack(among items: [WindowItem], frames: [AXUIElement: CGRect]) -> [WindowItem] {
        let visible = split(items).visible
        return zip(visible, matches(visible, frames: frames, in: WindowListEntry.onScreen()))
            .compactMap { item, match in match.map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// 画面に出ていれば見つかるウインドウ（visible）と、画面に出ていないウインドウ（floating。最小化したもの・隠したアプリのもの）に分ける。
    /// アプリを隠しているかは、アプリごとに 1 回だけ調べる
    private static func split(_ items: [WindowItem]) -> (visible: [WindowItem], floating: [WindowItem]) {
        var isHidden: [pid_t: Bool] = [:]
        var visible: [WindowItem] = []
        var floating: [WindowItem] = []
        for item in items {
            if item.isMinimized {
                floating.append(item)
                continue
            }
            let hidden = isHidden[item.pid] ?? (NSRunningApplication(processIdentifier: item.pid)?.isHidden == true)
            isHidden[item.pid] = hidden
            if hidden {
                floating.append(item)
            } else {
                visible.append(item)
            }
        }
        return (visible, floating)
    }

    /// ウインドウごとに、画面に出ているウインドウの一覧の何番目か（前から。出ていなければ nil）。
    /// ウインドウの番号が分かるものは番号で、分からないものはアプリ・名前・位置で照らし合わせる
    private static func matches(_ items: [WindowItem], frames: [AXUIElement: CGRect], in list: [WindowListEntry]) -> [Int?] {
        // ふつうの高さのウインドウだけ（ほかのウインドウの上に浮くパネルは除く）
        let candidates = list.filter { $0.layer == 0 }
        let positions = Dictionary(candidates.enumerated().map { ($1.number, $0) }, uniquingKeysWith: { first, _ in first })
        let fallback = items.indices.filter { items[$0].windowID == nil }
        var result: [Int?] = items.map { item in item.windowID.flatMap { positions[Int($0)] } }
        if !fallback.isEmpty {
            let matched = CaptureWindowMatcher.match(
                fallback.map { items[$0].matchKey(frame: frames[items[$0].id]) },
                // 名前は、画面収録の許可がないと空になる（そのときは位置だけで照らし合わせる）
                candidates: candidates.map { CaptureWindowMatcher.Window(pid: $0.pid, title: $0.title, frame: $0.bounds) }
            )
            for (index, match) in zip(fallback, matched) { result[index] = match }
        }
        return result
    }

    private static func ownWindowNumbers(in list: [WindowListEntry]) -> Set<Int> {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return Set(list.filter { $0.pid == ownPID }.map(\.number))
    }
}
