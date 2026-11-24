import AppKit
import PinstageCore
import SwiftUI

/// ステージの並べ方・余白と、グループとして保存・記録するボタン
struct LayoutControls: View {
    let stage: StageController
    let screen: NSScreen
    let actions: AppActions

    private var current: StageBoard<AXUIElement>.Stage { stage.stage(on: screen) }

    /// 余白のボタンの絵（並べ方の絵と見分けやすいもの。オンのときは色を付ける）
    private static let gapSymbol = "rectangle.inset.filled"

    /// 並べ方が、余白を自分で持っているか（登録した型・記録した配置では、「余白を空ける」を使わない）
    private var hasOwnSpacing: Bool {
        current.layout.hasOwnSpacing
    }

    var body: some View {
        if stage.stripSettings.itemSize.isIconOnly {
            compact
        } else {
            full
        }
    }

    /// アイコンだけのとき: 並べ方のメニュー・余白・グループとして保存を、アイコンのボタンで縦に並べる
    private var compact: some View {
        VStack(spacing: 4) {
            Divider().padding(.horizontal, 6)
            layoutMenu { StripIconLabel(systemName: "rectangle.split.3x1") }
                .fixedSize()
                .help("並べ方: \(stage.layoutTitle(current.layout))")

            gapButton(explainsDisabled: false)

            Button {
                stage.saveStageAsGroup(on: screen)
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .buttonStyle(StripPrimaryButtonStyle())
            .frame(width: 40)
            .disabled(current.selection.isEmpty)
            .help("グループとして保存")

            recordButton(help: "見えている画面を記録（位置・大きさ・重なりごと、新しいグループに）")
        }
        .frame(maxWidth: .infinity)
    }

    private var full: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "ステージ", count: current.selection.members.count)
            HStack(spacing: 4) {
                // 並べ方（押すとメニュー）
                layoutMenu { LayoutPill(title: stage.layoutTitle(current.layout)) }
                    .help("並べ方を選ぶ・型を作る")
                gapButton(explainsDisabled: true)
            }

            HStack(spacing: 4) {
                Button {
                    stage.saveStageAsGroup(on: screen)
                } label: {
                    // 幅が狭いときは短く
                    ViewThatFits(in: .horizontal) {
                        Label("グループとして保存", systemImage: "plus.square.on.square")
                        Label("グループに保存", systemImage: "plus.square.on.square")
                        Label("保存", systemImage: "plus.square.on.square")
                    }
                    .lineLimit(1)
                }
                .buttonStyle(StripPrimaryButtonStyle())
                .disabled(current.selection.isEmpty)
                recordButton(help: "見えている画面を記録: このディスプレイに見えているウインドウを、位置・大きさ・重なりの順番ごと、新しいグループにします")
            }
            .help(current.selection.isEmpty ? "ステージに出しているウインドウを、グループとして保存します（いまは空です）" : "ステージに出しているウインドウを、グループとして保存します")
        }
    }

    /// 並べ方のメニュー（label を押すと出る）
    private func layoutMenu(@ViewBuilder label: () -> some View) -> some View {
        Menu {
            menuItems
        } label: {
            label()
        }
        .stripMenuButton()
    }

    /// 余白を空けるボタン。explainsDisabled なら、押せないとき（並べ方が余白を自分で持っているとき）に薄くして、理由を出す
    private func gapButton(explainsDisabled: Bool) -> some View {
        let explains = explainsDisabled && hasOwnSpacing
        return Button {
            stage.setGap(!current.hasGap, on: screen)
        } label: {
            StripIconLabel(systemName: Self.gapSymbol, isActive: current.hasGap)
        }
        .buttonStyle(.plain)
        .disabled(hasOwnSpacing)
        .opacity(explains ? 0.4 : 1)
        .help(explains ? "登録した型では、型の余白をそのまま使います" : (current.hasGap ? "余白を空ける（オン）" : "余白を空ける（オフ）"))
    }

    /// 見えている画面を、位置・大きさ・重なりごとグループとして記録するボタン
    private func recordButton(help: String) -> some View {
        Button {
            stage.recordScreenAsGroup(on: screen)
        } label: {
            StripIconLabel(systemName: "camera.viewfinder")
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// 並べ方のメニューの中身（用意した型・登録した型・型を作る）
    @ViewBuilder
    private var menuItems: some View {
        Section("用意した型") {
            ForEach(LayoutKind.allCases) { kind in
                Toggle(kind.title, isOn: Binding(
                    get: { current.layout == .builtIn(kind) },
                    set: { _ in stage.setLayout(.builtIn(kind), on: screen) }
                ))
            }
        }
        if !stage.library.customLayouts.isEmpty {
            Section("登録した型") {
                ForEach(stage.library.customLayouts) { custom in
                    Toggle(custom.name, isOn: Binding(
                        get: { current.layout == .custom(custom.id) },
                        set: { _ in stage.setLayout(.custom(custom.id), on: screen) }
                    ))
                }
            }
        }
        // 記録したグループを呼び出したときは、その配置を選んだ印を出す（ほかの型を選ぶと、そちらに変わる）
        if case .recorded = current.layout {
            Divider()
            Toggle(LayoutChoice.recordedTitle, isOn: .constant(true))
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

/// 並べ方を選ぶ欄の中身（いまの並べ方の名前と ▾）
private struct LayoutPill: View {
    let title: String
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.split.3x1")
                    Text(title).lineLimit(1)
                }
                // 狭いときは絵を省き、名前は途中で切る
                Text(title).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .semibold))
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary.opacity(0.85))
        .stripPill(isHovering: isHovering)
        .onHover { isHovering = $0 }
    }
}
