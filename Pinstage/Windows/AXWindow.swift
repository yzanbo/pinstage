import AppKit
import ApplicationServices

/// アクセシビリティの API で、ほかのアプリのウインドウを読む・動かす
///
/// 座標は左上が原点（いちばん目の画面の左上）。アクセシビリティの許可が要る。
enum AXWindow {
    /// 応答しないアプリで止まり続けないよう、待つ時間を短くする（起動したときに一度だけ呼ぶ）
    static func configureMessagingTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.3)
    }

    /// 属性を読む（読めなければ nil）
    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else { return nil }
        return value as? T
    }

    /// ウインドウの枠
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let position = axValue(window, kAXPositionAttribute, type: .cgPoint, initial: CGPoint.zero),
              let size = axValue(window, kAXSizeAttribute, type: .cgSize, initial: CGSize.zero)
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// ウインドウごとの枠（読めなかったものは入らない）
    static func frames(of items: [WindowItem]) -> [AXUIElement: CGRect] {
        var frames: [AXUIElement: CGRect] = [:]
        for item in items {
            if let frame = frame(of: item.id) { frames[item.id] = frame }
        }
        return frames
    }

    /// ウインドウの枠を変える
    ///
    /// 画面の端に近いと大きさが先に削られることがあるので、大きさ → 位置 → 大きさの順に設定する。
    /// 「拡張されたユーザーインターフェイス」が有効なアプリ（VoiceOver 向け）はアニメーションで遅くなるので、その間だけ切る。
    static func setFrame(_ window: AXUIElement, pid: pid_t, to frame: CGRect) {
        let app = AXUIElementCreateApplication(pid)
        let enhanced: Bool = attribute(app, "AXEnhancedUserInterface") ?? false
        if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, false as CFBoolean) }
        defer {
            if enhanced { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, true as CFBoolean) }
        }

        var origin = frame.origin
        var size = frame.size
        guard let positionValue = AXValueCreate(.cgPoint, &origin), let sizeValue = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }

    /// 前に出す準備（しまってあれば戻し、隠したアプリなら表示する）。枠を変える前に呼ぶ
    /// - Returns: しまってあったウインドウを戻したか（戻るアニメーションの間は枠を変えても効かないことがあるので、少し待って変え直す）
    @discardableResult
    static func prepareToShow(_ window: AXUIElement, pid: pid_t) -> Bool {
        if let app = NSRunningApplication(processIdentifier: pid), app.isHidden {
            app.unhide()
        }
        let minimized: Bool = attribute(window, kAXMinimizedAttribute) ?? false
        if minimized {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, false as CFBoolean)
        }
        return minimized
    }

    /// そのアプリが実際にフォーカスしているウインドウ（ウインドウがなければ nil）
    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        attribute(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute)
    }

    /// いちばん前のアプリの、いま使っているウインドウがフルスクリーンか（フルスクリーンのデスクトップには、ストリップを出さない）
    static func frontmostWindowIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let window = focusedWindow(of: app.processIdentifier) else { return false }
        return isFullScreen(window)
    }

    /// そのウインドウがフルスクリーンか（フルスクリーンのウインドウは、自分だけのデスクトップにある）
    static func isFullScreen(_ window: AXUIElement) -> Bool {
        let fullScreen: Bool? = attribute(window, "AXFullScreen")
        return fullScreen ?? false
    }

    /// アプリが動いているか（終了したなら false）
    static func isRunning(pid: pid_t) -> Bool {
        NSRunningApplication(processIdentifier: pid).map { !$0.isTerminated } ?? false
    }

    /// ウインドウの要素が、まだ使えるか（閉じたなら false）。
    /// 別の操作スペースにあるウインドウは、ウインドウの一覧には出てこないが、まだ使える
    static func isValid(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(window, kAXRoleAttribute as CFString, &value) != .invalidUIElement
    }

    /// ウインドウを最前面に出す（アプリも前面にする）
    static func raise(_ window: AXUIElement, pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, true as CFBoolean)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, true as CFBoolean)
    }

    /// ウインドウを閉じる（ウインドウの閉じるボタンを押す。保存していなければ、アプリが聞く）。押せたら true
    @discardableResult
    static func close(_ window: AXUIElement) -> Bool {
        guard let button: AXUIElement = attribute(window, kAXCloseButtonAttribute) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    /// 点・大きさの属性を読む（CGPoint・CGSize だけに使う。中に参照を持たない型なので、そのまま書き込める）
    private static func axValue<T: BitwiseCopyable>(_ element: AXUIElement, _ name: String, type: AXValueType, initial: T) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        var result = initial
        // CFTypeRef から AXValue への変換は、型の ID を確かめたので必ず成り立つ
        let ok = withUnsafeMutableBytes(of: &result) { buffer in
            AXValueGetValue(value as! AXValue, type, buffer.baseAddress!)
        }
        return ok ? result : nil
    }
}

/// アクセシビリティの許可
enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// 許可を求めるダイアログを出す（許可していなければ）
    static func prompt() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// システム設定の「アクセシビリティ」を開く
    static func openSettings() {
        NSWorkspace.shared.open(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}
