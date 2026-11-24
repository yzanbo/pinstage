import CoreGraphics

/// ストリップのウインドウの行の高さ（形式と大きさで決まる。ウインドウの数では変えない）
public enum StripRowSizing {
    /// 行と行の間（一覧と、小さなアイコンは、タブのように詰める）
    public static func spacing(kind: StripRowKind) -> CGFloat {
        switch kind {
        case .list, .tile(.small): 4
        case .tile, .thumbnail: 6
        }
    }

    /// 行の描き方に合わせた、行のいちばん低い高さ。ウインドウが少なくても、縦いっぱいには広げない。
    /// 一覧・アイコンは大きさで決まった高さ。サムネイルは 0（中身の高さのまま。サムネイルの高さは大きさで決まり、名前の行の高さは文字の大きさで変わる）
    public static func rowHeight(kind: StripRowKind) -> CGFloat {
        switch kind {
        case .list(let size): size.listRowHeight
        case .tile(let size): size.tileHeight
        case .thumbnail: 0
        }
    }

    // MARK: - アイコンの並び（左右に出したときの格子）

    /// 格子の列の数（タイルのいちばん小さい幅で、使える幅に入るだけ。いつも 1 列以上）
    /// - Parameters:
    ///   - width: 一覧に使える幅
    ///   - tileWidth: タイルのいちばん小さい幅
    ///   - spacing: タイルの間
    public static func gridColumns(width: CGFloat, tileWidth: CGFloat, spacing: CGFloat) -> Int {
        guard width > 0, tileWidth > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (tileWidth + spacing)).rounded(.down)))
    }

    /// アイコンの格子の並べ方（列の数と、左右の余白）
    public struct GridLayout: Equatable, Sendable {
        public let columns: Int
        /// 左右の余白（行の端のアイコンの外にも、落とす位置の縦の線を引けるように空ける）
        public let sideMargin: CGFloat
    }

    /// アイコンの格子の並べ方を決める。
    /// 複数の列のときは、左右に余白を空ける（行の端の線のため）。ただし、余白を空けると列が減るときは空けない（線は端の内側に寄せて引ける）。
    /// 1 列のときは、線は横（アイコンとアイコンの間）なので空けない
    /// - Parameters:
    ///   - width: 一覧に使える幅（余白を含む）
    ///   - sideMargin: 空けたい左右の余白
    public static func gridLayout(width: CGFloat, tileWidth: CGFloat, spacing: CGFloat, sideMargin: CGFloat) -> GridLayout {
        let columns = gridColumns(width: width, tileWidth: tileWidth, spacing: spacing)
        guard columns > 1, gridColumns(width: width - sideMargin * 2, tileWidth: tileWidth, spacing: spacing) == columns else {
            return GridLayout(columns: columns, sideMargin: 0)
        }
        return GridLayout(columns: columns, sideMargin: sideMargin)
    }

    /// 格子で、その番号のタイルが行の右端か（次のタイルは次の行の左端に折り返す。1 列なら、どれも端ではなく縦に続く）
    public static func isLineEnd(_ index: Int, columns: Int) -> Bool {
        columns > 1 && index % columns == columns - 1
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
