import CoreGraphics

/// ストリップ（画面の端に出す、ウインドウとグループの一覧）の出し方
public enum StripMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 常に出す（ステージは、ストリップを除いた残りを使う）
    case alwaysShown
    /// ふだんは隠し、ポインタをストリップのある端に寄せたときだけ出す（ステージは画面いっぱいを使う）
    case autoHide

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .alwaysShown: "常に出す"
        case .autoHide: "自動で隠す"
        }
    }
}

/// ストリップとステージの位置の計算
///
/// 座標は macOS の画面座標（左下が原点。上の辺は maxY）。`visibleFrame` はメニューバーと Dock を除いた範囲を渡す
/// （常に出ている Dock・メニューバーと同じ辺に置いても、その内側に並ぶ）。
/// `thickness` はストリップの厚み（左右なら幅、上下なら高さ。StripSettings.effectiveThickness）。
public enum StripGeometry {
    /// ストリップの幅の初期設定（pt）
    public static let defaultWidth: CGFloat = 230
    /// ストリップの幅の範囲（pt）。アイコンの並びは、これより狭く、1 列になる幅まで狭められる（StripSettings.widthRange）
    public static let widthRange: ClosedRange<CGFloat> = 160...480

    /// ストリップと画面の端との間、ストリップとステージとの間（pt）。ストリップの長さは、使える範囲の端から端までいっぱいに使う
    public static let margin: CGFloat = 8
    /// 画面の端からこの距離（pt）までポインタが来たら、隠したストリップを出す
    public static let revealDistance: CGFloat = 2
    /// 出したストリップから、この距離（pt）より離れたら隠す
    public static let hideDistance: CGFloat = 24

    /// 左右のストリップを、細い帯の形（上の帯・並べ方のボタンを、アイコンだけにして縦に並べる）で描くか。
    /// ふつうの幅の下限より狭いとき（アイコンの並びを狭めたとき）
    public static func usesCompactChrome(width: CGFloat) -> Bool {
        width < widthRange.lowerBound
    }

    /// 幅を範囲の中に収める
    public static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }

    /// 内側の縁をドラッグしているときの幅（ポインタの x から。左右のストリップだけ）。範囲の中に収め、画面の半分より広くしない
    /// - Parameter range: 幅の範囲（形式で変わる。StripSettings.widthRange）
    public static func width(forPointerX x: CGFloat, in visibleFrame: CGRect, edge: StripEdge, range: ClosedRange<CGFloat> = widthRange) -> CGFloat {
        let raw = edge == .right ? visibleFrame.maxX - margin - x : x - visibleFrame.minX - margin
        let width = min(max(raw, range.lowerBound), range.upperBound)
        return min(width, max(range.lowerBound, visibleFrame.width / 2))
    }

    /// 出しているときのストリップの枠（その辺から間を空けて、厚みの分）
    public static func shownFrame(in visibleFrame: CGRect, edge: StripEdge, thickness: CGFloat) -> CGRect {
        visibleFrame
            .divided(atDistance: margin, from: edge.rectEdge).remainder
            .divided(atDistance: thickness, from: edge.rectEdge).slice
    }

    /// 隠しているときのストリップの枠（その辺の外へ出す）
    public static func hiddenFrame(in visibleFrame: CGRect, edge: StripEdge, thickness: CGFloat) -> CGRect {
        let distance = thickness + margin * 2
        return shownFrame(in: visibleFrame, edge: edge, thickness: thickness)
            .offsetBy(dx: edge.outward.dx * distance, dy: edge.outward.dy * distance)
    }

    /// ウインドウを並べる範囲（ステージ）。常に出すときは、ストリップと、その両側の間を除く
    public static func stageFrame(in visibleFrame: CGRect, mode: StripMode, edge: StripEdge, thickness: CGFloat) -> CGRect {
        guard mode == .alwaysShown else { return visibleFrame }
        return visibleFrame.divided(atDistance: margin + thickness + margin, from: edge.rectEdge).remainder
    }

    /// 隠したストリップを出すか（ポインタが、そのディスプレイの、ストリップのある端に来た）。
    /// 隣にディスプレイがあるとき、隣のディスプレイの上で出してしまわないよう、そのディスプレイの中にあるときだけにする
    public static func shouldReveal(pointer: CGPoint, screenFrame: CGRect, edge: StripEdge) -> Bool {
        guard pointer.x >= screenFrame.minX, pointer.x <= screenFrame.maxX,
              pointer.y >= screenFrame.minY, pointer.y <= screenFrame.maxY
        else { return false }
        return edge.distance(from: pointer, toEdgeOf: screenFrame) <= revealDistance
    }

    /// 出したストリップを隠すか（ポインタがストリップから離れた）。
    ///
    /// ストリップと画面の端との間（同じ辺に、常に出ている Dock・メニューバーがあるところ）は、離れたうちに入れない。
    /// 入れると、端に寄せて出した直後に「離れた」ことになって、出たり隠れたりを繰り返す。
    /// - Parameter screenFrame: そのディスプレイ全体の枠
    public static func shouldHide(pointer: CGPoint, stripFrame: CGRect, screenFrame: CGRect, edge: StripEdge) -> Bool {
        // ストリップを、画面の端まで伸ばした範囲
        let gap = max(0, edge.distance(from: stripFrame, toEdgeOf: screenFrame))
        let keep = stripFrame.union(stripFrame.offsetBy(dx: edge.outward.dx * gap, dy: edge.outward.dy * gap))
        return !keep.insetBy(dx: -hideDistance, dy: -hideDistance).contains(pointer)
    }
}

/// 「自動で隠す」のときに、いつ隠すかの決まり
///
/// - 画面の端に寄せて出したとき: ストリップから離れたら隠す
/// - キー・メニュー・自動化で出したとき: ポインタが離れたところにあっても、すぐには隠さない。
///   ポインタが一度ストリップに入って、そこから離れたら隠す（入らなければ、もう一度切り替えるまで出したまま）
public struct StripAutoHide: Equatable, Sendable {
    /// キー・メニュー・自動化で出して、出したままにしているか
    public private(set) var isHeldOpen = false
    /// 出したままにしている間に、ポインタがストリップに入ったか
    private var pointerEntered = false

    public init() {}

    /// キー・メニュー・自動化で出した
    public mutating func holdOpen() {
        isHeldOpen = true
        pointerEntered = false
    }

    /// 隠した・端に寄せて出した（ふつうの決まりに戻す）
    public mutating func reset() {
        isHeldOpen = false
        pointerEntered = false
    }

    /// いまのポインタの位置で隠すか（pointerNear はストリップの近くにあるか）
    public mutating func shouldHide(pointerNear: Bool) -> Bool {
        guard isHeldOpen else { return !pointerNear }
        if pointerNear {
            pointerEntered = true
            return false
        }
        if pointerEntered {
            reset()
            return true
        }
        return false
    }
}
