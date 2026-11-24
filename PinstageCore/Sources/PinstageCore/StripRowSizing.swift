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
        case .list: listRowHeight
        case .thumbnail: 320
        }
    }

    /// 一覧の行の高さ（ブラウザの縦のタブと同じくらい。ウインドウの数で変えない）
    public static let listRowHeight: CGFloat = 34

    /// 行と行の間（一覧は、タブのように詰める）
    public static func spacing(size: StripItemSize) -> CGFloat {
        size == .list ? 4 : 6
    }

    /// 見た目に合わせた行の高さ。一覧は決まった高さ、ほかは一覧の高さに収まるよう広げた高さ
    public static func rowHeight(size: StripItemSize, available: CGFloat, count: Int, footer: CGFloat) -> CGFloat {
        if size == .list { return listRowHeight }
        return rowHeight(available: available, count: count, spacing: spacing(size: size), footer: footer, maximum: maximumRowHeight(size: size))
    }
}
