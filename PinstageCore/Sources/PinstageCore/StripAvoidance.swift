import CoreGraphics

/// ウインドウを、常に出しているストリップに重ねない（タイトルバーのダブルクリックなどで広がったとき、ステージの範囲に収める）
public enum StripAvoidance {
    /// これより小さいはみ出しは、気にしない（pt）
    public static let tolerance: CGFloat = 2

    /// ストリップに重なっていれば、ステージの範囲に収めた枠（重なっていなければ nil）
    ///
    /// - 画面いっぱいなど、ステージより広いウインドウは、ステージいっぱいにする
    /// - 重なっているだけのウインドウは、大きさを変えずに右へずらす（収まらなければ縮める）
    /// - Parameters:
    ///   - frame: ウインドウの枠（ステージと同じ座標）
    ///   - stage: ステージの範囲（ストリップの右側）
    public static func adjusted(_ frame: CGRect, stage: CGRect) -> CGRect? {
        // ステージの左端より左（ストリップのほう）にはみ出していなければ、そのまま
        guard frame.minX < stage.minX - tolerance, frame.maxX > stage.minX - stage.width else { return nil }
        let fitted = StageLayout.fit(frame, into: stage)
        return fitted == frame ? nil : fitted
    }

    /// ストリップを狭めてステージの左端が左へ動いたとき、前の左端にくっつけていたウインドウを、新しい左端まで広げた枠（右端はそのまま）。
    /// くっついていなかったウインドウ・左端が左へ動いていないときは nil（動かさない）
    public static func following(_ frame: CGRect, stageLeftFrom oldLeft: CGFloat, to newLeft: CGFloat) -> CGRect? {
        guard newLeft < oldLeft, abs(frame.minX - oldLeft) <= tolerance else { return nil }
        return CGRect(x: newLeft, y: frame.minY, width: frame.maxX - newLeft, height: frame.height)
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
    /// - Returns: 動かす先（動かさなければ nil）と、新しい覚え書き
    public static func resolve(current: CGRect, previous: CGRect?, memory: ZoomMemory, stage: CGRect) -> (target: CGRect?, memory: ZoomMemory) {
        guard let fitted = adjusted(current, stage: stage) else {
            // 重なっていない。収めたままなら覚え書きを残し、利用者が動かしていたら消す
            return (nil, current == memory.adjusted ? memory : ZoomMemory())
        }
        let isWide = current.width >= stage.width - tolerance
        if isWide, let restore = memory.restore, previous == memory.adjusted, adjusted(restore, stage: stage) == nil {
            // 収めたままの状態から、もう一度広げた → 広げる前の大きさに戻す（ダブルクリックで元に戻す）
            return (restore, ZoomMemory())
        }
        let restore: CGRect? = if isWide {
            previous.flatMap { adjusted($0, stage: stage) == nil && $0 != memory.adjusted ? $0 : nil } ?? memory.restore
        } else {
            nil
        }
        return (fitted, ZoomMemory(restore: restore, adjusted: fitted))
    }
}
