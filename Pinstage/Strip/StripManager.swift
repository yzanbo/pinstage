import AppKit
import PinstageCore

/// ディスプレイごと・デスクトップごとのストリップをまとめる
///
/// 非公開の API が使えるとき（ふつうはこちら）:
/// - すべてのデスクトップに、前もってストリップを置く（デスクトップを足した・消したら、それに合わせる）
/// - 各ストリップは、自分のデスクトップにあるウインドウだけを並べる（ウインドウのデスクトップを macOS に聞く）
///
/// 使えないとき（macOS が変わって関数が消えたときなど）は、公開の API だけで推測する:
/// - デスクトップを切り替えたら、初めて訪れたデスクトップにストリップを作る
/// - ウインドウを読み直すたびに、読んだ一覧を、そのとき画面に出ているストリップのデスクトップのものとして覚えさせる
///   （判定は PinstageCore の DesktopAttribution）
final class StripManager {
    private let stage: StageController
    private let thumbnails: ThumbnailStore
    private let shortcuts: ShortcutCenter
    private let actions: AppActions
    /// ディスプレイごと・デスクトップごとのストリップ（訪れたデスクトップの数だけ増える）
    private var strips: [StripController] = []
    private lazy var windowDragFeedback = StripWindowDragFeedback { [weak self] source, pointer in
        self?.strips.first {
            $0.displayKey != source.displayKey && $0.isShown
                && $0.frame.contains(pointer) && $0.screen.frame.contains(pointer) && $0.isOnActiveSpace
        }
    }
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    /// デスクトップを切り替えたあと、切り替えの動きが落ち着くまで確かめ直す
    private var settleTask: Task<Void, Never>?
    /// デスクトップを切り替えたあとの、落ち着くまでの間か（この間だけ、初めて訪れたデスクトップにストリップを作る）
    private var isSettling = false
    /// いちばん新しく確かめたとき、デスクトップを切り替えている途中だったか（落ち着くまで、早めに読み直す）
    private var isSwitching = false
    /// 1 つのデスクトップにストリップが重なっているのを見つけた時刻（ディスプレイごと）
    private var overlappingSince: [String: TimeInterval] = [:]
    /// 画面に出ているストリップと、表に出ているデスクトップのストリップが食い違い始めた時刻（ディスプレイごと）
    private var disagreeingSince: [String: TimeInterval] = [:]
    /// ディスプレイごとの、前に見たときの使える範囲（Dock・メニューバーを除いた範囲）
    private var knownVisibleFrames: [String: CGRect] = [:]
    /// 非公開の API で、デスクトップを直接見分けるか（起動したときに決める）
    private let usesSystemSpaces = SkyLight.isAvailable

    /// いま表に出ているデスクトップのストリップ（ディスプレイごとに 1 つ）
    private var activeStrips: [StripController] {
        strips.filter(\.isOnActiveSpace)
    }

    /// いまのデスクトップの、どれかのストリップを出しているか
    var anyShown: Bool {
        activeStrips.contains(where: \.isShown)
    }

    /// いま出しているストリップのディスプレイ（ストリップに重なったウインドウを戻すとき、どのディスプレイで戻すか）
    var shownScreens: [NSScreen] {
        activeStrips.filter(\.isShown).map(\.screen)
    }

    init(stage: StageController, thumbnails: ThumbnailStore, shortcuts: ShortcutCenter, actions: AppActions) {
        self.stage = stage
        self.thumbnails = thumbnails
        self.shortcuts = shortcuts
        self.actions = actions
        // 読み直したら、そのとき画面に出ているストリップに、そのデスクトップのウインドウの一覧を覚えさせる
        stage.addRefreshHandler { [weak self] in self?.windowsRefreshed() }
        stage.onStripSettingsChanged = { [weak self] old in self?.settingsChanged(from: old) }
        // ウインドウバーに並べて、スクロールして見えている行のウインドウだけを撮る（サムネイルの形式でないとき・隠しているときは撮らない）
        thumbnails.targets = { [weak self] in
            guard let self, stage.stripSettings.capturesThumbnails, anyShown else { return [] }
            // ディスプレイごとのウインドウバーの、見えている行のウインドウを、重ならないように集める
            var seen = Set<AXUIElement>()
            return activeStrips.flatMap(\.thumbnailTargets).filter { seen.insert($0.id).inserted }
        }
        // ほかのデスクトップのウインドウのサムネイルも残しておく（切り替えの途中から、行き先のストリップに出ているように）
        thumbnails.existing = { Set(stage.windows.map(\.id)) }
    }

    func start() {
        rebuild()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
        // デスクトップを切り替えたら、そのデスクトップのストリップを用意して読み直す
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        }
    }

    func stop() {
        settleTask?.cancel()
        windowDragFeedback.finish()
        strips.forEach { $0.close() }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    // MARK: - デスクトップの切り替え

    /// デスクトップを切り替えた。初めて訪れたデスクトップには、ディスプレイごとにストリップを作る
    /// （2 回目からは、そのデスクトップに置いてあるストリップが、前に覚えた一覧のまま切り替えと一緒に出てくる）
    private func spaceChanged() {
        actions.closeWindowSwitcher(nil)
        windowDragFeedback.finish()
        trace("activeSpaceDidChange", onScreen: CurrentSpace.ownWindowNumbersOnScreen())
        stage.noteSpaceChanged()
        if usesSystemSpaces {
            // ストリップはすべてのデスクトップに置いてあり、一覧もデスクトップの番号で決めてあるので、読み直すだけでよい
            syncSpaces()
            stage.refresh()
            return
        }
        settleTask?.cancel()
        isSettling = true
        refreshAndEnsureStrips()
        // 切り替えの知らせは、切り替えの動きが終わる前に来ることがある（まだ両方のデスクトップが画面に出ている）。
        // 動きが落ち着くまで少しずつ読み直す（初めて訪れたデスクトップにストリップを作り、着いたデスクトップの一覧で覚え直す）
        settleTask = Task { [weak self] in
            for step in 1...30 {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled, let self else { return }
                // 着いたあとも 1 回は読み直す（開くのが遅れたウインドウを拾う）
                if isSwitching || step == 3 { refreshAndEnsureStrips() }
                if step >= 10, !isSwitching { break }
            }
            self?.isSettling = false
        }
    }

    /// 読み直す（読み直しの中で、ストリップを確かめて一覧を覚える）。
    /// アクセシビリティの許可がなくて読み直せないときも、ストリップだけは確かめる
    private func refreshAndEnsureStrips() {
        stage.refresh()
        if !stage.isTrusted {
            isSwitching = ensureStrips(onScreen: CurrentSpace.ownWindowNumbersOnScreen())
        }
    }

    /// ウインドウを読み直した。ストリップを確かめてから、読んだ「画面に出ているウインドウの一覧」を覚えさせる
    private func windowsRefreshed() {
        followUsableAreaChanges()
        if usesSystemSpaces {
            syncSpaces()
            assignWindowsBySpace()
            return
        }
        let snapshot = stage.desktopSnapshot
        var switching = ensureStrips(onScreen: snapshot?.ownWindowNumbers ?? CurrentSpace.ownWindowNumbersOnScreen())
        if let snapshot, rememberDesktops(from: snapshot) { switching = true }
        isSwitching = switching
    }

    /// Dock の大きさ・位置・自動で隠すか、メニューバーを自動で隠すかを変えると、ディスプレイの使える範囲（visibleFrame）が変わる。
    /// 画面の構成が変わった知らせが来ないこともあるので、読み直すたびに比べ、変わっていたらストリップを置き直し、ステージを並べ直す
    /// （常に表示の Dock と同じ辺に置いたストリップが、Dock の下に潜らないように）
    private func followUsableAreaChanges() {
        let current = Dictionary(NSScreen.screens.map { (StageController.displayKey($0), $0.visibleFrame) }, uniquingKeysWith: { first, _ in first })
        defer { knownVisibleFrames = current }
        // ディスプレイをつなぎ直したときは、知らせを受けて作り直すので、ここでは使える範囲だけが変わったときに限る
        guard !knownVisibleFrames.isEmpty, Set(current.keys) == Set(knownVisibleFrames.keys), current != knownVisibleFrames else { return }
        DesktopTrace.log("使える範囲", "変わった（Dock・メニューバーの設定）: \(current.values.map { "\($0)" }.joined(separator: " / "))")
        strips.forEach { $0.relayout() }
        stage.reapplyAllStages()
    }

    /// 読んだ一覧を、同じ一覧の中に出ているストリップのデスクトップのものとして覚えさせる。
    /// デスクトップを切り替えている途中は、覚えた一覧を変えない（行き先のストリップに、前のデスクトップのウインドウを混ぜない）
    /// - Returns: 切り替えている途中だったか
    private func rememberDesktops(from snapshot: DesktopSnapshot<AXUIElement>) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        let separateSpaces = NSScreen.screensHaveSeparateSpaces
        var outcomes: [DesktopAttribution.Outcome] = []
        let groups = Dictionary(grouping: strips, by: \.displayKey)
        for key in groups.keys.sorted() {
            guard let group = groups[key] else { continue }
            var desktops = group.map(\.desktop)
            outcomes.append(DesktopAttribution.update(
                &desktops,
                isOnScreen: group.map { $0.isOnScreen(in: snapshot.ownWindowNumbers, at: now) },
                isOnActiveSpace: group.map(\.isOnActiveSpace),
                disagreeingSince: &disagreeingSince[key],
                windows: snapshot.windows(onDisplay: key, separateSpaces: separateSpaces),
                at: now
            ))
            for (strip, desktop) in zip(group, desktops) {
                strip.remember(desktop)
            }
        }
        trace("refresh \(outcomes)", onScreen: snapshot.ownWindowNumbers)
        return outcomes.contains(.switching)
    }

    // MARK: - デスクトップを直接見分ける（非公開の API）

    /// すべてのディスプレイの、すべてのデスクトップ（フルスクリーンのものは除く）に、ストリップが 1 つずつあるようにする。
    /// デスクトップを足したら作り、消したら閉じる
    private func syncSpaces() {
        guard let displays = SkyLight.displays() else { return }
        var wanted: [(screen: NSScreen, space: UInt64)] = []
        for screen in stage.stripScreens {
            let display = SkyLight.display(forKey: StageController.displayKey(screen), in: displays)
            for space in display?.spaces ?? [] where !space.isFullScreen {
                wanted.append((screen, space.id))
            }
        }
        // もうないデスクトップ・ストリップを出さなくなったディスプレイのストリップを閉じる
        let wantedKeys = Set(wanted.map { "\(StageController.displayKey($0.screen))#\($0.space)" })
        for strip in strips where strip.spaceID.map({ !wantedKeys.contains("\(strip.displayKey)#\($0)") }) ?? true {
            trace("close #\(strip.windowNumber) space=\(strip.spaceID.map(String.init) ?? "-")", onScreen: [])
            strip.close()
            strips.removeAll { $0 === strip }
        }
        // まだストリップのないデスクトップに作る
        for (screen, space) in wanted {
            let key = StageController.displayKey(screen)
            guard !strips.contains(where: { $0.displayKey == key && $0.spaceID == space }) else { continue }
            addStrip(on: screen, space: space)
        }
    }

    /// 各ストリップに、自分のデスクトップにあるウインドウを入れる
    private func assignWindowsBySpace() {
        guard let spaces = stage.windowSpaces else { return }
        for strip in strips {
            guard let space = strip.spaceID else { continue }
            strip.setWindows(Set(spaces.compactMap { $0.value.contains(space) ? $0.key : nil }))
        }
    }

    // MARK: - デスクトップを推測する（公開の API だけ）

    /// いまのデスクトップに、ディスプレイごとのストリップがあるようにする
    /// - 初めて訪れたデスクトップには、ストリップを作る（デスクトップを切り替えたあとの、落ち着くまでの間だけ）
    /// - デスクトップを消したときなど、1 つのデスクトップにストリップが重なったら、1 つにする
    /// - Returns: デスクトップを切り替えている途中か（画面に出ているストリップと、表に出ているデスクトップのストリップが食い違っている）
    @discardableResult
    private func ensureStrips(onScreen numbers: Set<Int>) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        var isUnsettled = false
        var frontIsFullScreen: Bool?
        for screen in stage.stripScreens {
            let key = StageController.displayKey(screen)
            let onDisplay = strips.filter { $0.displayKey == key }
            let result = DesktopAttribution.placement(
                isOnActiveSpace: onDisplay.map(\.isOnActiveSpace),
                isOnScreen: onDisplay.map { $0.isOnScreen(in: numbers, at: now) },
                isConfirmed: onDisplay.map(\.desktop.isConfirmed),
                overlappingSince: &overlappingSince[key],
                at: now
            )
            if result.isUnsettled { isUnsettled = true }
            switch result.placement {
            case .keep:
                break
            case .missing:
                // 初めて訪れたデスクトップ。フルスクリーンのアプリのデスクトップには、ストリップを出さない
                guard isSettling else { continue }
                if frontIsFullScreen == nil { frontIsFullScreen = AXWindow.frontmostWindowIsFullScreen() }
                let showsFullScreenWindow = stage.desktopSnapshot?
                    .showsFullScreenWindow(onDisplay: key, separateSpaces: NSScreen.screensHaveSeparateSpaces) ?? false
                if frontIsFullScreen == false, !showsFullScreenWindow { addStrip(on: screen) }
            case .merge(_, let close):
                for extra in close.map({ onDisplay[$0] }) {
                    trace("close overlapping #\(extra.windowNumber)", onScreen: numbers)
                    extra.close()
                    strips.removeAll { $0 === extra }
                }
            }
        }
        return isUnsettled
    }

    private func addStrip(on screen: NSScreen, space: UInt64? = nil) {
        let strip = StripController(screen: screen, spaceID: space, stage: stage, thumbnails: thumbnails, shortcuts: shortcuts, actions: actions)
        strip.windowDragFeedback = windowDragFeedback
        strip.onShow = { [weak self] in self?.thumbnails.captureNow() }
        // 一覧は空で始まり、すぐあとの読み直しで、このデスクトップの一覧を覚える（前のデスクトップの一覧を出さない）
        strips.append(strip)
        strip.start()
        trace("create #\(strip.windowNumber)", onScreen: [])
    }

    /// デスクトップの切り替えの記録（開発用のビルドだけ）。ストリップごとに、
    /// 番号・表に出ているデスクトップにあるか（A）・画面の一覧に出ているか（S）・隠しているか（h）・覚えているウインドウの数を書く
    private func trace(_ event: @autoclosure () -> String, onScreen numbers: @autoclosure () -> Set<Int>) {
        DesktopTrace.log(
            "デスクトップ",
            "\(event()) [\(describeStrips(onScreen: numbers()))] windows=\(stage.desktopSnapshot?.onScreen.count ?? -1)"
        )
    }

    private func describeStrips(onScreen numbers: Set<Int>) -> String {
        strips.map { strip in
            let display = NSScreen.screens.firstIndex(of: strip.screen) ?? -1
            return "#\(strip.windowNumber)@\(display)" + (strip.spaceID.map { "/\($0)" } ?? "")
                + (strip.isOnActiveSpace ? "A" : "-")
                + (numbers.contains(strip.windowNumber) ? "S" : "-")
                + (strip.isShown ? "" : "h")
                + ":\(strip.desktop.windows.count)"
        }
        .joined(separator: " ")
    }

    // MARK: - 出す・隠す

    /// いまのデスクトップのストリップの、出す・隠すを切り替える（ショートカット・メニューから）
    func toggle() {
        setShown(!anyShown)
    }

    /// いまのデスクトップのストリップを出す・隠す（自動化から）
    func setShown(_ shown: Bool) {
        activeStrips.forEach { $0.setShown(shown) }
    }

    // MARK: - 作り直す

    private func rebuild() {
        actions.closeWindowSwitcher(nil)
        windowDragFeedback.finish()
        // ほかのデスクトップに置いたストリップも、いったんすべて閉じる（ディスプレイが変わると、置き場所が合わなくなるため）。
        // ほかのデスクトップには、次に訪れたときに作り直す
        strips.forEach { $0.close() }
        strips = []
        overlappingSince = [:]
        disagreeingSince = [:]
        if usesSystemSpaces {
            syncSpaces()
        } else if !AXWindow.frontmostWindowIsFullScreen() {
            stage.stripScreens.forEach { addStrip(on: $0) }
        }
        // ストリップのあるディスプレイが変わったので、どのディスプレイのウインドウかを見分け直す
        stage.refresh()
    }

    private func settingsChanged(from old: StripSettings) {
        let new = stage.stripSettings
        // 出すディスプレイを変えたら見分け直し、「同じアプリのウインドウをまとめる」を変えたら、読み直して並びを合わせる
        if new.displays != old.displays
            || new.groupsSameApp != old.groupsSameApp {
            stage.refresh()
        }
        if new.displays != old.displays {
            rebuild()
        } else if new.mode != old.mode || new.edge != old.edge {
            strips.forEach { $0.applySettings() }
        } else if new.effectiveThickness != old.effectiveThickness {
            strips.forEach { $0.relayout() }
        }
        // ステージの範囲が変わったので、並べているウインドウを並べ直す（常に出すときだけ、ストリップの厚みと辺でステージが変わる）
        let placementChanged = new.effectiveThickness != old.effectiveThickness || new.edge != old.edge || new.stageGap != old.stageGap
        if new.mode != old.mode || (new.mode == .alwaysShown && placementChanged) {
            // ステージが広がった側では、ストリップの横にくっつけていたウインドウも、新しい端まで広げる
            stage.followWidenedStage(from: old)
            stage.reapplyAllStages()
            // ストリップの後ろに入り込ませない範囲も変わったので、すぐ読み直して、後ろに残ったウインドウを押し出す
            // （読み直すと StripAvoider が確かめる。待つと、次の読み直しまで最大 1.5 秒かかる）
            stage.refresh()
        }
        if new.capturesThumbnails, !old.capturesThumbnails || new.itemSize != old.itemSize {
            // サムネイルの見た目に変えたときは、画面収録の許可を求める（初めてなら macOS の確かめるダイアログが出る）
            if !old.capturesThumbnails { thumbnails.requestPermission() }
            thumbnails.captureNow()
        }
    }
}
