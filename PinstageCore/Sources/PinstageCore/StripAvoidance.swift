import CoreGraphics

/// ウインドウを、常に出しているストリップに重ねない（タイトルバーのダブルクリックなどで広がったとき、ステージの範囲に収める）
public enum StripAvoidance {
    /// これより小さいはみ出しは、気にしない（pt）
    public static let tolerance: CGFloat = 2

    /// ストリップに重なっていれば、ステージの範囲に収めた枠（重なっていなければ nil）
    ///
    /// - 画面いっぱいなど、ステージより広いウインドウは、ステージいっぱいにする
    /// - 重なっているだけのウインドウは、大きさを変えずにステージのほうへずらす（収まらなければ縮める）
    /// - Parameters:
    ///   - frame: ウインドウの枠（アクセシビリティの座標。左上が原点なので、上の辺は minY）
    ///   - stage: ステージの範囲（ストリップを除いた残り。frame と同じ座標）
    ///   - edge: ストリップのある辺
    public static func adjusted(_ frame: CGRect, stage: CGRect, edge: StripEdge) -> CGRect? {
        // ステージの、ストリップのある側へはみ出していなければ、そのまま（その先の、隣のディスプレイにあるものも除く）
        let overlaps: Bool = switch edge {
        case .left: frame.minX < stage.minX - tolerance && frame.maxX > stage.minX - stage.width
        case .right: frame.maxX > stage.maxX + tolerance && frame.minX < stage.maxX + stage.width
        case .top: frame.minY < stage.minY - tolerance && frame.maxY > stage.minY - stage.height
        case .bottom: frame.maxY > stage.maxY + tolerance && frame.minY < stage.maxY + stage.height
        }
        guard overlaps else { return nil }
        let fitted = StageLayout.fit(frame, into: stage)
        return fitted == frame ? nil : fitted
    }

    /// ステージの範囲が広がったとき（ストリップを狭めた・ほかの辺へ移した）、前の端にくっつけていたウインドウを、新しい端まで広げた枠。
    /// 広がった側の端にくっついていなかったウインドウ・範囲が広がっていないときは nil（動かさない）
    public static func following(_ frame: CGRect, stageFrom old: CGRect, to new: CGRect) -> CGRect? {
        var minX = frame.minX, maxX = frame.maxX, minY = frame.minY, maxY = frame.maxY
        if new.minX < old.minX, abs(frame.minX - old.minX) <= tolerance { minX = new.minX }
        if new.maxX > old.maxX, abs(frame.maxX - old.maxX) <= tolerance { maxX = new.maxX }
        if new.minY < old.minY, abs(frame.minY - old.minY) <= tolerance { minY = new.minY }
        if new.maxY > old.maxY, abs(frame.maxY - old.maxY) <= tolerance { maxY = new.maxY }
        let widened = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        return widened == frame ? nil : widened
    }
}

extension StripAvoidance {
    /// タイトルバーのダブルクリック（広げる・元に戻す）を、ステージの範囲で続けて使えるようにするための覚え書き
    public struct ZoomMemory: Equatable, Sendable {
        /// 広げる前の枠（もう一度ダブルクリックしたら、ここへ戻す）
        public var restore: CGRect?
        /// Pinstage が収めた枠（ウインドウがこの枠のままなら、収めたままの状態）
        public var adjusted: CGRect?

        public init(restore: CGRect? = nil, adjusted: CGRect? = nil) {
            self.restore = restore
            self.adjusted = adjusted
        }
    }

    /// ウインドウの枠が変わったときに、どこへ動かすか
    ///
    /// - ストリップに重なっていなければ動かさない（ウインドウを利用者が動かしたら、覚え書きを消す）
    /// - 広げた（ステージより広くなった）ら、ステージいっぱいに収め、広げる前の枠を覚える
    /// - 収めたままの状態からもう一度広げた（ダブルクリックをもう一度）なら、広げる前の枠に戻す
    /// - Parameters:
    ///   - current: いまの枠
    ///   - previous: 前に見たときの枠
    ///   - memory: 覚え書き
    ///   - stage: ステージの範囲
    ///   - edge: ストリップのある辺
    /// - Returns: 動かす先（動かさなければ nil）と、新しい覚え書き
    public static func resolve(current: CGRect, previous: CGRect?, memory: ZoomMemory, stage: CGRect, edge: StripEdge) -> (target: CGRect?, memory: ZoomMemory) {
        guard let fitted = adjusted(current, stage: stage, edge: edge) else {
            // 重なっていない。収めたままなら覚え書きを残し、利用者が動かしていたら消す
            return (nil, current == memory.adjusted ? memory : ZoomMemory())
        }
        // ストリップのある向きに、ステージいっぱいより広いか（左右のストリップなら幅、上下なら高さ）
        let isWide = edge.isHorizontal
            ? current.height >= stage.height - tolerance
            : current.width >= stage.width - tolerance
        if isWide, let restore = memory.restore, previous == memory.adjusted, adjusted(restore, stage: stage, edge: edge) == nil {
            // 収めたままの状態から、もう一度広げた → 広げる前の大きさに戻す（ダブルクリックで元に戻す）
            return (restore, ZoomMemory())
        }
        let restore: CGRect? = if isWide {
            previous.flatMap { adjusted($0, stage: stage, edge: edge) == nil && $0 != memory.adjusted ? $0 : nil } ?? memory.restore
        } else {
            nil
        }
        return (fitted, ZoomMemory(restore: restore, adjusted: fitted))
    }
}
