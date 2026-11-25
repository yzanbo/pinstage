import AppKit
import PinstageCore
import SwiftUI

/// ストリップ上にデスクトップごとのボタンを出す。細い帯では一つのメニューにまとめる。
struct StripDesktopList: View {
    let stage: StageController
    let strip: StripController
    let actions: AppActions
    @State private var menuAnchor = CGRect.zero

    var body: some View {
        if stage.stripSettings.showsDesktopList {
            let spaces = stage.desktopListSpaces(on: strip.screen, allDisplays: false)
            if !spaces.isEmpty {
                if strip.isCompact {
                    compactMenu(spaces).frame(maxWidth: .infinity)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 3) {
                            ForEach(spaces) { space in
                                DesktopListButton(space: space) { anchor in
                                    open(space, anchor: anchor)
                                }
                            }
                        }
                    }
                    .defaultScrollAnchor(.leading)
                    .scrollIndicators(.hidden)
                    .frame(width: strip.isHorizontal ? min(132, CGFloat(spaces.count) * 29 - 3) : nil, height: 25)
                    .accessibilityLabel("デスクトップ一覧")
                }
            }
        }
    }

    private func compactMenu(_ spaces: [DesktopListSpace]) -> some View {
        Menu {
            ForEach(spaces) { space in
                Button {
                    // メニューを閉じてから、一覧にキー入力を渡す。
                    DispatchQueue.main.async { open(space, anchor: menuAnchor) }
                } label: {
                    if space.isCurrent {
                        Label("\(space.title)（現在）", systemImage: "checkmark")
                    } else {
                        Text(space.title)
                    }
                }
            }
        } label: {
            StripIconLabel(systemName: "rectangle.on.rectangle")
        }
        .stripMenuButton()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { menuAnchor = $0 }
        .help("デスクトップ一覧")
        .accessibilityLabel("デスクトップ一覧")
    }

    private func open(_ space: DesktopListSpace, anchor: CGRect) {
        actions.openDesktopList(space.id, strip.screenRect(for: anchor), strip)
    }
}

private struct DesktopListButton: View {
    let space: DesktopListSpace
    let action: (CGRect) -> Void
    @State private var anchor = CGRect.zero
    @State private var hovering = false

    var body: some View {
        Button { action(anchor) } label: {
            Group {
                if let number = space.name.number {
                    Text("\(number)").monospacedDigit()
                } else {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(space.isCurrent ? Color.accentColor : Color.primary)
            .frame(width: 26, height: 24)
            .background(space.isCurrent ? StripStyle.selectedFill : hovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                        in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { anchor = $0 }
        .help(space.isCurrent ? "\(space.title)（現在）" : space.title)
        .accessibilityLabel(space.isCurrent ? "\(space.title)（現在）" : space.title)
    }
}

extension View {
    /// 行の右クリックとは別に、見出しとウインドウバーの空いているところで表示を切り替える。
    func desktopListContextMenu(stage: StageController) -> some View {
        contextMenu {
            Toggle("デスクトップ一覧を表示", isOn: Binding(
                get: { stage.stripSettings.showsDesktopList },
                set: { stage.stripSettings.showsDesktopList = $0 }
            ))
        }
    }
}
