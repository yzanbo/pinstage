import AppKit
import PinstageCore
import SwiftUI

/// 上の帯の、ステージの並べ方を選ぶボタン（押すとメニュー。用意した型・登録した型・型を作る）
struct StripLayoutButton: View {
    let stage: StageController
    let screen: NSScreen
    let actions: AppActions

    private var current: StageBoard<AXUIElement>.Stage { stage.stage(on: screen) }

    var body: some View {
        Menu {
            menuItems
        } label: {
            StripIconLabel(systemName: "rectangle.split.3x1")
        }
        .stripMenuButton()
        .fixedSize()
        .help("並べ方: \(stage.layoutTitle(current.layout))")
    }

    /// 並べ方のメニューの中身（用意した型・登録した型・型を作る）
    @ViewBuilder
    private var menuItems: some View {
        LayoutChoiceItems(current: current.layout, customLayouts: stage.library.customLayouts) { choice in
            stage.setLayout(choice, on: screen)
        }
        Divider()
        Button("いまの並びを型として登録") { stage.registerCurrentArrangement(on: screen) }
            .disabled(current.selection.isEmpty)
        Button("いまの並びから型を作る…") { actions.createLayout(stage.currentArrangement(on: screen)) }
            .disabled(current.selection.isEmpty)
        Button("新しい型…") { actions.createLayout([]) }
        Button("型を管理…") { actions.openSettings(.layouts) }
    }
}

/// 型の一覧（用意した型・登録した型。記録した配置を選んでいるときは、その印も）。
/// 上の帯の並べ方のメニューと、グループの右クリックの「並べ方」で使う
struct LayoutChoiceItems: View {
    /// いま選んでいる並べ方（印を付ける）
    let current: LayoutChoice
    let customLayouts: [CustomLayout]
    /// 型を選んだ
    let select: (LayoutChoice) -> Void

    var body: some View {
        Section("用意した型") {
            ForEach(LayoutKind.allCases) { kind in
                toggle(kind.title, choice: .builtIn(kind))
            }
        }
        if !customLayouts.isEmpty {
            Section("登録した型") {
                ForEach(customLayouts) { custom in
                    toggle(custom.name, choice: .custom(custom.id))
                }
            }
        }
        // 記録した配置を選んでいるときは、その印を出す（ほかの型を選ぶと、そちらに変わる）
        if case .recorded = current {
            Divider()
            Toggle(LayoutChoice.recordedTitle, isOn: .constant(true))
        }
    }

    private func toggle(_ title: String, choice: LayoutChoice) -> some View {
        Toggle(title, isOn: Binding(
            get: { current == choice },
            set: { _ in select(choice) }
        ))
    }
}

/// グループを作るボタン（「グループ」の見出しの右の ＋。押すと、ステージを保存するか、見えている画面を記録するかを選ぶ）
struct GroupAddButton: View {
    let stage: StageController
    let screen: NSScreen

    private var isStageEmpty: Bool { stage.stage(on: screen).selection.isEmpty }

    var body: some View {
        Menu {
            Button("ステージをグループとして保存") { stage.saveStageAsGroup(on: screen) }
                .disabled(isStageEmpty)
            Button("見えている画面を記録") { stage.recordScreenAsGroup(on: screen) }
        } label: {
            StripIconLabel(systemName: "plus")
        }
        .stripMenuButton()
        .fixedSize()
        .help("グループを作る: ステージのウインドウを保存するか、見えている画面を位置・大きさ・重なりごと記録します")
    }
}
