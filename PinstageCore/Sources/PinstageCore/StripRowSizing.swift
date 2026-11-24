import CoreGraphics

/// ストリップのウインドウの行の高さ（ウインドウが少ないときは、行を大きくして縦いっぱいに並べる）
public enum StripRowSizing {
    /// 一覧の高さに収まるよう、行を同じ高さで広げたときの高さ（上限まで）
    ///
    /// 返した高さは「いちばん低い高さ」として使う。中身の高さより低ければ中身の高さのまま（収まらなければスクロール）。
    /// - Parameters:
    ///   - available: 一覧に使える高さ
    ///   - count: 行の数
    ///   - spacing: 行と行の間
    ///   - footer: 行の下に並べるもの（「ほかのウインドウ」のボタンなど）の高さ
    ///   - maximum: 行の高さの上限（間延びしないように）
    public static func rowHeight(available: CGFloat, count: Int, spacing: CGFloat, footer: CGFloat, maximum: CGFloat) -> CGFloat {
        guard count > 0, available > 0 else { return 0 }
        let height = (available - footer - spacing * CGFloat(count - 1)) / CGFloat(count)
        return max(0, min(height, maximum))
    }

    /// 行の高さの上限（見た目で変える）
    public static func maximumRowHeight(size: StripItemSize) -> CGFloat {
        switch size {
        case .icons, .grid: 64
        case .list: 96
        case .thumbnail: 320
        }
    }

    /// 一覧を 2 行（アプリ名つき）で出せる、行のいちばん低い高さ（アイコン 32pt と上下の余白）
    public static let twoLineHeight: CGFloat = 44

    /// 一覧の行を 2 行で出すか（ウインドウが多くて行が詰まるときは、1 行にして多く並べる）
    public static func showsTwoLines(rowHeight: CGFloat) -> Bool {
        rowHeight >= twoLineHeight
    }
}
