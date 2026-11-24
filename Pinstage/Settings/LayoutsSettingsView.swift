import PinstageCore
import SwiftUI

/// 「型」のタブ: 登録した型の一覧（作る・直す・名前を変える・消す）
struct LayoutsSettingsView: View {
    let stage: StageController
    let editor: LayoutEditorWindowController

    var body: some View {
        SettingsPane {
            Section {
                if stage.library.customLayouts.isEmpty {
                    SettingsNote("まだ型がありません。「新しい型…」で作るか、ウインドウバーの並べ方のメニューで「いまの並びを型として登録」を選んでください。")
                }
                ForEach(stage.library.customLayouts) { layout in
                    HStack(spacing: 12) {
                        LayoutPreview(slots: layout.slots)
                            .frame(width: 80, height: 50)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(layout.name)
                            Text("\(layout.slots.count) 枠")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("編集…") { editor.edit(layout) }
                        Menu {
                            Button("名前を変更…") {
                                if let name = TextPrompt.ask(title: "型の名前", defaultValue: layout.name) {
                                    stage.renameCustomLayout(layout.id, to: name)
                                }
                            }
                            Button("複製") {
                                var copy = layout
                                copy.id = UUID()
                                copy.name = stage.library.nextCustomLayoutName
                                stage.saveCustomLayout(copy)
                            }
                            Divider()
                            Button("削除", role: .destructive) { stage.deleteCustomLayout(layout.id) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            } header: {
                SettingTitle(
                    "登録した型",
                    info: "型は並べ方の形だけを覚えます（どのアプリかは覚えません）。重ねたり、間を空けたりした形も作れます。消した型を使っていたグループは「自動（枚数に合わせる）」になります。"
                )
            } footer: {
                HStack {
                    Spacer()
                    Button("新しい型…") { editor.createNew() }
                }
            }
        }
    }
}

/// 型の小さな見本（枠の形と重なりの順番）
struct LayoutPreview: View {
    let slots: [UnitRect]

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.06))
                ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                    let frame = slot.frame(in: proxy.size)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 1))
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
    }
}
