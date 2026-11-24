import AppKit
import Observation
import os
import PinstageCore

/// ステージ（最前面に出すウインドウの組み合わせ）・グループ・型をまとめて扱う本体
///
/// - ディスプレイごとにステージを持つ（ストリップを押したディスプレイのステージを変える）
/// - ストリップのクリック・⌘＋クリック・ドラッグで、ステージの組み合わせを変える
/// - 変えるたびに、そのディスプレイの型で並べて最前面に出す
/// - グループと登録した型は、ファイルに保存して再起動のあとも残す
///
/// グループの保存・編集は StageController+Groups.swift、登録した型は StageController+Layouts.swift にある。
@Observable
final class StageController {
    /// いま開いているウインドウ（ウインドウバーの並び順。新しく開いたものが末尾。ほかのデスクトップのものも含む）
    private(set) var windows: [WindowItem] = []
    /// いま見ているデスクトップ（操作スペース）にあるウインドウ
    private(set) var currentSpaceIDs: Set<AXUIElement> = []
    /// どのデスクトップのストリップにも並べるウインドウ（最小化したもの・隠したアプリのもの。画面に出ていないので、どのデスクトップのものか分からない）
    private(set) var floatingIDs: Set<AXUIElement> = []
    /// いちばん新しく読んだ、画面に出ているウインドウの一覧（読んでいなければ nil）。
    /// ストリップが、自分のデスクトップのウインドウの一覧を覚えるのに使う
    @ObservationIgnored private(set) var desktopSnapshot: DesktopSnapshot<AXUIElement>?
    /// ウインドウごとの、あるデスクトップ（非公開の API で読む。読めないときは nil）。
    /// デスクトップごとのストリップが、自分のデスクトップのウインドウを決めるのに使う
    private(set) var windowSpaces: [AXUIElement: Set<UInt64>]?
    /// 隠されたウインドウ（× で閉じてもウインドウを捨てずに隠すだけのアプリのもの）。ウインドウバーには並べない（並び順の記録には残す）
    private(set) var hiddenWindowIDs: Set<AXUIElement> = []
    /// 最後にデスクトップを切り替えた時刻（切り替えた直後は、行き先のウインドウがまだ画面に出ていないことがあるので、隠されたかを見分けない）
    @ObservationIgnored private var spaceChangedAt: TimeInterval = 0
    /// デスクトップの名前（「デスクトップ 3」など。ディスプレイごとに左から数える。非公開の API で読む）
    private(set) var desktopNames: [UInt64: DesktopName] = [:]
    /// ほかのデスクトップのウインドウを探す（非公開の API）
    @ObservationIgnored private let discovery = OtherSpaceDiscovery()
    /// ウインドウごとの、あるディスプレイ（ディスプレイの鍵。ディスプレイごとのストリップに、そのディスプレイのウインドウを並べるため）
    private(set) var windowDisplays: [AXUIElement: String] = [:]
    /// ディスプレイごとのステージ
    private(set) var board = StageBoard<AXUIElement>()
    /// 保存しているグループと型
    private(set) var library = StageLibrary()
    /// アクセシビリティの許可があるか
    private(set) var isTrusted = AccessibilityPermission.isTrusted
    /// macOS のステージマネージャがオンか（オンだと並べたとおりにならないので、ストリップと設定で知らせる）
    private(set) var isSystemStageManagerOn = SystemStageManager.isEnabled
    /// ステージマネージャの案内を、この起動の間は出さない（利用者が × で閉じた）
    var dismissedStageManagerNotice = false
    /// グループを呼び出している途中か（アプリの起動を待っている間）
    private(set) var recallingGroupID: UUID?
    /// 最後に呼び出したグループ（「次のグループ」「前のグループ」の起点）
    private(set) var lastRecalledGroupID: UUID?
    /// 最後に呼び出したグループを出したディスプレイと、そのとき出したウインドウ
    /// （グループの並べ方を変えたとき、まだそのまま出していれば、その場で並び直すため）
    private(set) var lastRecalledStage: (screenKey: String, windows: Set<AXUIElement>)?
    /// ストリップの設定
    var stripSettings: StripSettings {
        didSet {
            guard stripSettings != oldValue else { return }
            stripSettings.save(to: defaults)
            onStripSettingsChanged?(oldValue)
        }
    }
    /// ウインドウを 1 枚だけ出すときの大きさ
    var singleWindowSize: SingleWindowSize {
        didSet { singleWindowSize.save(to: defaults) }
    }

    /// グループ・型を保存した（「ショートカット」アプリに、グループの一覧が変わったことを知らせるため）
    @ObservationIgnored var onLibraryChanged: (() -> Void)?
    /// ストリップの設定が変わった（変わる前の設定）
    @ObservationIgnored var onStripSettingsChanged: ((StripSettings) -> Void)?

    /// 設定を読み書きする場所（開発用の見本では、本物の設定を書き換えないように、別の場所を渡す）
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let store = StageLibraryStore(fileURL: StageLibraryStore.defaultFileURL())
    @ObservationIgnored private var refreshTimer: Timer?
    /// ディスプレイごとの、並べたあとに枠を確かめ直す仕事（並べ直したら、前の仕事はやめる）
    @ObservationIgnored private var placementChecks: [String: Task<Void, Never>] = [:]
    /// 画面に出ているウインドウの一覧が変わったかを、こまめに確かめるタイマー
    @ObservationIgnored private var windowListTimer: Timer?
    /// 前に確かめたときに画面に出ていた、ほかのアプリのふつうのウインドウの番号（まだ確かめていなければ nil）
    @ObservationIgnored private var onScreenNumbers: Set<Int>?
    /// ウインドウを読み直したときにすること（ストリップが一覧を覚え直す・ストリップに重なったウインドウを戻す）
    @ObservationIgnored private var refreshHandlers: [() -> Void] = []
    @ObservationIgnored private var raiseTask: Task<Void, Never>?
    /// 起動して初めてウインドウを読んだときに、覚えた並び順に並べ直したか
    @ObservationIgnored private var restoredWindowOrder = false
    @ObservationIgnored private let log = Logger(subsystem: "app.pinstage.Pinstage", category: "Stage")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stripSettings = StripSettings(defaults: defaults)
        singleWindowSize = SingleWindowSize(defaults: defaults)
    }

    // MARK: - 起動と終了

    func start() {
        AXWindow.configureMessagingTimeout()
        loadLibrary()
        if !isTrusted { AccessibilityPermission.prompt() }
        refresh()
        // ウインドウの開け閉め・名前の変化と、許可の変化を拾うため、少しずつ読み直す
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // × で閉じた・隠したなどを、すぐ一覧に映す。閉じるときにウインドウを捨てずに隠すだけのアプリ（LINE など）は、
        // 閉じた知らせを出さないので、画面に出ているウインドウの一覧（軽く読める）を見て、変わったときだけ読み直す
        windowListTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfWindowListChanged() }
        }
        // デスクトップを切り替えたときの読み直しは、StripManager が行う（先に、そのデスクトップのストリップを用意するため）
    }

    func stop() {
        refreshTimer?.invalidate()
        windowListTimer?.invalidate()
        raiseTask?.cancel()
        saveWindowOrder()
    }

    // MARK: - ウインドウを読み直す

    /// ウインドウを読み直したときにすることを足す
    func addRefreshHandler(_ handler: @escaping () -> Void) {
        refreshHandlers.append(handler)
    }

    /// 画面に出ているウインドウ（ほかのアプリの、ふつうのウインドウ）が変わっていたら、読み直す
    private func refreshIfWindowListChanged() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let numbers = Set(WindowListEntry.onScreen().filter { $0.pid != ownPID && $0.isNormalWindow }.map(\.number))
        guard numbers != onScreenNumbers else { return }
        // 初めて確かめたときは覚えるだけ（起動したときに読んでいるので、読み直さなくてよい）
        let isFirst = onScreenNumbers == nil
        onScreenNumbers = numbers
        if !isFirst { refresh() }
    }

    /// 開いているウインドウを読み直す
    func refresh() {
        isTrusted = AccessibilityPermission.isTrusted
        let stageManagerOn = SystemStageManager.isEnabled
        if stageManagerOn != isSystemStageManagerOn { isSystemStageManagerOn = stageManagerOn }
        guard isTrusted else {
            if !windows.isEmpty { windows = [] }
            return
        }
        let next = readWindows()
        // 変わったときだけ入れ直す（変わらないのに入れ直すと、ストリップ全体が 1.5 秒ごとに描き直される）
        if next != windows { windows = next }
        classify(next)
        var pruned = board
        pruned.prune(keeping: Set(next.map(\.id)))
        if pruned != board { board = pruned }
        refreshHandlers.forEach { $0() }
        discoverOtherSpaceWindows()
    }

    /// いま開いているウインドウを、ストリップに並べる順番で読む
    private func readWindows() -> [WindowItem] {
        var current = WindowCatalog.enumerate()
        // 別の操作スペースのウインドウは、多くのアプリでウインドウの一覧に出てこない。
        // まだあるウインドウは残しておく（ステージから外したり、並び順を崩したりしないように）
        let listed = Set(current.map(\.id))
        let listedNumbers = Set(current.compactMap(\.windowID))
        var isRunning: [pid_t: Bool] = [:]
        current += windows.filter { item in
            // 一覧に出てきたウインドウは、一覧のほうを使う（ほかのデスクトップで見つけた部品と、同じウインドウのことがある）
            guard !listed.contains(item.id), !item.windowID.map(listedNumbers.contains).orFalse else { return false }
            // アプリが動いているかは、アプリごとに 1 回だけ調べる
            let running = isRunning[item.pid] ?? AXWindow.isRunning(pid: item.pid)
            isRunning[item.pid] = running
            return running && AXWindow.isValid(item.id)
        }
        if !restoredWindowOrder, !current.isEmpty {
            // 起動して初めて読んだときは、前に終了したときの並び順に並べ直す
            restoredWindowOrder = true
            let signatures = current.map { $0.signature ?? WindowSignature(bundleID: "", title: $0.title) }
            let order = WindowOrderStore.restoredOrder(saved: WindowOrderStore.load(from: defaults), current: signatures)
            let restored = order.map { current[$0] }
            return stripSettings.groupsSameApp ? RecentOrder.clustered(restored, app: \.appKey) : restored
        }
        let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 新しいウインドウは、同じアプリのウインドウのすぐ後ろに入れる（なければ末尾）。まとめる設定なら、すでに並んでいるものもまとめる
        return RecentOrder.syncing(windows.map(\.id), with: current.map(\.id), clusters: stripSettings.groupsSameApp) { byID[$0]?.appKey }
            .compactMap { byID[$0] }
    }

    /// いまのデスクトップのもの・どのディスプレイのものかを見分ける（見分け方は WindowClassifier）
    private func classify(_ items: [WindowItem]) {
        let result = WindowClassifier.classify(items, separatesDisplays: separatesDisplays)
        // 変わったときだけ入れ直す（同じ値でも入れ直すと、見ているウインドウバーが描き直される）
        if result.desktopNames != desktopNames { desktopNames = result.desktopNames }
        if result.windowSpaces != windowSpaces { windowSpaces = result.windowSpaces }
        desktopSnapshot = result.activeSpace.snapshot
        if result.activeSpace.ids != currentSpaceIDs { currentSpaceIDs = result.activeSpace.ids }
        if result.activeSpace.floating != floatingIDs { floatingIDs = result.activeSpace.floating }
        // ディスプレイを見分けなかったとき（ウインドウバーが 1 つ）は、前の値のままにする
        if let displays = result.windowDisplays, displays != windowDisplays { windowDisplays = displays }
        // デスクトップを切り替えた直後（1 秒）は、隠されたかを見分け直さない（行き先のウインドウを、隠されたものと取り違えないように）
        if ProcessInfo.processInfo.systemUptime - spaceChangedAt >= 1, result.hiddenWindows != hiddenWindowIDs {
            hiddenWindowIDs = result.hiddenWindows
        }
    }

    /// すべてのデスクトップに割り当てたウインドウか（決まりは PinstageCore の WindowSpaces。デスクトップが分からなければ false）
    func isOnAllDesktops(_ item: WindowItem) -> Bool {
        windowSpaces?[item.id].map(WindowSpaces.isOnAllDesktops) ?? false
    }

    /// デスクトップを切り替えた（StripManager から）
    func noteSpaceChanged() {
        spaceChangedAt = ProcessInfo.processInfo.systemUptime
    }

    /// ウインドウのあるデスクトップの名前（except のデスクトップにあるとき・分からないときは nil）
    func desktopName(of item: WindowItem, except space: UInt64?) -> DesktopName? {
        // すべてのデスクトップに割り当てたウインドウは、どのデスクトップにもあるので、ほかのデスクトップの印は付けない
        guard let spaces = windowSpaces?[item.id], !spaces.isEmpty, !WindowSpaces.isOnAllDesktops(spaces) else { return nil }
        if let space, spaces.contains(space) { return nil }
        return spaces.lazy.compactMap { self.desktopNames[$0] }.first
    }

    /// ほかのデスクトップのウインドウを探して、一覧に足す（見つけたら読み直す）
    private func discoverOtherSpaceWindows() {
        discovery.discover(known: Set(windows.compactMap(\.windowID))) { [weak self] found in
            guard let self else { return }
            // 探している間に一覧に入ったものは除く
            let known = Set(windows.compactMap(\.windowID))
            let new = found.filter { !known.contains($0.windowID ?? 0) }
            guard !new.isEmpty else { return }
            // 新しく開いたものと同じく足す（同じアプリのすぐ後ろ、なければ末尾。あとの読み直しで、閉じるまで残る）
            let byID = Dictionary((windows + new).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            windows = RecentOrder.appending(new.map(\.id), to: windows.map(\.id)) { byID[$0]?.appKey }.compactMap { byID[$0] }
            refresh()
        }
    }

    /// 閉じた・終了したのを、すぐストリップに映す（アプリが閉じ終えるまで少し待つ）
    private func refreshSoon() {
        Task {
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(400))
                refresh()
            }
        }
    }

    // MARK: - ストリップに並べるウインドウ

    /// そのディスプレイのストリップに並べる候補
    /// - そのウインドウバーのデスクトップのウインドウ。最小化したもの・隠したアプリのものは、どのデスクトップのウインドウバーにも並べる
    /// - そのディスプレイにあるウインドウ（ウインドウバーが 1 つのときはすべて）
    func spaceWindows(on screen: NSScreen, spaceIDs: Set<AXUIElement>) -> [WindowItem] {
        // 隠されたウインドウ（× で閉じて隠しただけのもの）は並べない
        let shown = hiddenWindowIDs.isEmpty ? windows : windows.filter { !hiddenWindowIDs.contains($0.id) }
        var result = shown.filter { spaceIDs.contains($0.id) || floatingIDs.contains($0.id) }
        if separatesDisplays {
            let key = Self.displayKey(screen)
            // どのディスプレイのものか分からないウインドウ（枠が読めないもの）は、どのストリップにも並べる
            result = result.filter { windowDisplays[$0.id].map { $0 == key } ?? true }
        }
        return result
    }

    // MARK: - ディスプレイ

    /// ストリップを出すディスプレイ（設定のまま。そのディスプレイでは、ステージからストリップの分を除く）
    var stripScreens: [NSScreen] {
        switch stripSettings.displays {
        case .all: NSScreen.screens
        case .mainOnly: NSScreen.primary.map { [$0] } ?? []
        }
    }

    /// ウインドウバーごとに、そのディスプレイのウインドウだけを並べるか（ウインドウバーが 2 つ以上あるとき）
    var separatesDisplays: Bool {
        stripScreens.count > 1
    }

    /// ディスプレイの名前（ステージを分ける鍵）
    static func displayKey(_ screen: NSScreen) -> String {
        screen.displayUUID ?? "display-\(screen.displayNumber ?? 0)"
    }

    /// ポインタのあるディスプレイ（ショートカットで操作するときに使う）
    static var screenUnderPointer: NSScreen? {
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.primary
    }

    // MARK: - ステージの操作（ストリップから）

    func stage(on screen: NSScreen) -> StageBoard<AXUIElement>.Stage {
        board.stage(on: Self.displayKey(screen))
    }

    /// そのディスプレイのステージを変える（apply なら、変えたあと並べて前に出す）
    func updateStage(on screen: NSScreen, apply: Bool, _ change: (inout StageBoard<AXUIElement>.Stage) -> Void) {
        board.update(on: Self.displayKey(screen), change)
        if apply { applyStage(on: screen) }
    }

    /// そのディスプレイのステージに出しているウインドウ（出す順番。後ろほど前面）
    func stageItems(on screen: NSScreen) -> [WindowItem] {
        stage(on: screen).selection.members.compactMap(item(for:))
    }

    func item(for id: AXUIElement) -> WindowItem? {
        windows.first { $0.id == id }
    }

    /// クリック: そのウインドウだけを出す
    func showOnly(_ item: WindowItem, on screen: NSScreen) {
        updateStage(on: screen, apply: true) { $0.selection.showOnly(item.id) }
    }

    /// ダブルクリック: そのウインドウだけを、ステージいっぱいに広げて出す（並べ方の型にかかわらず）
    func showMaximized(_ item: WindowItem, on screen: NSScreen) {
        // 1 回目のクリックで並べたあとの確かめ直しが残っていると、広げた枠を 1 回目の枠に戻してしまうので、やめる
        cancelPlacementCheck(on: screen)
        updateStage(on: screen, apply: false) { $0.selection.showOnly(item.id) }
        AXWindow.prepareToShow(item.id, pid: item.pid)
        AXWindow.setFrame(item.id, pid: item.pid, to: stageArea(on: screen))
        raise([item])
    }

    /// ⌘＋クリック: 足す・外す
    func toggle(_ item: WindowItem, on screen: NSScreen) {
        updateStage(on: screen, apply: true) { $0.selection.toggle(item.id) }
    }

    /// ステージへドラッグ: 足す
    func add(_ item: WindowItem, on screen: NSScreen) {
        add([item], on: screen)
    }

    /// ステージへまとめて足す（同じアプリのまとまりをドラッグしたとき。並べ直すのは 1 回だけ）
    func add(_ items: [WindowItem], on screen: NSScreen) {
        updateStage(on: screen, apply: true) { stage in
            items.forEach { stage.selection.add($0.id) }
        }
    }

    /// ステージから外す（ウインドウはそのまま。残りを並べ直す）
    func remove(_ item: WindowItem, on screen: NSScreen) {
        updateStage(on: screen, apply: true) { $0.selection.remove(item.id) }
    }

    /// 並べ方を変える（ステージに出していれば並べ直す）
    func setLayout(_ choice: LayoutChoice, on screen: NSScreen) {
        updateStage(on: screen, apply: true) { $0.layout = choice }
    }


    // MARK: - 並べて前に出す

    /// そのディスプレイのステージのウインドウを、選んだ型で並べて最前面に出す
    func applyStage(on screen: NSScreen) {
        let stage = self.stage(on: screen)
        let items = stageItems(on: screen)
        guard !items.isEmpty else { return }
        let area = stageArea(on: screen)
        let restored = Set(items.filter { AXWindow.prepareToShow($0.id, pid: $0.pid) }.map(\.id))
        let placements = Array(zip(items, frames(for: items, in: area, stage: stage)))
        for (item, frame) in placements {
            AXWindow.setFrame(item.id, pid: item.pid, to: frame)
        }
        checkPlacements(placements, restored: restored, on: screen)
        // ストリップの行の並びは変えない（⌘＋クリックで続けて選ぶとき、選びたい行がずれないように）
        raise(items)
    }

    /// 並べたあと、少し待って実際の枠を読み直し、ずれていたら合わせ直す
    ///
    /// - しまってあったウインドウは、戻るアニメーションの間に枠を変えても効かないことがある
    /// - Chrome・Electron のアプリなどは、頼んだ大きさを遅れて当てたり、途中で元に戻したりすることがある
    /// 合わせ直してもずれたままのもの（アプリがそれより小さくできない・大きさを刻みでしか変えないなど）は、原因を確かめるために記録に残す
    /// 並べたあとの確かめ直しをやめる（並べたあとに、別の枠にしたとき。ダブルクリックで広げたときなど）
    private func cancelPlacementCheck(on screen: NSScreen) {
        placementChecks.removeValue(forKey: Self.displayKey(screen))?.cancel()
    }

    private func checkPlacements(_ placements: [(WindowItem, CGRect)], restored: Set<AXUIElement>, on screen: NSScreen) {
        let key = Self.displayKey(screen)
        placementChecks[key]?.cancel()
        placementChecks[key] = Task {
            try? await Task.sleep(for: .milliseconds(restored.isEmpty ? 300 : 450))
            // 利用者がウインドウをつかんで動かしている間は、合わせ直さない（動かした先を戻してしまうため）
            guard !Task.isCancelled, NSEvent.pressedMouseButtons == 0 else { return }
            var retried: [(WindowItem, CGRect)] = []
            for (item, frame) in placements {
                guard restored.contains(item.id) || !(AXWindow.frame(of: item.id).map { StageLayout.isPlaced($0, at: frame) } ?? true) else { continue }
                AXWindow.setFrame(item.id, pid: item.pid, to: frame)
                retried.append((item, frame))
            }
            guard !retried.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            for (item, frame) in retried {
                guard let actual = AXWindow.frame(of: item.id), !StageLayout.isPlaced(actual, at: frame) else { continue }
                DesktopTrace.log("並べたときのずれ", "\(item.bundleID ?? item.appName): 枠 \(frame.integral) → 実際 \(actual.integral)")
            }
        }
    }

    /// すべてのディスプレイのステージを並べ直す（ストリップの幅や出し方が変わり、ステージの範囲が変わったとき）
    func reapplyAllStages() {
        for screen in NSScreen.screens where !stage(on: screen).selection.isEmpty {
            applyStage(on: screen)
        }
    }

    /// ステージの範囲（アクセシビリティの座標）。ストリップを出しているディスプレイでは、ストリップの分を除く
    /// - Parameter settings: この設定のときの範囲（省けば、いまの設定）
    func stageArea(on screen: NSScreen, settings: StripSettings? = nil) -> CGRect {
        let settings = settings ?? stripSettings
        let primaryHeight = NSScreen.primary?.frame.height ?? screen.frame.height
        let visible = screen.visibleFrame
        let hasStrip = stripScreens.contains { Self.displayKey($0) == Self.displayKey(screen) }
        let frame = hasStrip
            ? StripGeometry.stageFrame(in: visible, mode: settings.mode, edge: settings.edge, thickness: settings.effectiveThickness, gap: settings.stageGap)
            : visible
        return ScreenCoordinates.toAccessibility(frame, primaryScreenHeight: primaryHeight)
    }

    /// ステージの範囲が広がったとき（ストリップを狭めた・ほかの辺へ移した）、
    /// 前のステージの端（ストリップの横）にくっつけていたウインドウを、新しい端まで広げる（反対側の端はそのまま）。
    /// ステージに出しているウインドウは、並べ直すので除く
    func followWidenedStage(from old: StripSettings) {
        guard old.mode == .alwaysShown, stripSettings.mode == .alwaysShown else { return }
        let locator = DisplayLocator()
        for screen in stripScreens {
            let key = Self.displayKey(screen)
            let oldArea = stageArea(on: screen, settings: old)
            let newArea = stageArea(on: screen)
            guard oldArea != newArea else { continue }
            let onStage = Set(stage(on: screen).selection.members)
            for item in windows where !item.isMinimized && currentSpaceIDs.contains(item.id) && !onStage.contains(item.id) {
                guard let frame = AXWindow.frame(of: item.id),
                      let widened = StripAvoidance.following(frame, stageFrom: oldArea, to: newArea),
                      locator.key(for: frame) == key
                else { continue }
                AXWindow.setFrame(item.id, pid: item.pid, to: widened)
            }
        }
    }

    /// ウインドウごとの枠（アクセシビリティの座標）
    private func frames(for items: [WindowItem], in area: CGRect, stage: StageBoard<AXUIElement>.Stage) -> [CGRect] {
        // 1 枚だけのときは、設定の大きさで前に出す（そのまま・縦いっぱい・ステージいっぱい）
        if items.count == 1, !stage.layout.resizesSingleWindow {
            guard let current = AXWindow.frame(of: items[0].id) else { return [] }
            return [StageLayout.singleFrame(current: current, in: area, size: singleWindowSize)]
        }
        return stage.layout.frames(
            count: items.count,
            in: area,
            customLayouts: library.customLayouts
        )
    }

    /// 後ろから順に前に出す（最後のものが最前面）。アプリを切り替えるたびに少し待つ
    private func raise(_ items: [WindowItem]) {
        raiseTask?.cancel()
        raiseTask = Task {
            for item in items {
                if Task.isCancelled { return }
                // ほかのデスクトップのウインドウは、そのデスクトップへ移って前に出す
                if isOnOtherSpace(item), let id = item.windowID {
                    SkyLight.focus(windowID: id, pid: item.pid)
                }
                AXWindow.raise(item.id, pid: item.pid)
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    /// ほかのデスクトップ（いま表に出ていないデスクトップ）にあるウインドウか
    private func isOnOtherSpace(_ item: WindowItem) -> Bool {
        guard let spaces = windowSpaces?[item.id], !spaces.isEmpty else { return false }
        return spaces.isDisjoint(with: SkyLight.currentSpaces())
    }

    // MARK: - 閉じる・終了する

    /// ウインドウを閉じる（保存していなければ、アプリが聞く）
    func close(_ item: WindowItem) {
        AXWindow.close(item.id)
        refreshSoon()
    }

    /// そのウインドウのアプリを終了する（ふつうの終了。保存していない書類があれば、アプリが聞く）
    func quitApp(of item: WindowItem) {
        NSRunningApplication(processIdentifier: item.pid)?.terminate()
        refreshSoon()
    }

    // MARK: - ストリップのウインドウの並び順

    /// ストリップのウインドウを並べ替える（ドラッグ。dropIndex はその番号の行の前。並びはアプリを終了するまで残る）
    /// - Parameter visible: ストリップに並べている行（index・dropIndex は、この中での番号）。
    ///   いまのデスクトップのウインドウだけを並べているときも、ほかのデスクトップのウインドウの並びは崩さない
    func moveWindow(from index: Int, dropIndex: Int, visible: [AXUIElement]) {
        let byID = Dictionary(windows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        // 同じアプリをまとめているときは、ほかのアプリの間へ落としたら、同じアプリのウインドウをまとめて動かす
        let order = stripSettings.groupsSameApp
            ? ListReorder.movedSubset(all: windows.map(\.id), visible: visible, from: index, dropIndex: dropIndex) { byID[$0]?.appKey }
            : ListReorder.movedSubset(all: windows.map(\.id), visible: visible, from: index, dropIndex: dropIndex)
        windows = order.compactMap { byID[$0] }
        saveWindowOrder()
    }

    /// ストリップのウインドウの並び順を覚える（再起動のあとも残すため。並べ替えたとき・終了するとき）
    private func saveWindowOrder() {
        guard restoredWindowOrder else { return }
        WindowOrderStore.save(windows.compactMap(\.signature), to: defaults)
    }

    /// ポインタのあるディスプレイで、いま前に出しているウインドウの次（前）のウインドウだけを出す（ストリップの並び順で。ショートカット）
    func showAdjacentWindow(forward: Bool) {
        guard let screen = Self.screenUnderPointer else { return }
        let front = stage(on: screen).selection.members.last
        // ストリップに並べている順番（いまのデスクトップの、このディスプレイのウインドウ）で切り替える
        let candidates = spaceWindows(on: screen, spaceIDs: currentSpaceIDs)
        let current = front.flatMap { id in candidates.firstIndex { $0.id == id } }
        guard let index = Cycling.index(after: current, count: candidates.count, forward: forward) else { return }
        showOnly(candidates[index], on: screen)
    }

    // MARK: - グループを呼び出す

    /// グループを呼び出す。閉じているアプリは起動し直し、ウインドウが出るのを少し待ってから並べる。
    /// 覚えたディスプレイがつながっていなければ、fallback のディスプレイに出す
    func recall(_ group: StageGroup, fallback: NSScreen?) async {
        guard recallingGroupID == nil else { return }
        recallingGroupID = group.id
        defer { recallingGroupID = nil }

        refresh()
        var matches = match(group)
        // 見つからなかったウインドウのアプリを起動する（動いていれば、ウインドウを開き直すよう頼む）
        let needsLaunch = Set(zip(group.members, matches).filter { $0.1.windowIndex == nil }.map(\.0.bundleID))
        if !needsLaunch.isEmpty {
            needsLaunch.forEach(launchApp(bundleID:))
            // 起動したアプリのウインドウが出るまで、最大 6 秒待つ
            for _ in 0..<30 {
                try? await Task.sleep(for: .milliseconds(200))
                refresh()
                matches = match(group)
                if matches.allSatisfy({ $0.windowIndex != nil }) { break }
            }
        }

        let candidates = windowsWithSignature()
        let ids = matches.compactMap(\.windowIndex).map { candidates[$0].item.id }
        let remembered = group.displayID.flatMap(NSScreen.screen(withDisplayUUID:))
        guard !ids.isEmpty, let screen = remembered ?? fallback ?? NSScreen.primary else { return }
        lastRecalledGroupID = group.id
        lastRecalledStage = (Self.displayKey(screen), Set(ids))
        // 記録した配置は、メンバーごとに枠が決まっているので、見つからなかったメンバーの枠を抜く（ほかの枠がずれないように）
        let layout = group.layout.keepingSlots(where: matches.map { $0.windowIndex != nil })
        updateStage(on: screen, apply: true) { stage in
            stage.selection.replace(with: ids)
            stage.layout = layout
        }
    }

    /// 何番目のグループを呼び出す（ショートカット）。覚えたディスプレイがなければ、ポインタのあるディスプレイに出す
    func recallGroup(at index: Int) {
        guard library.groups.indices.contains(index) else { return }
        let group = library.groups[index]
        Task { await recall(group, fallback: Self.screenUnderPointer) }
    }

    /// 最後に呼び出したグループの次（forward が false なら前）のグループを呼び出す（ショートカット）
    func recallAdjacentGroup(forward: Bool) {
        let current = lastRecalledGroupID.flatMap(library.groupIndex(id:))
        guard let index = Cycling.index(after: current, count: library.groups.count, forward: forward) else { return }
        recallGroup(at: index)
    }

    private func windowsWithSignature() -> [(item: WindowItem, signature: WindowSignature)] {
        windows.compactMap { item in item.signature.map { (item, $0) } }
    }

    private func match(_ group: StageGroup) -> [WindowMatcher.Match] {
        WindowMatcher.match(
            group.members,
            candidates: windowsWithSignature().map(\.signature),
            runningBundleIDs: NSWorkspace.shared.runningBundleIDs
        )
    }

    /// アプリを起動する（動いていれば、ウインドウを開き直すよう頼む）
    private func launchApp(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            log.notice("アプリが見つかりません: \(bundleID, privacy: .public)")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration, completionHandler: nil)
    }

    #if DEBUG
    // MARK: - 見本（開発用）

    /// 見本のデータを入れる（ストリップの見た目を画像に描き出して確かめるため。保存はしない）
    func loadPreview(
        windows: [WindowItem],
        groups: [StageGroup],
        onStage: [AXUIElement],
        screen: NSScreen,
        isTrusted: Bool = true,
        isSystemStageManagerOn: Bool = false,
        layout: LayoutChoice? = nil,
        customLayouts: [CustomLayout] = [],
        otherDesktop: [AXUIElement] = [],
        allDesktops: [AXUIElement] = []
    ) {
        self.windows = windows
        self.isTrusted = isTrusted
        self.isSystemStageManagerOn = isSystemStageManagerOn
        currentSpaceIDs = Set(windows.map(\.id))
        library = StageLibrary(groups: groups, customLayouts: customLayouts)
        if !otherDesktop.isEmpty || !allDesktops.isEmpty {
            // ほかのデスクトップ（2）のウインドウと、すべてのデスクトップ（1〜3）に割り当てたウインドウ
            let other = otherDesktop.map { ($0, Set([UInt64(2)])) }
            let all = allDesktops.map { ($0, Set<UInt64>([1, 2, 3])) }
            windowSpaces = Dictionary(other + all, uniquingKeysWith: { first, _ in first })
            desktopNames = [1: DesktopName(number: 1), 2: DesktopName(number: 2), 3: DesktopName(number: 3)]
        }
        updateStage(on: screen, apply: false) { stage in
            stage.selection.replace(with: onStage)
            if let layout { stage.layout = layout }
        }
    }
    #endif

    // MARK: - 保存

    /// グループ・型を書き換える。変わったときだけ保存する
    @discardableResult
    func editLibrary<Result>(_ change: (inout StageLibrary) -> Result) -> Result {
        var edited = library
        let result = change(&edited)
        if edited != library {
            library = edited
            saveLibrary()
        }
        return result
    }

    private func loadLibrary() {
        do {
            library = try store.load()
        } catch {
            // 読めないファイルは脇へ移して、空から始める（次の保存で上書きして失わないように）
            let moved = store.moveAsideUnreadable()
            log.error("グループを読み込めませんでした: \(error.localizedDescription, privacy: .public)。移した先: \(moved?.path ?? "なし", privacy: .public)")
            library = StageLibrary()
        }
    }

    private func saveLibrary() {
        do {
            try store.save(library)
        } catch {
            log.error("グループを保存できませんでした: \(error.localizedDescription, privacy: .public)")
        }
        onLibraryChanged?()
    }
}

private extension Optional where Wrapped == Bool {
    /// nil なら false
    var orFalse: Bool { self ?? false }
}
