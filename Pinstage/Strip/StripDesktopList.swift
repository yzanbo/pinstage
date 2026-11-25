import AppKit
import PinstageCore
import SwiftUI

/// ストリップ上のまとめボタンと、デスクトップごとのボタン。
struct StripDesktopList: View {
    private typealias Layout = StripDesktopButtonLayout
    private static let overviewSymbol = "rectangle.on.rectangle"

    let stage: StageController
    let strip: StripController
    let actions: AppActions

    private var verticalAlignment: HorizontalAlignment { strip.isCompact ? .center : .leading }
    private var frameAlignment: Alignment { strip.isCompact ? .center : .leading }

    var body: some View {
        if stage.stripSettings.showsDesktopList {
            let groups = stage.desktopListGroups(on: strip.screen, for: .windowBar)
            if !groups.isEmpty {
                buttons(groups, presentation: stage.stripSettings.desktopButtons.presentation(isCompact: strip.isCompact))
            }
        }
    }

    @ViewBuilder
    private func buttons(_ groups: [DesktopSpaceGroup], presentation: StripDesktopButtons.Presentation) -> some View {
        let layout = Layout(groups: groups.map { ($0.items.count, $0.id != nil) })
        if strip.isHorizontal {
            HStack(spacing: Layout.buttonSpacing) {
                if presentation.showsOverview { overviewButton() }
                if presentation.showsDesktopNumbers { numberRow(groups, layout: layout) }
            }
        } else if presentation == .desktopNumbers {
            // 「自動」の幅が広い縦バーは、個別ボタンを横に並べる。
            numberRow(groups, layout: layout)
        } else {
            VStack(alignment: verticalAlignment, spacing: 4) {
                overviewButton(showsTitle: !strip.isCompact)
                if presentation.showsDesktopNumbers { numberColumn(groups, layout: layout) }
            }
            .frame(maxWidth: .infinity, alignment: frameAlignment)
        }
    }

    private func numberColumn(_ groups: [DesktopSpaceGroup], layout: Layout) -> some View {
        ScrollView {
            groupedButtons(groups, axis: .vertical, compact: strip.isCompact)
                .frame(maxWidth: .infinity)
        }
        .scrollIndicators(!strip.isCompact && layout.columnScrolls ? .visible : .hidden)
        .frame(height: layout.columnHeight)
        .accessibilityLabel("デスクトップ別")
    }

    private func numberRow(_ groups: [DesktopSpaceGroup], layout: Layout) -> some View {
        ScrollView(.horizontal) {
            groupedButtons(groups, axis: .horizontal, compact: true)
        }
        .defaultScrollAnchor(.leading)
        .scrollIndicators(.hidden)
        .frame(width: strip.isHorizontal ? layout.rowWidth : nil, height: Layout.buttonHeight + 1)
        .accessibilityLabel("デスクトップ別")
    }

    private func groupedButtons(_ groups: [DesktopSpaceGroup], axis: Axis, compact: Bool) -> some View {
        let groupLayout = stack(axis, spacing: Layout.groupSpacing)
        let buttonLayout = stack(axis, spacing: Layout.buttonSpacing)
        return groupLayout {
            ForEach(groups) { group in
                buttonLayout {
                    ForEach(group.items) { space in
                        DesktopListButton(space: space, compact: compact) {
                            actions.openWindowSwitcher(space.id, strip)
                        }
                    }
                }
                .background(group.id == nil ? Color.clear : Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func stack(_ axis: Axis, spacing: CGFloat) -> AnyLayout {
        axis == .horizontal ? AnyLayout(HStackLayout(spacing: spacing)) : AnyLayout(VStackLayout(spacing: spacing))
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
    private typealias Layout = StripDesktopButtonLayout
    let space: DesktopListSpace
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false

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
                compactLabel.frame(width: Layout.compactWidth(showsDisplayNumber: space.displayNumber != nil))
            } else {
                fullLabel
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(space.isCurrent ? Color.accentColor : Color.primary)
        .frame(height: Layout.buttonHeight)
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
