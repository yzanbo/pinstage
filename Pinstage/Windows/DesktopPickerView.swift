import AppKit
import PinstageCore
import SwiftUI

/// ウインドウの切り替え画面（⌥Tab・ウインドウバーのデスクトップのボタンで開く）
struct DesktopPickerView: View {
    let model: DesktopPickerModel

    private typealias Layout = WindowSwitcherLayout

    var body: some View {
        let sections = model.sections
        let item = model.selectedItem(in: sections)
        let selection = item.map { $0.0.rowID($0.1) }
        let desktopNumbers = Dictionary(
            model.numberedDesktops(in: sections).enumerated().map { ($1.id, $0 + 1) },
            uniquingKeysWith: { first, _ in first }
        )
        VStack(alignment: .leading, spacing: Layout.blockSpacing) {
            header
            if model.isMissingThumbnailPermission {
                Text("サムネイルは画面収録の許可が必要です。許可するまではアイコンだけで表示します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(height: Layout.noticeHeight)
            }
            if !model.stage.isTrusted {
                Text("ウインドウを表示するには、アクセシビリティの許可が必要です。")
                    .foregroundStyle(.secondary)
            } else if sections.isEmpty || sections.allSatisfy({ $0.windows.isEmpty }) && !model.query.isEmpty {
                Text(model.query.isEmpty ? "このデスクトップの一覧を表示できません。" : "「\(model.query)」に合うウインドウはありません。")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: Layout.sectionTitleSpacing) {
                                    if !section.title.isEmpty {
                                        sectionTitle(section, number: desktopNumbers[section.id])
                                    }
                                    if section.windows.isEmpty {
                                        Text("ウインドウはありません")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .frame(height: Layout.emptySectionHeight)
                                    } else if model.appearance == .list {
                                        VStack(spacing: Layout.listRowSpacing) {
                                            rows(in: section, selection: selection)
                                        }
                                    } else {
                                        let spacing = Layout.tileSpacing
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
                    // スクロールバーを出すと、行の右端（デスクトップの印）がその下に隠れるので出さない（選んだ行へは自動でスクロールする）
                    .scrollIndicators(.never)
                    .onChange(of: model.selected) {
                        if let selected = model.selected { proxy.scrollTo(selected) }
                    }
                    .onChange(of: model.displaySize) {
                        if let selection { proxy.scrollTo(selection, anchor: .center) }
                    }
                    // ウインドウバーのデスクトップのボタンから開いたときは、選んだデスクトップのところを見せる
                    .onAppear {
                        if let selected = model.selected { proxy.scrollTo(selected) }
                    }
                }
                footer(item)
            }
            DesktopPickerHints()
        }
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator).allowsHitTesting(false))
    }

    /// 上の見出し（題か、打った文字）と、表示・確定方法の切り替え
    private var header: some View {
        HStack(spacing: 10) {
            if model.query.isEmpty {
                Text(WindowSwitcherSettings.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                // 打った文字（esc で消す・⌫ で 1 文字戻す）
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                    Text(model.query)
                        .lineLimit(1)
                    Rectangle().fill(Color.accentColor).frame(width: 2, height: 18)
                }
                .font(.title3)
                .padding(.horizontal, 10)
                .frame(height: Layout.headerHeight)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
                .accessibilityLabel("絞り込み: \(model.query)")
            }
            Spacer(minLength: 8)
            DesktopPickerControls(model: model)
                .layoutPriority(1)
        }
        .frame(height: Layout.headerHeight)
    }

    /// デスクトップの見出し（名前・いまのデスクトップの印・ウインドウの数。数字キーで移れる番号も添える）
    private func sectionTitle(_ section: DesktopPickerSection, number: Int?) -> some View {
        HStack(spacing: 6) {
            Text(section.title).font(.headline)
            if section.isCurrent {
                Text("現在")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            if !section.windows.isEmpty {
                Text("\(section.windows.count)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 0)
            if let number {
                Text("\(number) で移動")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(height: Layout.sectionTitleHeight)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 下の行。スペースで選んだものがあれば、その数と ↩ で並べること。なければ、選んでいるウインドウの名前（アプリ・デスクトップも添える）
    @ViewBuilder
    private func footer(_ item: (DesktopPickerSection, WindowItem)?) -> some View {
        VStack(spacing: Layout.footerSpacing) {
            Divider()
            HStack(spacing: 8) {
                if !model.marked.isEmpty {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                    Text("\(model.marked.count) 個を選んでいます")
                    Text("↩ でステージに並べる・esc で選び直す").foregroundStyle(.secondary)
                } else if let (section, window) = item {
                    Text(window.displayTitle).lineLimit(1)
                    if !window.title.isEmpty {
                        Text(window.appName).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if model.stage.isOnAllDesktops(window) {
                        DesktopBadge.allDesktops("すべてのデスクトップ", fontSize: 11)
                    } else if let badge = section.badges[window.id] {
                        DesktopBadge.otherDesktop(badge.title, fontSize: 11)
                    }
                    if model.isOnStage(window) {
                        Label("ステージに出ています", systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.footerContentHeight)
        }
    }

    private func rows(in section: DesktopPickerSection, selection: DesktopPickerRowID?) -> some View {
        ForEach(section.windows) { window in
            let row = section.rowID(window)
            DesktopPickerEntry(
                window: window, badge: section.badges[window.id],
                isOnAllDesktops: model.stage.isOnAllDesktops(window),
                appBadges: model.stage.badges(for: window),
                isOnStage: model.isOnStage(window),
                isMarked: model.isMarked(window),
                appearance: model.appearance,
                displaySize: model.displaySize,
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

/// 切り替え画面の、下の操作の案内
private struct DesktopPickerHints: View {
    var body: some View {
        HStack(spacing: 12) {
            hint("↑↓←→・Tab", "選ぶ")
            hint("↩", "開く")
            hint("space", "選んで並べる")
            hint("文字", "絞り込み")
            hint("esc", "閉じる")
            Spacer(minLength: 0)
            hint("⌘W", "閉じる")
            hint("⌘Q", "終了")
            hint("⌘M", "しまう")
            hint("⌘G", "グループ分け")
            hint("⌘1〜3", "見た目")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(height: WindowSwitcherLayout.hintsHeight)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.caption2.weight(.semibold).monospaced())
                .padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(action)
        }
        .fixedSize()
    }
}

private struct DesktopPickerControls: View {
    let model: DesktopPickerModel

    var body: some View {
        HStack(spacing: 8) {
            Picker("グループ分け", selection: Binding(get: { model.grouping }, set: { model.setGrouping($0) })) {
                ForEach(WindowSwitcherSettings.Grouping.allCases, id: \.self) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("グループ分け（⌘G で切り替え）")
            Picker("見た目", selection: Binding(get: { model.preferredAppearance }, set: { model.setAppearance($0) })) {
                ForEach(Array(WindowSwitcherSettings.Appearance.allCases.enumerated()), id: \.element) { index, appearance in
                    Image(systemName: appearance.symbolName)
                        .help("\(appearance.title)（⌘\(index + 1)）")
                        .accessibilityLabel(appearance.title)
                        .tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("見た目（⌘1 一覧・⌘2 アイコンだけ・⌘3 サムネイル）")
            Picker("大きさ", selection: Binding(get: { model.displaySize }, set: { model.setDisplaySize($0) })) {
                ForEach(WindowSwitcherSettings.DisplaySize.allCases, id: \.self) { size in
                    Text(size.title)
                        .accessibilityLabel("大きさ：\(size.title)")
                        .tag(size)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("\(WindowSwitcherSettings.title)の大きさ")
            HStack(spacing: 4) {
                Text("確定")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Picker("確定方法", selection: Binding(get: { model.confirmation }, set: { model.setConfirmation($0) })) {
                    ForEach(WindowSwitcherSettings.Confirmation.allCases, id: \.self) { confirmation in
                        Text(confirmation == .onModifierRelease ? "キーを離す" : "Enter")
                            .accessibilityLabel(confirmation.title)
                            .tag(confirmation)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .fixedSize()
            .help("ショートカットで開いたときの確定方法。⌥ を離して確定するか、Enter またはクリックで確定するかを選びます。")
        }
        .controlSize(.small)
    }
}

private struct DesktopPickerEntry: View {
    let window: WindowItem
    let badge: DesktopPickerBadge?
    /// すべてのデスクトップに割り当てたウインドウか（ウインドウバーと同じ印を付ける）
    let isOnAllDesktops: Bool
    /// 公開されたアプリのバッジ、または Dock と同じ赤い数字・点
    let appBadges: [AppIconBadge]
    /// ステージに出しているか
    let isOnStage: Bool
    /// スペースで選んでいるか（↩ でまとめてステージに並べる）
    let isMarked: Bool
    let appearance: WindowSwitcherSettings.Appearance
    let displaySize: WindowSwitcherSettings.DisplaySize
    let thumbnail: NSImage?
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    private typealias Layout = WindowSwitcherLayout

    var body: some View {
        Button(action: action) {
            Group {
                switch appearance {
                case .list: listRow
                case .icons, .thumbnails: tile
                }
            }
            .background(selected ? StripStyle.selectedFill : hovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                        in: RoundedRectangle(cornerRadius: 10))
            // 選んでいる項目は、ウインドウバーのステージに出ている行と同じく、青い枠で囲む
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.9) : .clear, lineWidth: 2)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(helpText)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var listRow: some View {
        HStack(spacing: 10) {
            markCheck
            appIcon(size: Layout.listIconSize(for: displaySize))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    stageDot
                    Text(window.displayTitle).lineLimit(1)
                }
                if !window.title.isEmpty {
                    Text(window.appName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            desktopMark(showsAllDesktops: true)
        }
        .padding(.horizontal, 10)
        .frame(height: Layout.listRowHeight(for: displaySize))
    }

    private var tile: some View {
        VStack(spacing: Layout.tileContentSpacing) {
            if appearance == .thumbnails {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        // 撮影中・最小化・撮影できないウインドウも、同じ大きさのまま選べる。
                        appIcon(size: Layout.thumbnailFallbackIconSize(for: displaySize))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.thumbnailImageHeight(for: displaySize))
                HStack(spacing: 5) {
                    stageDot
                    appIcon(size: 16)
                    Text(window.displayTitle).font(.callout).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: Layout.tileCaptionHeight(for: appearance))
            } else {
                appIcon(size: Layout.iconSize(for: displaySize))
                    .frame(maxWidth: .infinity)
                    .frame(height: Layout.iconSize(for: displaySize))
                HStack(spacing: 4) {
                    stageDot
                    Text(window.displayTitle).font(.caption).lineLimit(1).truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .frame(height: Layout.tileCaptionHeight(for: appearance))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, Layout.tileVerticalPadding(for: appearance))
        .frame(height: Layout.tileHeight(for: appearance, size: displaySize))
        // 右上は、アイコンの右上のアプリのバッジと重ならないよう空ける。デスクトップの印は左上、選んだ印は右下
        .overlay(alignment: .topLeading) { desktopMark(showsAllDesktops: appearance == .thumbnails).padding(6) }
        .overlay(alignment: .bottomTrailing) { markCheck.padding(6) }
    }

    /// アプリアイコンの隅にバッジを付ける。右下はすべてのデスクトップの印。しまってあるウインドウは薄く
    private func appIcon(size: CGFloat) -> some View {
        WindowAppIcon(image: window.icon, size: size, badges: size >= 16 ? appBadges : [],
                      isDimmed: window.isMinimized, showsAllDesktops: isOnAllDesktops && size >= 30, showsFallback: true)
            .accessibilityHidden(true)
    }

    /// ステージに出しているウインドウの印（名前の前の小さな青い点）
    @ViewBuilder private var stageDot: some View {
        if isOnStage {
            Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                .help("ステージに出ています")
        }
    }

    /// スペースで選んだ印
    @ViewBuilder private var markCheck: some View {
        if isMarked {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white, Color.accentColor)
                .help("選んでいます（↩ でステージに並べる）")
        }
    }

    /// 一覧とサムネイルには「すべて」を添える。アイコンだけのときはアイコンの右下に任せる。
    @ViewBuilder private func desktopMark(showsAllDesktops: Bool) -> some View {
        if isOnAllDesktops {
            if showsAllDesktops { DesktopBadge.allDesktops(fontSize: 10) }
        } else if let badge {
            DesktopBadge.otherDesktop(badge.text, fontSize: 10)
                .help(badge.title)
        }
    }

    /// どのデスクトップのウインドウか・ステージ・しまってあるか（ポインタを乗せたとき・読み上げ）
    private var details: [String] {
        var details: [String] = []
        if let desktop = isOnAllDesktops ? DesktopBadge.allDesktopsDescription : badge?.title { details.append(desktop) }
        if isOnStage { details.append("ステージに出ています") }
        if window.isMinimized { details.append("しまってあります") }
        details.append(contentsOf: appBadges.map(\.description))
        return details
    }

    private var helpText: String {
        ([window.displayTitle] + details).joined(separator: " · ")
    }

    private var accessibilityTitle: String {
        let title = window.title.isEmpty ? window.displayTitle : "\(window.displayTitle)、\(window.appName)"
        return ([title] + details).joined(separator: "、")
    }
}
