import AppKit
import PinstageCore
import SwiftUI

struct DesktopPickerView: View {
    let model: DesktopPickerModel
    var attachment: DesktopPickerAttachment?

    var body: some View {
        let sections = model.sections
        let item = model.selectedItem(in: sections)
        let selection = item.map { $0.0.rowID($0.1) }
        VStack(alignment: .leading, spacing: 8) {
            if model.desktop == nil {
                Text(model.grouping == .byDesktop ? "デスクトップ別のウインドウ" : "ウインドウを切り替える")
                    .font(.headline)
            }
            if !model.stage.isTrusted {
                Text("ウインドウを表示するには、アクセシビリティの許可が必要です。")
                    .foregroundStyle(.secondary)
            } else if sections.isEmpty {
                Text("このデスクトップの一覧を表示できません。")
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: 3) {
                                    if !section.title.isEmpty {
                                        HStack(spacing: 8) {
                                            Text(section.title).font(.subheadline.weight(.semibold))
                                            if section.isCurrent {
                                                Text("現在").font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        .accessibilityAddTraits(.isHeader)
                                    }
                                    if section.windows.isEmpty {
                                        Text("ウインドウはありません").font(.caption).foregroundStyle(.secondary)
                                    } else if model.appearance == .list {
                                        rows(in: section, selection: selection)
                                    } else {
                                        let spacing = WindowSwitcherLayout.tileSpacing
                                        let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: model.columns)
                                        LazyVGrid(columns: columns, spacing: spacing) {
                                            rows(in: section, selection: selection)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.selected) {
                        if let selected = model.selected { proxy.scrollTo(selected) }
                    }
                }
                if model.appearance == .icons, let (section, window) = item {
                    Divider()
                    HStack(spacing: 8) {
                        Text(window.displayTitle).lineLimit(1)
                        if let badge = section.badges[window.id] {
                            Text(badge.title).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(WindowSwitcherLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator).allowsHitTesting(false))
        .padding(Edge.Set(attachment?.side ?? .leading), attachment == nil ? 0 : DesktopPickerAttachment.depth)
        .overlay {
            if let attachment { attachment.allowsHitTesting(false) }
        }
    }

    private func rows(in section: DesktopPickerSection, selection: DesktopPickerRowID?) -> some View {
        ForEach(section.windows) { window in
            let row = section.rowID(window)
            DesktopPickerEntry(
                window: window, badge: section.badges[window.id],
                appearance: model.appearance,
                thumbnail: model.appearance == .thumbnails ? model.thumbnails.images[window.id] : nil,
                selected: selection == row
            ) {
                model.activate(window, in: section)
            }
            .id(row)
            .onScrollVisibilityChange(threshold: 0.15) { visible in
                model.setPreviewVisible(row, window: window, visible)
            }
            .onDisappear { model.setPreviewVisible(row, window: window, false) }
        }
    }
}

/// ボタンと一覧のつながりを示す矢印。枠を画面内へずらしたときも、先をボタンへ向ける。
struct DesktopPickerAttachment: View {
    static let depth: CGFloat = 7
    let side: Edge
    let target: CGFloat

    init(edge: StripEdge, anchor: CGRect, panel: CGRect) {
        switch edge {
        case .left: side = .leading
        case .right: side = .trailing
        case .top: side = .top
        case .bottom: side = .bottom
        }
        target = edge.isHorizontal ? anchor.midX - panel.minX : panel.maxY - anchor.midY
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let verticalSide = side == .leading || side == .trailing
            let extent = verticalSide ? size.height : size.width
            let middle = extent >= 28 ? min(max(target, 14), extent - 14) : extent / 2
            let far = side == .trailing || side == .bottom
            let reach = verticalSide ? size.width : size.height
            let tip: CGFloat = far ? reach : 0
            let base = far ? reach - Self.depth - 1 : Self.depth + 1
            Path { path in
                func point(_ position: CGFloat, _ distance: CGFloat) -> CGPoint {
                    verticalSide ? CGPoint(x: distance, y: position) : CGPoint(x: position, y: distance)
                }
                path.move(to: point(middle, tip))
                path.addLine(to: point(middle - 6, base))
                path.addLine(to: point(middle + 6, base))
                path.closeSubpath()
            }
            .fill(.regularMaterial)
        }
    }
}

private struct DesktopPickerEntry: View {
    let window: WindowItem
    let badge: DesktopPickerBadge?
    let appearance: WindowSwitcherSettings.Appearance
    let thumbnail: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                switch appearance {
                case .list: listRow
                case .icons, .thumbnails: tile
                }
            }
            .background(selected ? StripStyle.selectedFill : hovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                        in: RoundedRectangle(cornerRadius: StripStyle.cornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(badge.map { "\(window.displayTitle) · \($0.title)" } ?? window.displayTitle)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var listRow: some View {
        HStack(spacing: 9) {
            appIcon(size: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(window.displayTitle).lineLimit(1)
                if !window.title.isEmpty {
                    Text(window.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            badgeLabel
        }
        .padding(.horizontal, 7)
        .frame(minHeight: 36)
    }

    private var tile: some View {
        VStack(spacing: 4) {
            if appearance == .thumbnails {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                    } else {
                        // 撮影中・最小化・撮影できないウインドウも、同じ大きさのまま選べる。
                        appIcon(size: 40)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 86)
                HStack(spacing: 4) {
                    appIcon(size: 14)
                    Text(window.displayTitle).font(.caption).lineLimit(1)
                    Spacer(minLength: 0)
                }
            } else {
                appIcon(size: 36)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
        }
        .padding(6)
        .overlay(alignment: .topTrailing) { badgeLabel.padding(4) }
    }

    private func appIcon(size: CGFloat) -> some View {
        Group {
            if let icon = window.icon {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var badgeLabel: some View {
        if let badge {
            Text(badge.text)
                .font(.caption2.monospacedDigit())
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.regularMaterial, in: Capsule())
                .help(badge.title)
        }
    }

    private var accessibilityTitle: String {
        let title = window.title.isEmpty ? window.displayTitle : "\(window.displayTitle)、\(window.appName)"
        return badge.map { "\(title)、\($0.title)" } ?? title
    }
}
