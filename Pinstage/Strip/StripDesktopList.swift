import AppKit
import PinstageCore
import SwiftUI

/// ストリップ上のまとめボタンと、デスクトップごとのボタン。
struct StripDesktopList: View {
    private static let buttonSpacing: CGFloat = 3
    private static let maxVisibleRows = 4
    private static let overviewSymbol = "rectangle.on.rectangle"

    let stage: StageController
    let strip: StripController
    let actions: AppActions

    private var verticalAlignment: HorizontalAlignment { strip.isCompact ? .center : .leading }
    private var frameAlignment: Alignment { strip.isCompact ? .center : .leading }

    var body: some View {
        if stage.stripSettings.showsDesktopList {
            let spaces = stage.desktopListSpaces(on: strip.screen)
            if !spaces.isEmpty {
                buttons(spaces, presentation: stage.stripSettings.desktopButtons.presentation(isCompact: strip.isCompact))
            }
        }
    }

    @ViewBuilder
    private func buttons(_ spaces: [DesktopListSpace], presentation: StripDesktopButtons.Presentation) -> some View {
        if strip.isHorizontal {
            HStack(spacing: Self.buttonSpacing) {
                if presentation.showsOverview { overviewButton() }
                if presentation.showsDesktopNumbers { numberRow(spaces) }
            }
        } else if presentation == .desktopNumbers {
            // 「自動」の幅が広い縦バーは、個別ボタンを横に並べる。
            numberRow(spaces)
        } else {
            VStack(alignment: verticalAlignment, spacing: 4) {
                overviewButton(showsTitle: !strip.isCompact)
                if presentation.showsDesktopNumbers { numberColumn(spaces) }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }

    private func numberColumn(_ spaces: [DesktopListSpace]) -> some View {
        let rows = CGFloat(min(spaces.count, Self.maxVisibleRows))
        return ScrollView {
            VStack(spacing: Self.buttonSpacing) {
                desktopButtons(spaces, compact: strip.isCompact)
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(!strip.isCompact && spaces.count > Self.maxVisibleRows ? .visible : .hidden)
        .frame(height: rows * DesktopListButton.height + (rows - 1) * Self.buttonSpacing)
        .accessibilityLabel("デスクトップ別")
    }

    private func numberRow(_ spaces: [DesktopListSpace]) -> some View {
        let width = spaces.reduce(CGFloat.zero) { $0 + DesktopListButton.compactWidth(for: $1) }
            + CGFloat(spaces.count - 1) * Self.buttonSpacing
        return ScrollView(.horizontal) {
            HStack(spacing: Self.buttonSpacing) {
                desktopButtons(spaces, compact: true)
            }
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .frame(width: strip.isHorizontal ? min(132, width) : nil, height: DesktopListButton.height + 1)
        .accessibilityLabel("デスクトップ別")
    }

    private func desktopButtons(_ spaces: [DesktopListSpace], compact: Bool) -> some View {
        ForEach(spaces) { space in
            DesktopListButton(space: space, compact: compact) {
                actions.openWindowSwitcher(space.id, strip)
            }
        }
    }

    /// まとめボタン。⌥Tab と同じ切り替え画面（すべてのデスクトップ）を開く
    private func overviewButton(showsTitle: Bool = false) -> some View {
        Button {
            actions.openWindowSwitcher(nil, strip)
        } label: {
            if showsTitle {
                Label(WindowSwitcherSettings.title, systemImage: Self.overviewSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .stripPill(isHovering: false)
            } else {
                StripIconLabel(systemName: Self.overviewSymbol)
            }
        }
        .buttonStyle(.plain)
        .help("\(WindowSwitcherSettings.title)を開く（⌥Tab と同じ画面）")
        .accessibilityLabel(WindowSwitcherSettings.title)
    }
}

private struct DesktopListButton: View {
    let space: DesktopListSpace
    let compact: Bool
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
        Group {
            if compact {
                compactLabel.frame(width: Self.compactWidth(for: space))
            } else {
                fullLabel
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(space.isCurrent ? Color.accentColor : Color.primary)
        .frame(height: Self.height)
        .background(space.isCurrent ? StripStyle.selectedFill : hovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
    }

    private var fullLabel: some View {
        HStack(spacing: 5) {
            Text(space.name.title).lineLimit(1)
            Spacer(minLength: 0)
            if let displayNumber = space.displayNumber {
                Label("\(displayNumber)", systemImage: "display")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity)
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
            Menu("デスクトップボタンの並べ方") {
                Picker("デスクトップボタンの並べ方", selection: $stage.stripSettings.desktopButtons) {
                    ForEach(StripDesktopButtons.allCases, id: \.self) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            .disabled(!stage.stripSettings.showsDesktopList)
        }
    }
}
