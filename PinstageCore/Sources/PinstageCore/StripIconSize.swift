import CoreGraphics

/// ストリップの大きさ（どの形式にもかかる。「小」は、一覧・サムネイルのいままでの大きさ）
public enum StripIconSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small
    case medium
    case large

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }

    // MARK: アイコンの並び

    /// アイコンの並びの、アイコンの一辺（pt）。「小」は一覧のアイコンと同じ
    public var iconSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 28
        case .large: 36
        }
    }

    /// アイコン 1 つ分（タイル）の幅のいちばん小さい値（pt）。ストリップの幅に、この幅で入るだけ並べる
    public var tileWidth: CGFloat {
        iconSize + 14
    }

    /// タイルの高さ（pt）
    public var tileHeight: CGFloat {
        switch self {
        case .small: 30
        case .medium: 38
        case .large: 44
        }
    }

    /// 左右に出したストリップの、アイコンの並びのいちばん狭い幅（pt。アイコンが 1 列に並ぶ幅。上の帯のボタンとグループのタイルも収まる）
    public var minimumStripWidth: CGFloat {
        switch self {
        case .small: 52
        case .medium: 58
        case .large: 64
        }
    }

    // MARK: 一覧

    /// 一覧の行の高さ（pt。ウインドウの数では変えない）。「小」はブラウザの縦のタブと同じくらい
    public var listRowHeight: CGFloat {
        switch self {
        case .small: 34
        case .medium: 42
        case .large: 50
        }
    }

    /// 一覧のアイコンの一辺（pt）
    public var listIconSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 24
        case .large: 30
        }
    }

    /// 一覧の名前の文字の大きさ（pt）
    public var listFontSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 14
        case .large: 15
        }
    }

    // MARK: サムネイル

    /// サムネイルの高さ（pt）
    public var thumbnailHeight: CGFloat {
        switch self {
        case .small: 84
        case .medium: 112
        case .large: 140
        }
    }

    /// サムネイルの左下に添える、アプリのアイコンの一辺（pt）
    public var thumbnailBadgeSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 22
        case .large: 26
        }
    }

    /// サムネイルの下の、名前の文字の大きさ（pt。nil なら、いままでどおり .caption）
    public var thumbnailFontSize: CGFloat? {
        switch self {
        case .small: nil
        case .medium: 12
        case .large: 13
        }
    }
}

/// ウインドウの行の描き方（形式と大きさから決まる）
public enum StripRowKind: Equatable, Sendable {
    /// アイコンの並びの 1 つ（タイル）
    case tile(StripIconSize)
    /// 一覧の 1 行
    case list(StripIconSize)
    /// サムネイル
    case thumbnail(StripIconSize)

    /// 大きさ
    public var size: StripIconSize {
        switch self {
        case .tile(let size), .list(let size), .thumbnail(let size): size
        }
    }

    /// アイコンだけを描くか（名前はポインタを乗せると出す）
    public var showsIconOnly: Bool {
        if case .tile = self { return true }
        return false
    }

    /// サムネイルか
    public var isThumbnail: Bool {
        if case .thumbnail = self { return true }
        return false
    }

    /// 一覧か
    public var isList: Bool {
        if case .list = self { return true }
        return false
    }

    /// アイコンの一辺（pt）。サムネイルでは、まだ撮っていないときに真ん中に出すアイコンの、もとの大きさ
    public var iconSize: CGFloat {
        switch self {
        case .tile(let size): size.iconSize
        case .list(let size): size.listIconSize
        case .thumbnail(let size): size.thumbnailBadgeSize + 10
        }
    }
}
