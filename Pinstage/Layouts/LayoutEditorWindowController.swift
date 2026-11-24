import AppKit
import PinstageCore
import SwiftUI

/// 型の編集画面のウインドウ（一度に 1 つ。開いている間は Dock に出す）
final class LayoutEditorWindowController {
    private let stage: StageController
    private let window = EditorWindow()

    init(stage: StageController) {
        self.stage = stage
    }

    /// 新しい型を作る（slots があれば、その並びから始める）
    func createNew(from slots: [UnitRect] = []) {
        let layout = CustomLayout(
            name: stage.library.nextCustomLayoutName,
            slots: slots.isEmpty ? LayoutEditing.templates[0].slots : slots
        )
        open(layout, title: "新しい型")
    }

    /// 登録した型を直す
    func edit(_ layout: CustomLayout) {
        open(layout, title: "型を編集")
    }

    private func open(_ layout: CustomLayout, title: String) {
        let view = LayoutEditorView(
            layout: layout,
            aspectRatio: Self.stageAspectRatio(stage: stage),
            onSave: { [weak self] edited in
                self?.stage.saveCustomLayout(edited)
                self?.window.close()
            },
            onCancel: { [weak self] in self?.window.close() }
        )
        window.present(title: title, rootView: view)
    }

    /// メインのディスプレイのステージの縦横の比（編集する地を、実際のステージと同じ形にする）
    private static func stageAspectRatio(stage: StageController) -> CGFloat {
        guard let screen = NSScreen.primary else { return 16 / 10 }
        let area = stage.stageArea(on: screen)
        guard area.height > 0 else { return 16 / 10 }
        return area.width / area.height
    }
}
