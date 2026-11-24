import AppKit

/// ほかのデスクトップのウインドウを探す（非公開の API。RemoteWindows を使う）
///
/// アクセシビリティの API の一覧には、いま見ているデスクトップのウインドウしか出てこないアプリが多いので、
/// 見つけていないウインドウがあるアプリだけ、メインの処理の外で探す。
/// 前に探して見つからなかったものは、30 秒たつまで探し直さない
final class OtherSpaceDiscovery {
    /// 見つからなかったものを探し直すまでの時間（秒）
    static let retryInterval: TimeInterval = 30

    /// 探している途中の処理
    private var task: Task<Void, Never>?
    /// アプリごとの、前に探したウインドウと時刻
    private var lastAttempt: [pid_t: (windows: Set<CGWindowID>, at: TimeInterval)] = [:]

    /// まだ見つけていないウインドウを探す（探している途中なら何もしない）。見つけたら onFound に渡す
    /// - Parameter known: もう一覧にあるウインドウの番号
    func discover(known: Set<CGWindowID>, onFound: @escaping @MainActor ([WindowItem]) -> Void) {
        guard task == nil, SkyLight.isAvailable, RemoteWindows.isAvailable else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let missing = RemoteWindows.missingWindows(known: known).filter { pid, ids in
            // 前に探して見つからなかったものと同じなら、しばらく探し直さない
            guard let last = lastAttempt[pid], last.windows == ids else { return true }
            return now - last.at >= Self.retryInterval
        }
        guard !missing.isEmpty else { return }
        for (pid, ids) in missing { lastAttempt[pid] = (ids, now) }
        task = Task { [weak self] in
            let found = await Task.detached(priority: .utility) {
                missing.map { pid, ids in (pid, RemoteWindows.find(pid: pid, wanted: ids)) }
            }.value
            guard let self else { return }
            task = nil
            let items = found.flatMap { pid, windows in windows.compactMap { Self.item(for: $0, pid: pid) } }
            guard !items.isEmpty else { return }
            onFound(items)
        }
    }

    /// 見つけた部品から、ストリップに並べるウインドウを作る
    private static func item(for found: RemoteWindows.Found, pid: pid_t) -> WindowItem? {
        guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return nil }
        return WindowItem(
            id: found.element,
            pid: pid,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "名前のないアプリ",
            title: AXWindow.attribute(found.element, kAXTitleAttribute) ?? "",
            icon: app.icon,
            isMinimized: AXWindow.attribute(found.element, kAXMinimizedAttribute) ?? false,
            windowID: found.windowID
        )
    }
}
