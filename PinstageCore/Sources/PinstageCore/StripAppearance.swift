import CoreGraphics
import Foundation

/// ストリップの見た目（ウインドウの並べ方とサムネイルを、1 つにまとめたもの）
///
/// 行の大きさは選ばせない。一覧は、ブラウザの縦のタブと同じくらいの決まった高さの 1 行。
/// サムネイル・細い帯は、ウインドウの数に合わせて縦いっぱいに広がり、その高さで中身の大きさを決める。
public enum StripItemSize: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 細い帯（ストリップごと細くして、アイコンだけを縦に並べる。名前はポインタを乗せると出す）
    case icons
    /// アイコンの並び（ストリップの幅はそのままで、ウインドウをアイコンだけで何個か並べる）
    case grid
    /// 一覧（アイコンと名前を 1 行で。ブラウザの縦のタブと同じくらいの大きさ）
    case list
    /// サムネイル（ウインドウの中身を映す。画面収録の許可が要る）
    case thumbnail

    public var id: String { rawValue }

    /// 保存した値から読む（見た目を 4 つにまとめる前の値も、まとめた先に読み替える）
    public init?(storedValue: String) {
        switch storedValue {
        case "small", "medium": self = .list
        case "thumbnailMedium", "thumbnailLarge": self = .thumbnail
        default: self.init(rawValue: storedValue)
        }
    }

    public var title: String {
        switch self {
        case .icons: "細い帯（アイコンだけ）"
        case .grid: "アイコンの並び"
        case .list: "一覧"
        case .thumbnail: "サムネイル"
        }
    }

    /// 見出しのメニューに出す印
    public var symbolName: String {
        switch self {
        case .icons: "sidebar.left"
        case .grid: "square.grid.3x2"
        case .list: "list.bullet.rectangle"
        case .thumbnail: "photo"
        }
    }

    /// アイコンの一辺（pt）
    public var iconSize: CGFloat {
        switch self {
        case .icons, .grid: 36
        case .list: 18
        case .thumbnail: 28
        }
    }

    /// サムネイルのいちばん低い高さ（pt）。サムネイルの見た目のときだけ。行が高ければ、それに合わせて大きくする
    public var thumbnailHeight: CGFloat {
        self == .thumbnail ? 84 : 0
    }

    /// サムネイルを出すか（画面収録の許可が要る）
    public var showsThumbnails: Bool {
        thumbnailHeight > 0
    }

    /// ストリップごと細い帯にするか
    public var isIconOnly: Bool {
        self == .icons
    }

    /// ウインドウをアイコンの並び（タイル）で出すか
    public var showsTiles: Bool {
        self == .grid
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
    public var itemSize: StripItemSize
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
    /// ストリップの幅（pt。右の縁をドラッグして変える）
    public var stripWidth: CGFloat {
        didSet { stripWidth = StripGeometry.clampedWidth(stripWidth) }
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
        keepsWindowsOffStrip: Bool = true
    ) {
        self.mode = mode
        self.itemSize = itemSize
        self.visibleCount = Self.clampedCount(visibleCount)
        self.displays = displays
        self.stripWidth = StripGeometry.clampedWidth(stripWidth)
        self.showsOtherSpaces = showsOtherSpaces
        self.showsOtherDisplays = showsOtherDisplays
        self.keepsWindowsOffStrip = keepsWindowsOffStrip
    }

    /// サムネイルを撮るか（サムネイルの見た目のとき）
    public var capturesThumbnails: Bool {
        itemSize.showsThumbnails
    }

    /// いまのストリップの幅（アイコンだけのときは細い幅に決める。そのほかは、右の縁で変えた幅）
    public var effectiveWidth: CGFloat {
        itemSize.isIconOnly ? StripGeometry.iconOnlyWidth : stripWidth
    }

    private static func clampedCount(_ count: Int) -> Int {
        min(max(count, visibleCountRange.lowerBound), visibleCountRange.upperBound)
    }

    private enum Key {
        static let mode = "strip.mode"
        static let itemSize = "strip.itemSize"
        static let visibleCount = "strip.visibleCount"
        static let displays = "strip.displays"
        static let stripWidth = "strip.width"
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
            keepsWindowsOffStrip: defaults.object(forKey: Key.keepsWindowsOffStrip) as? Bool ?? fallback.keepsWindowsOffStrip
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: Key.mode)
        defaults.set(itemSize.rawValue, forKey: Key.itemSize)
        defaults.set(visibleCount, forKey: Key.visibleCount)
        defaults.set(displays.rawValue, forKey: Key.displays)
        defaults.set(Double(stripWidth), forKey: Key.stripWidth)
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
