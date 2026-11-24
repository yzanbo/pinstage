import CoreGraphics
import Foundation

/// ストリップの形式（ウインドウをどう並べるか）
///
/// 大きさ（StripIconSize）は、どの形式にもかかる。一覧は、決まった高さの 1 行（「小」はブラウザの縦のタブと同じくらい）。
/// サムネイルは、大きさで決まる高さより低くはせず、ウインドウが少なければ縦いっぱいに広げる。
/// アイコンの並びは、ストリップを 1 列まで狭められる（細い帯になる）。
public enum StripItemSize: String, CaseIterable, Codable, Sendable, Identifiable {
    /// アイコンの並び（ウインドウをアイコンだけで並べる。名前はポインタを乗せると出す）
    case grid
    /// 一覧（アイコンと名前を 1 行で。ブラウザの縦のタブと同じくらいの大きさ）
    case list
    /// サムネイル（ウインドウの中身を映す。画面収録の許可が要る）
    case thumbnail

    public var id: String { rawValue }

    /// 保存した値から読む（見た目をまとめる前の値も、まとめた先に読み替える）
    public init?(storedValue: String) {
        switch storedValue {
        case "small", "medium": self = .list
        case "icons": self = .grid
        case "thumbnailMedium", "thumbnailLarge": self = .thumbnail
        default: self.init(rawValue: storedValue)
        }
    }

    public var title: String {
        switch self {
        case .grid: "アイコンの並び"
        case .list: "一覧"
        case .thumbnail: "サムネイル"
        }
    }

    /// 見出しのメニューに出す印
    public var symbolName: String {
        switch self {
        case .grid: "square.grid.3x2"
        case .list: "list.bullet.rectangle"
        case .thumbnail: "photo"
        }
    }

    /// サムネイルを出すか（画面収録の許可が要る）
    public var showsThumbnails: Bool {
        self == .thumbnail
    }
}

/// ストリップを出すディスプレイ
public enum StripDisplays: String, CaseIterable, Codable, Sendable, Identifiable {
    /// つないでいるすべてのディスプレイ（ディスプレイごとにステージを持つ）
    case all
    /// メニューバーのあるディスプレイだけ
    case mainOnly

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: "すべてのディスプレイ"
        case .mainOnly: "メインのディスプレイだけ"
        }
    }
}

/// ストリップの設定（UserDefaults に保存する）
public struct StripSettings: Equatable, Sendable {
    public var mode: StripMode
    /// ストリップを出す辺（画面の上下左右）
    public var edge: StripEdge
    /// 形式（ウインドウをどう並べるか）
    public var itemSize: StripItemSize
    /// 大きさ（どの形式にもかかる）
    public var iconSize: StripIconSize
    /// ストリップに並べるウインドウの数（新しく開いた順。残りは「ほかのウインドウ」にたたむ）
    public var visibleCount: Int {
        didSet { visibleCount = Self.clampedCount(visibleCount) }
    }
    public var displays: StripDisplays
    /// ほかのデスクトップ（操作スペース）のウインドウも出すか。オフなら、いま見ているデスクトップのウインドウだけを出す
    public var showsOtherSpaces: Bool
    /// ほかのディスプレイのウインドウも出すか。オフなら、ストリップのあるディスプレイのウインドウだけを出す（ストリップが 1 つのときはすべて）
    public var showsOtherDisplays: Bool
    /// 常に出しているときに、ウインドウをストリップに重ねない（重なったら、ステージの範囲に収める）
    public var keepsWindowsOffStrip: Bool
    /// 左右に出したときのストリップの幅（pt。ステージの側の縁をドラッグして変える）。一覧・サムネイルの幅
    public var stripWidth: CGFloat {
        didSet { stripWidth = StripGeometry.clampedWidth(stripWidth) }
    }
    /// 左右に出したときの、アイコンの並びの幅（pt）。一覧・サムネイルとは別に覚える（1 列まで狭められる）
    public var gridWidth: CGFloat {
        didSet { gridWidth = Self.clampedGridWidth(gridWidth) }
    }

    public static let visibleCountRange = 3...30
    public static let `default` = StripSettings(
        mode: .alwaysShown,
        itemSize: .list,
        visibleCount: 8,
        displays: .all,
        stripWidth: StripGeometry.defaultWidth
    )

    public init(
        mode: StripMode,
        itemSize: StripItemSize,
        visibleCount: Int,
        displays: StripDisplays,
        stripWidth: CGFloat = StripGeometry.defaultWidth,
        showsOtherSpaces: Bool = false,
        showsOtherDisplays: Bool = false,
        keepsWindowsOffStrip: Bool = true,
        edge: StripEdge = .left,
        iconSize: StripIconSize = .small,
        gridWidth: CGFloat = StripGeometry.defaultWidth
    ) {
        self.mode = mode
        self.edge = edge
        self.itemSize = itemSize
        self.iconSize = iconSize
        self.visibleCount = Self.clampedCount(visibleCount)
        self.displays = displays
        self.stripWidth = StripGeometry.clampedWidth(stripWidth)
        self.gridWidth = Self.clampedGridWidth(gridWidth)
        self.showsOtherSpaces = showsOtherSpaces
        self.showsOtherDisplays = showsOtherDisplays
        self.keepsWindowsOffStrip = keepsWindowsOffStrip
    }

    /// サムネイルを撮るか（サムネイルの形式のとき）
    public var capturesThumbnails: Bool {
        itemSize.showsThumbnails
    }

    /// ウインドウの行の描き方（形式と大きさから決まる）
    public var rowKind: StripRowKind {
        switch itemSize {
        case .grid: .tile(iconSize)
        case .list: .list(iconSize)
        case .thumbnail: .thumbnail(iconSize)
        }
    }

    /// 左右に出したときの、いまの形式の幅の範囲。アイコンの並びは、1 列になる幅まで狭められる
    public var widthRange: ClosedRange<CGFloat> {
        let upper = StripGeometry.widthRange.upperBound
        return itemSize == .grid ? iconSize.minimumStripWidth...upper : StripGeometry.widthRange
    }

    /// 左右に出したときの、いまの形式の幅（範囲の中に収めた値）
    public var width: CGFloat {
        get {
            let range = widthRange
            return min(max(itemSize == .grid ? gridWidth : stripWidth, range.lowerBound), range.upperBound)
        }
        set {
            if itemSize == .grid {
                gridWidth = newValue
            } else {
                stripWidth = newValue
            }
        }
    }

    /// いまのストリップの厚み（左右なら幅、上下なら、行の描き方で決まる高さ）。ステージの範囲は、この厚みで決める
    public var effectiveThickness: CGFloat {
        edge.isHorizontal ? StripRowSizing.barThickness(kind: rowKind) : width
    }

    private static func clampedCount(_ count: Int) -> Int {
        min(max(count, visibleCountRange.lowerBound), visibleCountRange.upperBound)
    }

    /// アイコンの並びの幅を、どの大きさでも入りうる範囲に収める（大きさに合わせた下限は、width で使うときに当てる）
    private static func clampedGridWidth(_ width: CGFloat) -> CGFloat {
        min(max(width, StripIconSize.small.minimumStripWidth), StripGeometry.widthRange.upperBound)
    }

    private enum Key {
        static let mode = "strip.mode"
        static let edge = "strip.edge"
        static let itemSize = "strip.itemSize"
        static let iconSize = "strip.iconSize"
        /// 大きさを、アイコンの並びだけにかけていたときの値（読み替える）
        static let legacyGridIconSize = "strip.gridIconSize"
        static let visibleCount = "strip.visibleCount"
        static let displays = "strip.displays"
        static let stripWidth = "strip.width"
        static let gridWidth = "strip.gridWidth"
        static let showsOtherSpaces = "strip.showsOtherSpaces"
        static let showsOtherDisplays = "strip.showsOtherDisplays"
        static let keepsWindowsOffStrip = "strip.keepsWindowsOffStrip"
    }

    /// 保存した設定を読む（なければ初期設定）
    public init(defaults: UserDefaults) {
        let fallback = Self.default
        self.init(
            mode: defaults.string(forKey: Key.mode).flatMap(StripMode.init(rawValue:)) ?? fallback.mode,
            itemSize: defaults.string(forKey: Key.itemSize).flatMap(StripItemSize.init(storedValue:)) ?? fallback.itemSize,
            visibleCount: defaults.object(forKey: Key.visibleCount) as? Int ?? fallback.visibleCount,
            displays: defaults.string(forKey: Key.displays).flatMap(StripDisplays.init(rawValue:)) ?? fallback.displays,
            stripWidth: (defaults.object(forKey: Key.stripWidth) as? Double).map { CGFloat($0) } ?? fallback.stripWidth,
            showsOtherSpaces: defaults.object(forKey: Key.showsOtherSpaces) as? Bool ?? fallback.showsOtherSpaces,
            showsOtherDisplays: defaults.object(forKey: Key.showsOtherDisplays) as? Bool ?? fallback.showsOtherDisplays,
            keepsWindowsOffStrip: defaults.object(forKey: Key.keepsWindowsOffStrip) as? Bool ?? fallback.keepsWindowsOffStrip,
            edge: defaults.string(forKey: Key.edge).flatMap(StripEdge.init(rawValue:)) ?? fallback.edge,
            iconSize: (defaults.string(forKey: Key.iconSize) ?? defaults.string(forKey: Key.legacyGridIconSize))
                .flatMap(StripIconSize.init(rawValue:)) ?? fallback.iconSize,
            gridWidth: (defaults.object(forKey: Key.gridWidth) as? Double).map { CGFloat($0) } ?? fallback.gridWidth
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Key.mode)
        defaults.set(edge.rawValue, forKey: Key.edge)
        defaults.set(itemSize.rawValue, forKey: Key.itemSize)
        defaults.set(iconSize.rawValue, forKey: Key.iconSize)
        defaults.set(visibleCount, forKey: Key.visibleCount)
        defaults.set(displays.rawValue, forKey: Key.displays)
        defaults.set(Double(stripWidth), forKey: Key.stripWidth)
        defaults.set(Double(gridWidth), forKey: Key.gridWidth)
        defaults.set(showsOtherSpaces, forKey: Key.showsOtherSpaces)
        defaults.set(showsOtherDisplays, forKey: Key.showsOtherDisplays)
        defaults.set(keepsWindowsOffStrip, forKey: Key.keepsWindowsOffStrip)
    }
}

/// ストリップのウインドウの並び（一度並べた順番は変えず、新しく開いたものを先頭に足す）
public enum RecentOrder {
    /// いまあるものに合わせる（なくなったものは除き、新しいものは先頭に足す）
    public static func syncing<ID: Hashable>(_ order: [ID], with current: [ID]) -> [ID] {
        let currentSet = Set(current)
        let kept = order.filter { currentSet.contains($0) }
        let keptSet = Set(kept)
        let added = current.filter { !keptSet.contains($0) }
        return added + kept
    }
}
