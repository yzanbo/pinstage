import CoreGraphics

/// ストリップ（画面の左端に出す、ウインドウとグループの一覧）の出し方
public enum StripMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 常に出す（ステージはストリップの右側だけを使う）
    case alwaysShown
    /// ふだんは隠し、ポインタを画面の左端に寄せたときだけ出す（ステージは画面いっぱいを使う）
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
/// 座標は macOS の画面座標（左下が原点）。`visibleFrame` はメニューバーと Dock を除いた範囲を渡す。
/// `width` はストリップの幅（右の縁をドラッグして変えられる。StripSettings.stripWidth）。
public enum StripGeometry {
    /// ストリップの幅の初期設定（pt）
    public static let defaultWidth: CGFloat = 230
    /// アイコンだけのときのストリップの幅（pt）
    public static let iconOnlyWidth: CGFloat = 64
    /// ストリップの幅の範囲（pt）
    public static let widthRange: ClosedRange<CGFloat> = 160...480
    /// ストリップと画面の左端との間、ストリップとステージとの間（pt）
    public static let margin: CGFloat = 8
    /// ストリップの上下の余白（pt）。ステージのウインドウと同じく、メニューバーの下から Dock の上までいっぱいに使う
    public static let verticalMargin: CGFloat = 0
    /// 画面の左端からこの距離（pt）までポインタが来たら、隠したストリップを出す
    public static let revealDistance: CGFloat = 2
    /// 出したストリップから、この距離（pt）より離れたら隠す
    public static let hideDistance: CGFloat = 24

    /// 幅を範囲の中に収める
    public static func clampedWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, widthRange.lowerBound), widthRange.upperBound)
    }

    /// 右の縁をドラッグしているときの幅（ポインタの x から）。範囲の中に収め、画面の半分より広くしない
    public static func width(forPointerX x: CGFloat, in visibleFrame: CGRect) -> CGFloat {
        let width = clampedWidth(x - visibleFrame.minX - margin)
        return min(width, max(widthRange.lowerBound, visibleFrame.width / 2))
    }

    /// 出しているときのストリップの枠
    public static func shownFrame(in visibleFrame: CGRect, width: CGFloat = defaultWidth) -> CGRect {
        CGRect(
            x: visibleFrame.minX + margin,
            y: visibleFrame.minY + verticalMargin,
            width: width,
            height: max(0, visibleFrame.height - verticalMargin * 2)
        )
    }

    /// 隠しているときのストリップの枠（画面の左の外へ出す）
    public static func hiddenFrame(in visibleFrame: CGRect, width: CGFloat = defaultWidth) -> CGRect {
        shownFrame(in: visibleFrame, width: width).offsetBy(dx: -(width + margin * 2), dy: 0)
    }

    /// ウインドウを並べる範囲（ステージ）
    public static func stageFrame(in visibleFrame: CGRect, mode: StripMode, width: CGFloat = defaultWidth) -> CGRect {
        switch mode {
        case .alwaysShown:
            let used = margin + width + margin
            return CGRect(
                x: visibleFrame.minX + used,
                y: visibleFrame.minY,
                width: max(0, visibleFrame.width - used),
                height: visibleFrame.height
            )
        case .autoHide:
            return visibleFrame
        }
    }

    /// 隠したストリップを出すか（ポインタがそのディスプレイの左端に来た）。
    /// 左隣にディスプレイがあるとき、隣のディスプレイの上で出してしまわないよう、そのディスプレイの中にあるときだけにする
    public static func shouldReveal(pointer: CGPoint, screenFrame: CGRect) -> Bool {
        pointer.x >= screenFrame.minX
            && pointer.x <= screenFrame.minX + revealDistance
            && pointer.y >= screenFrame.minY
            && pointer.y <= screenFrame.maxY
    }

    /// 出したストリップを隠すか（ポインタがストリップから離れた）
    public static func shouldHide(pointer: CGPoint, stripFrame: CGRect) -> Bool {
        !stripFrame.insetBy(dx: -hideDistance, dy: -hideDistance).contains(pointer)
    }
}

/// 「自動で隠す」のときに、いつ隠すかの決まり
///
/// - 画面の左端に寄せて出したとき: ストリップから離れたら隠す
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

    /// 隠した・左端に寄せて出した（ふつうの決まりに戻す）
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
