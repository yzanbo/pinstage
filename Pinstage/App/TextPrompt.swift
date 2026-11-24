import AppKit

/// 名前を入力してもらう小さなダイアログ
enum TextPrompt {
    /// 入力された文字（キャンセルしたら nil）
    static func ask(title: String, defaultValue: String) -> String? {
        // メニューバーだけに常駐しているので、前面に出してから聞く（入力欄にキーが届くように）
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "キャンセル")
        let field = NSTextField(string: defaultValue)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }
}

/// してよいかを確かめるダイアログ
enum Confirmation {
    /// 「action」を押したら true
    static func ask(title: String, message: String, action: String) -> Bool {
        // メニューバーだけに常駐しているので、前面に出してから聞く
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
