import AppKit
import PinstageCore
import SwiftUI

/// ストリップ上のまとめボタンと、デスクトップごとのボタン。
struct StripDesktopList: View {
    private static let buttonSpacing: CGFloat = 3
    private static let overviewSymbol = "rectangle.on.rectangle"

    let stage: StageController
    let strip: StripController
    let actions: AppActions

    var body: some View {
        if stage.stripSettings.showsDesktopList {
            let spaces = stage.desktopListSpaces(on: strip.screen)
            if !spaces.isEmpty {
                if strip.isCompact {
                    overviewButton().frame(maxWidth: .infinity)
                } else {
                    numberRow(spaces)
                }
            }
        }
    }

    private func numberRow(_ spaces: [DesktopListSpace]) -> some View {
        let width = spaces.reduce(CGFloat.zero) { $0 + DesktopListButton.compactWidth(for: $1) }
            + CGFloat(spaces.count - 1) * Self.buttonSpacing
        return ScrollView(.horizontal) {
            HStack(spacing: Self.buttonSpacing) {
                desktopButtons(spaces)
            }
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .frame(width: strip.isHorizontal ? min(132, width) : nil, height: DesktopListButton.height + 1)
        .accessibilityLabel("デスクトップ別")
    }

    private func desktopButtons(_ spaces: [DesktopListSpace]) -> some View {
        ForEach(spaces) { space in
            DesktopListButton(space: space) {
                actions.openWindowSwitcher(space.id, strip)
            }
        }
    }

    /// まとめボタン。⌥Tab と同じ切り替え画面（すべてのデスクトップ）を開く
    private func overviewButton() -> some View {
        Button {
            actions.openWindowSwitcher(nil, strip)
        } label: {
            StripIconLabel(systemName: Self.overviewSymbol)
        }
        .buttonStyle(.plain)
        .help("\(WindowSwitcherSettings.title)を開く（⌥Tab と同じ画面）")
        .accessibilityLabel(WindowSwitcherSettings.title)
    }
}

private struct DesktopListButton: View {
    let space: DesktopListSpace
    let action: () -> Void
    @State private var hovering = false

    static let height: CGFloat = 24

    static func compactWidth(for space: DesktopListSpace) -> CGFloat {
        space.displayNumber == nil ? 26 : 38
    }

    var body: some View {
        Button(action: action) {
            label
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("\(space.helpTitle)から\(WindowSwitcherSettings.title)を開く")
        .accessibilityLabel(space.helpTitle)
    }

    private var label: some View {
        compactLabel
            .frame(width: Self.compactWidth(for: space))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(space.isCurrent ? Color.accentColor : Color.primary)
        .frame(height: Self.height)
        .background(space.isCurrent ? StripStyle.selectedFill : hovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var compactLabel: some View {
        HStack(spacing: 2) {
            if let display = space.displayNumber {
                Text("\(display)·").foregroundStyle(.secondary)
            }
            if let number = space.name.number {
                Text("\(number)")
            } else {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
        }
        .monospacedDigit()
        .lineLimit(1)
    }
}

extension View {
    /// 行の右クリックとは別に、見出しとウインドウバーの空いているところで表示を切り替える。
    func desktopListContextMenu(stage: StageController) -> some View {
        @Bindable var stage = stage
        return contextMenu {
            Toggle("デスクトップボタンを表示", isOn: $stage.stripSettings.showsDesktopList)
        }
    }
}
