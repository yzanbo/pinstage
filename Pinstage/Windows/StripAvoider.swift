import AppKit
import ApplicationServices
import PinstageCore

/// ウインドウを、常に出しているストリップの後ろに入り込ませない
///
/// macOS には、ほかのアプリに使わせない場所を予約する仕組み（Dock のようなもの）がないので、ストリップは浮いているだけで、
/// ウインドウを広げる（タイトルバーのダブルクリック・緑のボタン・「フィル」など）と、ストリップの後ろまで入り込む。
/// ウインドウが動いた・大きさが変わった知らせを受け取り、ストリップに重なっていたら、ステージの範囲（ストリップを除いた残り）に戻す。
/// - ドラッグ・大きさの変更の途中は動かさず、マウスを離してから戻す
/// - 広げたウインドウはステージいっぱいに収め、もう一度ダブルクリックしたら元の大きさに戻す
/// - 知らせを出さないアプリのため、ウインドウを読み直すたび（1.5 秒ごと）にも確かめる
final class StripAvoider {
    private let stage: StageController
    /// いま出しているストリップのディスプレイ（そのディスプレイのウインドウだけを戻す）
    private let shownStripScreens: () -> [NSScreen]
    /// アプリごとの、知らせの受け取り口
    private var observers: [pid_t: AXObserver] = [:]
    /// ウインドウごとに知らせを頼んだもの（アプリによっては、ウインドウに頼まないと届かない）
    private var observedWindows: Set<AXUIElement> = []
    /// ウインドウごとの、前に見たときの枠
    private var knownFrames: [AXUIElement: CGRect] = [:]
    /// ウインドウごとの、ダブルクリックで元に戻すための覚え書き
    private var memories: [AXUIElement: StripAvoidance.ZoomMemory] = [:]
    /// 戻そうとしても動かなかった枠（アプリがその大きさより小さくできないなど。同じ枠では何度も試さない）
    private var refusedFrames: [AXUIElement: CGRect] = [:]
    private var pendingCheck: Task<Void, Never>?
    private var workspaceObservers: [NSObjectProtocol] = []

    /// 知らせを受けてから確かめるまでの間（続けて届く知らせを、まとめて 1 回で確かめる）
    private static let debounce: Duration = .milliseconds(120)

    init(stage: StageController, shownStripScreens: @escaping () -> [NSScreen]) {
        self.stage = stage
        self.shownStripScreens = shownStripScreens
    }

    func start() {
        for app in NSWorkspace.shared.runningApplications where app.hasManageableWindows {
            observe(app.processIdentifier)
        }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid, NSRunningApplication(processIdentifier: pid)?.hasManageableWindows == true { self?.observe(pid) }
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.unobserve(pid) }
            }
        })
        stage.addRefreshHandler { [weak self] in self?.windowsRefreshed() }
    }

    func stop() {
        pendingCheck?.cancel()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        for pid in Array(observers.keys) { unobserve(pid) }
    }

    // MARK: - 知らせを受け取る

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, AccessibilityPermission.isTrusted else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, stripAvoiderCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        for name in [kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private var refcon: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    /// ウインドウを読み直した。新しいウインドウに知らせを頼み、閉じたウインドウの覚え書きを消してから確かめる
    private func windowsRefreshed() {
        let current = Set(stage.windows.map(\.id))
        for item in stage.windows where !observedWindows.contains(item.id) {
            if observers[item.pid] == nil { observe(item.pid) }
            guard let observer = observers[item.pid] else { continue }
            AXObserverAddNotification(observer, item.id, kAXWindowMovedNotification as CFString, refcon)
            AXObserverAddNotification(observer, item.id, kAXWindowResizedNotification as CFString, refcon)
            observedWindows.insert(item.id)
        }
        observedWindows.formIntersection(current)
        knownFrames = knownFrames.filter { current.contains($0.key) }
        memories = memories.filter { current.contains($0.key) }
        refusedFrames = refusedFrames.filter { current.contains($0.key) }
        scheduleCheck()
    }

    /// 少し待ってから確かめる（続けて届く知らせをまとめる）
    fileprivate func scheduleCheck(after delay: Duration = StripAvoider.debounce) {
        pendingCheck?.cancel()
        pendingCheck = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.check()
        }
    }

    // MARK: - 確かめて戻す

    private func check() {
        let settings = stage.stripSettings
        guard settings.keepsWindowsOffStrip, settings.mode == .alwaysShown, stage.isTrusted else { return }
        // ドラッグ・大きさの変更の途中は動かさない（離してから戻す）
        if NSEvent.pressedMouseButtons != 0 {
            scheduleCheck(after: .milliseconds(250))
            return
        }
        let stripKeys = Set(shownStripScreens().map(StageController.displayKey))
        guard !stripKeys.isEmpty else { return }
        let locator = DisplayLocator()
        /// ディスプレイごとのステージの範囲（同じディスプレイのウインドウで使い回す）
        var areas: [String: CGRect] = [:]

        for item in stage.windows where !item.isMinimized {
            guard let frame = AXWindow.frame(of: item.id) else { continue }
            // 次に確かめるときに比べる枠（動かしたら、動かしたあとの枠）
            var latest = frame
            defer { knownFrames[item.id] = latest }
            // ストリップを出しているディスプレイのウインドウだけ
            guard let display = locator.display(for: frame), stripKeys.contains(display.key) else { continue }
            // 前に戻そうとして動かなかった枠のままなら、もう試さない
            if refusedFrames[item.id] == frame { continue }
            let area = areas[display.key] ?? stage.stageArea(on: display.screen)
            areas[display.key] = area
            let result = StripAvoidance.resolve(
                current: frame,
                previous: knownFrames[item.id],
                memory: memories[item.id] ?? .init(),
                stage: area,
                edge: settings.edge
            )
            memories[item.id] = result.memory
            guard let target = result.target else { continue }
            AXWindow.setFrame(item.id, pid: item.pid, to: target)
            let moved = AXWindow.frame(of: item.id)
            if moved == frame {
                // アプリが動かさなかった（その大きさより小さくできないなど）
                refusedFrames[item.id] = frame
            }
            latest = moved ?? frame
        }
    }
}

/// ウインドウが動いた・大きさが変わった知らせ（アクセシビリティの API から呼ばれる）
private nonisolated func stripAvoiderCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let avoider = Unmanaged<StripAvoider>.fromOpaque(refcon).takeUnretainedValue()
    Task { @MainActor in avoider.scheduleCheck() }
}
