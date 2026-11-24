import AppKit
import SwiftUI

/// 編集画面（グループ・型）のウインドウ。一度に 1 つだけ開き、開いている間は Dock に出す
final class EditorWindow {
    private var window: NSWindow?

    /// 開く（前に開いていたものは閉じる）。大きさは中身に合わせる
    func present(title: String, rootView: some View) {
        close()
        let controller = NSHostingController(rootView: rootView)
        controller.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        DockIcon.present(window)
    }

    func close() {
        window?.close()
    }
}

/// 編集画面のいちばん下の行（キャンセル・保存）
struct EditorFooter: View {
    /// 保存できるか（中身が空なら押せない）
    let canSave: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button("キャンセル", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button("保存", action: onSave)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
    }
}
