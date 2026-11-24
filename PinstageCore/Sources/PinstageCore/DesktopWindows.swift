import Foundation

/// 1 つのデスクトップ（操作スペース）のストリップが覚える、そのデスクトップのウインドウの一覧
///
/// ストリップはデスクトップごとに置く。ほかのデスクトップを見ている間も、この一覧を持ったままにしておくと、
/// 切り替えの動きの途中から、行き先のデスクトップの一覧が出ている。
public struct DesktopWindows<Window: Hashable>: Equatable {
    /// 覚えている一覧（そのデスクトップで、画面に出ていたウインドウ）
    public private(set) var windows: Set<Window> = []
    /// そのデスクトップだけが画面に出ているときの一覧で、覚えたことがあるか
    public private(set) var isConfirmed = false
    /// 一覧に入った時刻（切り替えの途中に紛れ込んだものを、あとで外すため）
    private var addedAt: [Window: TimeInterval] = [:]

    public init() {}

    /// 一覧を入れ替える（残るウインドウの、入った時刻はそのまま）
    mutating func replace(with new: Set<Window>, at now: TimeInterval, confirmed: Bool) {
        if confirmed { isConfirmed = true }
        guard new != windows else { return }
        addedAt = addedAt.filter { new.contains($0.key) }
        for window in new where addedAt[window] == nil {
            addedAt[window] = now
        }
        windows = new
    }

    /// 少し前に入ったばかりで、いまはほかのデスクトップに出ているウインドウを外す（切り替えの途中に紛れ込んだもの）。
    /// 前から入っているウインドウは外さない（すべてのデスクトップに出すウインドウを、消さないように）
    mutating func removeStrays(shownElsewhere others: Set<Window>, at now: TimeInterval, within interval: TimeInterval) {
        let strays = windows.filter { window in
            guard others.contains(window), let added = addedAt[window] else { return false }
            return now - added < interval
        }
        guard !strays.isEmpty else { return }
        windows.subtract(strays)
        for window in strays {
            addedAt[window] = nil
        }
    }
}

/// 画面に出ているウインドウの一覧を、1 回読んだもの
///
/// ウインドウと、このアプリのウインドウ（ストリップ）を、同じ 1 回の一覧から読む。
/// 別々に読むと、デスクトップを切り替えている途中に、ウインドウとストリップの組み合わせが食い違う。
public struct DesktopSnapshot<Window: Hashable> {
    /// フルスクリーンのウインドウがあるディスプレイ
    public enum Display: Equatable, Sendable {
        case known(String)
        /// 枠が読めず、どのディスプレイか分からない
        case unknown
    }

    /// 画面に出ているウインドウ（最小化したもの・隠したアプリのものは入らない）
    public var onScreen: Set<Window>
    /// そのうち、フルスクリーンのもの（値は、あるディスプレイ）
    public var fullScreen: [Window: Display]
    /// 画面に出ている、このアプリのウインドウの番号（どのストリップが画面に出ているかを見分ける）
    public var ownWindowNumbers: Set<Int>

    public init(onScreen: Set<Window>, fullScreen: [Window: Display], ownWindowNumbers: Set<Int>) {
        self.onScreen = onScreen
        self.fullScreen = fullScreen
        self.ownWindowNumbers = ownWindowNumbers
    }

    /// そのディスプレイのデスクトップの、ストリップが覚えるウインドウ
    ///
    /// フルスクリーンのウインドウは入れない（自分だけのデスクトップにあり、切り替えの途中だけ画面に出る）。
    /// ディスプレイごとにデスクトップを切り替える設定のときは、ほかのディスプレイのフルスクリーンのウインドウは入れる（そこに出たままなので）。
    /// - Parameter separateSpaces: ディスプレイごとにデスクトップを切り替える設定か
    public func windows(onDisplay display: String, separateSpaces: Bool) -> Set<Window> {
        guard !fullScreen.isEmpty else { return onScreen }
        return onScreen.filter { window in
            switch fullScreen[window] {
            case nil: true
            case .known(let other): separateSpaces && other != display
            case .unknown: false
            }
        }
    }

    /// そのディスプレイに、フルスクリーンのウインドウが出ているか（フルスクリーンのデスクトップには、ストリップを出さない）。
    /// デスクトップがすべてのディスプレイにまたがる設定のときは、どのディスプレイのものでも同じデスクトップ
    public func showsFullScreenWindow(onDisplay display: String, separateSpaces: Bool) -> Bool {
        guard !fullScreen.isEmpty else { return false }
        guard separateSpaces else { return true }
        return fullScreen.values.contains { $0 == .unknown || $0 == .known(display) }
    }
}

/// 「画面に出ているウインドウの一覧」を、どのデスクトップのものとして覚えるかを決める
///
/// 操作スペースを扱う公開の API はないので、ストリップのウインドウを目印にする。
/// 一覧を読んだとき、同じ一覧の中に出ているストリップが、そのデスクトップのストリップ。
///
/// - 1 つだけ出ている: その一覧を、そのストリップに覚えさせる
/// - 2 つ以上出ている: デスクトップを切り替えている途中（両方のデスクトップのウインドウが画面に出ている）。
///   どちらの一覧か分からないので、覚えた一覧は変えない（変えると、行き先のストリップに、前のデスクトップのウインドウが混ざる）
/// - 1 つも出ていない: ストリップのないデスクトップ（フルスクリーンなど）
public enum DesktopAttribution {
    /// 一覧に入ってからこの秒数までのウインドウは、切り替えの途中に紛れ込んだものかもしれないと見なす
    public static let strayInterval: TimeInterval = 5
    /// 画面に出ているストリップと、表に出ているデスクトップのストリップが食い違っても、この秒数までは切り替えの途中と見なす。
    /// それより長く食い違ったままなら、画面に出ているほうを信じる
    public static let disagreementTolerance: TimeInterval = 2
    /// 1 つのデスクトップに重なったストリップを、1 つにするまで待つ秒数（切り替えの途中の見間違いで閉じないように）
    public static let overlapDelay: TimeInterval = 1
    /// 作ったばかりのストリップを、一覧に出ていなくても、いまのデスクトップにあるものとして扱う秒数
    /// （自分のウインドウを出した結果は、次の描画まで「画面に出ているウインドウの一覧」に出てこない）
    public static let newStripGrace: TimeInterval = 1

    public enum Outcome: Equatable {
        /// その番号のストリップに覚えさせた
        case remembered(Int)
        /// 切り替えの途中なので、覚えた一覧を変えなかった
        case switching
        /// ストリップのないデスクトップにいる
        case noStrip
    }

    /// 1 つのディスプレイの、デスクトップごとの一覧を更新する（表に出ているデスクトップのストリップとも照らし合わせる）
    ///
    /// 初めて行くデスクトップへ切り替えた直後は、前のデスクトップのストリップだけが、まだ画面に出ている。
    /// そのストリップは、もう表に出ているデスクトップのものではないので、行き先のウインドウを覚えさせない。
    /// - Parameters:
    ///   - isOnActiveSpace: それぞれのストリップが、表に出ているデスクトップにあるか（AppKit の答え。desktops と同じ並び）
    ///   - disagreeingSince: 2 つの見え方が食い違い始めた時刻（食い違っていなければ nil。呼ぶたびに渡し直す）
    @discardableResult
    public static func update<Window: Hashable>(
        _ desktops: inout [DesktopWindows<Window>],
        isOnScreen: [Bool],
        isOnActiveSpace: [Bool],
        disagreeingSince: inout TimeInterval?,
        windows: Set<Window>,
        at now: TimeInterval
    ) -> Outcome {
        let present = indices(of: isOnScreen)
        if present.count <= 1, present != indices(of: isOnActiveSpace) {
            let since = disagreeingSince ?? now
            disagreeingSince = since
            if now - since < disagreementTolerance { return .switching }
        } else {
            disagreeingSince = nil
        }
        return update(&desktops, isOnScreen: isOnScreen, windows: windows, at: now)
    }

    /// 1 つのディスプレイの、デスクトップごとの一覧を更新する
    /// - Parameters:
    ///   - desktops: そのディスプレイのストリップ（デスクトップごと）が覚えている一覧
    ///   - isOnScreen: それぞれのストリップが、読んだ一覧の中に出ているか（desktops と同じ並び）
    ///   - windows: 読んだ一覧に出ているウインドウ
    ///   - now: 読んだ時刻（秒。起動してからの時間など、戻らない時計）
    @discardableResult
    public static func update<Window: Hashable>(
        _ desktops: inout [DesktopWindows<Window>],
        isOnScreen: [Bool],
        windows: Set<Window>,
        at now: TimeInterval
    ) -> Outcome {
        let present = indices(of: isOnScreen).filter(desktops.indices.contains)
        switch present.count {
        case 0:
            // ほかのデスクトップのストリップから、切り替えの途中に紛れ込んだもの（いま、ここに出ているウインドウ）を外す
            for index in desktops.indices {
                desktops[index].removeStrays(shownElsewhere: windows, at: now, within: strayInterval)
            }
            return .noStrip
        case 1:
            let current = present[0]
            desktops[current].replace(with: windows, at: now, confirmed: true)
            for index in desktops.indices where index != current {
                desktops[index].removeStrays(shownElsewhere: windows, at: now, within: strayInterval)
            }
            return .remembered(current)
        default:
            // まだ一覧を覚えていないストリップにだけ、ほかのストリップが覚えている分を引いたものを仮に入れる
            let known = present
                .filter { desktops[$0].isConfirmed }
                .reduce(into: Set<Window>()) { $0.formUnion(desktops[$1].windows) }
            for index in present where !desktops[index].isConfirmed {
                desktops[index].replace(with: windows.subtracting(known), at: now, confirmed: false)
            }
            return .switching
        }
    }

    /// true の番号
    private static func indices(of flags: [Bool]) -> [Int] {
        flags.indices.filter { flags[$0] }
    }

    // MARK: - ストリップの置き方

    /// 1 つのディスプレイの、いまのデスクトップのストリップをどうするか
    public enum Placement: Equatable {
        /// そのまま
        case keep
        /// どちらで見てもストリップがない（初めて訪れたデスクトップか、フルスクリーンなどストリップを出さないデスクトップ）
        case missing
        /// 1 つのデスクトップに重なっているので、keep だけを残して close を閉じる（デスクトップを消したときなど）
        case merge(keep: Int, close: [Int])
    }

    /// いまのデスクトップに、ストリップが 1 つあるようにするには、どうするかを決める
    /// - Parameters:
    ///   - isOnActiveSpace: それぞれのストリップが、表に出ているデスクトップにあるか（AppKit の答え）
    ///   - isOnScreen: それぞれのストリップが、画面に出ているウインドウの一覧に出ているか
    ///   - isConfirmed: それぞれのストリップが、一覧を覚えたことがあるか（重なったときは、覚えているほうを残す）
    ///   - overlappingSince: 重なっているのを見つけた時刻（重なっていなければ nil。呼ぶたびに渡し直す）
    /// - Returns: isUnsettled は、2 つの見え方が食い違っているか、重なっているか（切り替えの動きの途中。落ち着くまで確かめ直す）
    public static func placement(
        isOnActiveSpace: [Bool],
        isOnScreen: [Bool],
        isConfirmed: [Bool],
        overlappingSince: inout TimeInterval?,
        at now: TimeInterval
    ) -> (placement: Placement, isUnsettled: Bool) {
        let here = indices(of: isOnActiveSpace)
        let shown = indices(of: isOnScreen)
        // 切り替えの動きの途中は、この 2 つが食い違う（前のデスクトップのストリップが、まだ画面に出ている）
        let agree = here == shown
        guard agree, here.count > 1 else {
            overlappingSince = nil
            return (here.isEmpty && shown.isEmpty ? .missing : .keep, !agree)
        }
        guard let since = overlappingSince else {
            overlappingSince = now
            return (.keep, true)
        }
        guard now - since >= overlapDelay else { return (.keep, true) }
        overlappingSince = nil
        let keeper = here.first { isConfirmed.indices.contains($0) && isConfirmed[$0] } ?? here[0]
        return (.merge(keep: keeper, close: here.filter { $0 != keeper }), true)
    }
}

/// 隠されたウインドウ（× で閉じてもウインドウを捨てずに隠すだけのアプリ（LINE など）のもの）の見分け
///
/// macOS は、隠されたウインドウも元のデスクトップにあるものとして扱い続けるので、
/// 「いま見ているデスクトップにあるのに、画面に出ていない」ことで見分ける。
/// 最小化したもの・隠したアプリのもの（floating）は、画面に出ていなくても隠されたものとしない。
public enum HiddenWindows {
    /// - Parameters:
    ///   - spaces: ウインドウごとの、あるデスクトップ（分からないウインドウは入らない）
    ///   - current: いま表に出ているデスクトップ（ディスプレイごと）
    ///   - onScreen: 画面に出ているウインドウ
    ///   - floating: 最小化したもの・隠したアプリのもの
    public static func ids<Window: Hashable>(
        spaces: [Window: Set<UInt64>],
        current: Set<UInt64>,
        onScreen: Set<Window>,
        floating: Set<Window>
    ) -> Set<Window> {
        Set(spaces.compactMap { window, windowSpaces in
            !windowSpaces.isDisjoint(with: current) && !onScreen.contains(window) && !floating.contains(window) ? window : nil
        })
    }
}
