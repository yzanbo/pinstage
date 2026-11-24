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
    ///   - maximum: 行の高さの上限（間延びしないように）
    public static func rowHeight(available: CGFloat, count: Int, spacing: CGFloat, maximum: CGFloat) -> CGFloat {
        guard count > 0, available > 0 else { return 0 }
        let height = (available - spacing * CGFloat(count - 1)) / CGFloat(count)
        return max(0, min(height, maximum))
    }

    /// サムネイルの行の高さの上限（間延びしないように）
    public static let maximumThumbnailRowHeight: CGFloat = 320

    /// 行と行の間（一覧と、小さなアイコンは、タブのように詰める）
    public static func spacing(kind: StripRowKind) -> CGFloat {
        switch kind {
        case .list, .tile(.small): 4
        case .tile, .thumbnail: 6
        }
    }

    /// サムネイルの、名前の行と余白の高さ（行の高さから、これを除いた分がサムネイルの高さ）
    public static let thumbnailCaptionHeight: CGFloat = 34

    /// 行の描き方に合わせた行の高さ。一覧・アイコンは決まった高さ、サムネイルは一覧の高さに収まるよう広げた高さ
    public static func rowHeight(kind: StripRowKind, available: CGFloat, count: Int) -> CGFloat {
        switch kind {
        case .list(let size): size.listRowHeight
        case .tile(let size): size.tileHeight
        // 少ないときに広げる高さ（多いときは小さい値になり、中身の高さのまま。サムネイルの高さの下限は、ビューで大きさから決める）
        case .thumbnail:
            rowHeight(available: available, count: count, spacing: spacing(kind: kind), maximum: maximumThumbnailRowHeight)
        }
    }

    // MARK: - 上下に出したとき（横長の帯）

    /// 横長の帯の、上下の余白（pt）
    public static let barPadding: CGFloat = 7

    /// 横長の帯の、ウインドウ 1 つ分の高さ（行の描き方で決まる。ウインドウの数では変えない）
    public static func barRowHeight(kind: StripRowKind) -> CGFloat {
        switch kind {
        case .tile(let size): size.tileHeight + 2
        case .list(let size): size.listRowHeight
        // 横長の帯のサムネイル（名前の行を含む）
        case .thumbnail(let size): size.thumbnailHeight + 32
        }
    }

    /// 横長の帯の厚み（高さ）
    public static func barThickness(kind: StripRowKind) -> CGFloat {
        barRowHeight(kind: kind) + barPadding * 2
    }

    /// 横長の帯の一覧の、タブ 1 つ分の幅の範囲（「小」はブラウザの横のタブと同じくらい。大きいほど、文字に合わせて広げる）
    public static func tabWidthRange(for size: StripIconSize) -> ClosedRange<CGFloat> {
        switch size {
        case .small: 120...220
        case .medium: 140...240
        case .large: 160...260
        }
    }

    /// 横長の帯の、ウインドウ 1 つ分の幅。
    /// 一覧は、ブラウザのタブのように、使える幅を同じ幅で分ける（範囲の中で。収まらなければスクロール）。ほかは決まった幅
    /// - Parameters:
    ///   - available: 一覧に使える幅
    ///   - count: ウインドウの数
    public static func barItemWidth(kind: StripRowKind, available: CGFloat, count: Int) -> CGFloat {
        switch kind {
        case .tile(let size): return size.tileWidth
        // サムネイルは、画面と同じ横長の形に近づける
        case .thumbnail(let size): return (size.thumbnailHeight * 1.6 + 16).rounded()
        case .list(let size):
            let tabWidthRange = tabWidthRange(for: size)
            guard count > 0, available > 0 else { return tabWidthRange.upperBound }
            let width = (available - spacing(kind: kind) * CGFloat(count - 1)) / CGFloat(count)
            return min(max(width.rounded(.down), tabWidthRange.lowerBound), tabWidthRange.upperBound)
        }
    }
}
