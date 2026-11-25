import AppKit

/// 前面アプリを変えず、検索や一覧を開いている間だけキー入力を受けられるパネル。
final class KeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        // 日本語入力で変換している途中は、↩・↑↓を日本語入力に任せる。
        let isComposing = (firstResponder as? NSTextView)?.hasMarkedText() ?? false
        if event.type == .keyDown, !isComposing, keyHandler?(event) == true { return }
        super.sendEvent(event)
    }
}
