import AppKit

/// Dock のアイコンを、ふつうのウィンドウ（設定・型の編集）を開いている間だけ出す
///
/// ふだんはメニューバーだけに常駐する（Info.plist の LSUIElement）。ウィンドウを開いている間は、
/// Dock と ⌘Tab からそのウィンドウに戻れるようにする。すべて閉じたら、また Dock から消す。
/// ストリップ（StripPanel）は重ねて出す部品なので、開いていても Dock には出さない（Pinshot と同じ作り）
enum DockIcon {
    /// 開いているウィンドウと、閉じたことを受け取る印
    private static var observers: [ObjectIdentifier: (window: NSWindow, token: any NSObjectProtocol)] = [:]

    /// window を開いている間、Dock にアイコンを出す（ウィンドウを前に出す前に呼ぶ）
    static func show(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        if observers[key] == nil {
            let token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                MainActor.assumeIsolated { windowWillClose(key) }
            }
            observers[key] = (window, token)
        }
        enterDock()
    }

    /// ふつうのウィンドウ（設定・型の編集）を開いて、前に出す（開いている間は Dock に出す）
    static func present(_ window: NSWindow) {
        show(for: window)
        // Pinstage はふだん前面のアプリにならないので、先に前面へ出してから開く
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Dock のアイコンを押したとき: 開いているウィンドウを前に出す（しまっていれば戻す）
    static func bringWindowsToFront() {
        for (window, _) in observers.values {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
    }

    private static func windowWillClose(_ key: ObjectIdentifier) {
        guard let entry = observers.removeValue(forKey: key) else { return }
        NotificationCenter.default.removeObserver(entry.token)
        // ほかに開いているウィンドウがなければ、メニューバーだけに戻る
        if observers.isEmpty {
            leaveDock()
        }
    }

    /// Dock に出す（もう出ていれば何もしない）
    private static func enterDock() {
        guard NSApp.activationPolicy() != .regular else { return }
        NSApp.setActivationPolicy(.regular)
        // Dock に出たときのアイコンを、作ったアイコンにする。Dock の枠ができるのは少しあとなので、少し待ってもう一度設定する
        AppIcon.applyToApp()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AppIcon.applyToApp()
        }
    }

    /// Dock から消して、メニューバーだけに戻る
    private static func leaveDock() {
        guard NSApp.activationPolicy() != .accessory else { return }
        NSApp.setActivationPolicy(.accessory)
    }
}
