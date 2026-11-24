import AppKit
import PinstageCore

/// 並べ方の名前と、登録した型
extension StageController {
    /// 並べ方の名前
    func layoutTitle(_ choice: LayoutChoice) -> String {
        choice.title(customLayouts: library.customLayouts)
    }

    /// そのディスプレイのステージのウインドウの並びを、型の枠にする（重ねた形・間を空けた形もそのまま）
    func currentArrangement(on screen: NSScreen) -> [UnitRect] {
        let area = stageArea(on: screen)
        return stageItems(on: screen).compactMap { AXWindow.frame(of: $0.id) }.map { UnitRect(frame: $0, in: area) }
    }

    /// いまの並びを、そのまま型として登録する（そのディスプレイのステージの並べ方も、その型にする）
    func registerCurrentArrangement(on screen: NSScreen) {
        let slots = currentArrangement(on: screen)
        guard !slots.isEmpty else { return }
        let custom = editLibrary { $0.addCustomLayout(slots: slots) }
        updateStage(on: screen, apply: false) { $0.layout = .custom(custom.id) }
    }

    /// 型の編集画面で作った・直した型を保存する（同じ ID があれば置き換える）
    func saveCustomLayout(_ layout: CustomLayout) {
        editLibrary { $0.saveCustomLayout(layout) }
        // その型で並べているステージは、並べ直す
        for screen in NSScreen.screens where stage(on: screen).layout == .custom(layout.id) {
            applyStage(on: screen)
        }
    }

    func renameCustomLayout(_ id: UUID, to name: String) {
        editLibrary { $0.renameCustomLayout(id, to: name) }
    }

    /// 登録した型を消す（その型を使っていたグループとステージは「自動」にする）
    func deleteCustomLayout(_ id: UUID) {
        editLibrary { $0.removeCustomLayout(id) }
        for screen in NSScreen.screens where stage(on: screen).layout == .custom(id) {
            updateStage(on: screen, apply: false) { $0.layout = .builtIn(.auto) }
        }
    }
}
