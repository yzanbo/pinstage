import AppKit
import PinstageCore
import SwiftUI

struct GroupSection: View {
    let stage: StageController
    let shortcuts: ShortcutCenter
    let strip: StripController
    let actions: AppActions
    @State private var reorder = ReorderState()
    /// グループの一覧の中身の高さ（多いときは、この欄だけスクロールさせる）
    @State private var contentHeight: CGFloat = 0

    /// 横長の帯で、グループの一覧の中身の幅（多いときは、この欄だけ横にスクロールさせる）
    @State private var contentWidth: CGFloat = 0

    /// グループの欄の高さの上限（ストリップの高さに対する割合）。超えたらスクロールする
    private static let maximumShare: CGFloat = 0.4
    /// 横長の帯で、グループの欄の幅の上限（ストリップの幅に対する割合）
    private static let maximumBarShare: CGFloat = 0.3

    var body: some View {
        if strip.isHorizontal {
            bar
        } else {
            column
        }
    }

    /// グループの行
    private func rows(_ visible: [StageGroup]) -> some View {
        ForEach(Array(visible.enumerated()), id: \.element.id) { position, group in
            GroupRow(
                group: group,
                index: stage.library.groupIndex(id: group.id) ?? position,
                position: position,
                visibleCount: visible.count,
                reorder: reorder, stage: stage, shortcuts: shortcuts, strip: strip, actions: actions
            )
        }
    }

    /// 上下に出したとき: グループを横に並べる（グループがなければ、何も出さない。多いときは、この欄だけ横にスクロール）
    @ViewBuilder
    private var bar: some View {
        let visible = stage.groups(on: strip.screen)
        if !visible.isEmpty {
            BarDivider()
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    rows(visible)
                }
                .coordinateSpace(.named(ReorderState.groupSpace))
                .overlay(alignment: .topLeading) { DropLine(reorder: reorder, count: visible.count, layout: .columns) }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { contentWidth = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            // 少ないときは中身の幅、多いときは上限まで（ウインドウの一覧を潰さないように）
            .frame(width: min(contentWidth, strip.visibleFrame.width * Self.maximumBarShare))
            // スクロールで隠れたグループには落とさないよう、見えている範囲を覚える
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GroupDropTargets.space)) } action: { strip.groupTargets.viewport = $0 }
        }
    }

    /// 左右に出したとき: グループを縦に並べる
    @ViewBuilder
    private var column: some View {
        let isIconOnly = strip.isCompact
        let maximum = strip.visibleFrame.height * Self.maximumShare
        VStack(alignment: .leading, spacing: 6) {
            // このディスプレイのストリップに並べるグループ（並び順は全体のまま）
            let visible = stage.groups(on: strip.screen)
            if !isIconOnly {
                SectionHeader(title: "グループ", count: visible.count)
            } else if !visible.isEmpty {
                Divider().padding(.horizontal, 6)
            }
            if visible.isEmpty, !isIconOnly {
                Text(stage.library.groups.isEmpty
                    ? "ステージに出した組み合わせを「グループとして保存」すると、ここに並びます"
                    : "このディスプレイのグループはありません。ここで「グループとして保存」すると、このディスプレイのグループになります")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    rows(visible)
                }
                .coordinateSpace(.named(ReorderState.groupSpace))
                .overlay(alignment: .topLeading) { DropLine(reorder: reorder, count: visible.count) }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .scrollIndicators(.never)
            .scrollBounceBehavior(.basedOnSize)
            // 少ないときは中身の高さ、多いときは上限まで（ウインドウの一覧を潰さないように）
            .frame(height: min(contentHeight, maximum))
            // スクロールで隠れた行には落とさないよう、見えている範囲を覚える
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GroupDropTargets.space)) } action: { strip.groupTargets.viewport = $0 }
        }
    }
}

private struct GroupRow: View {
    let group: StageGroup
    /// 全体の並びでの番号（ショートカットの番号に使う）
    let index: Int
    /// このストリップに並べている中での番号（ドラッグ・上へ下への並べ替えに使う）
    let position: Int
    /// このストリップに並べているグループの数
    let visibleCount: Int
    let reorder: ReorderState
    let stage: StageController
    let shortcuts: ShortcutCenter
    let strip: StripController
    let actions: AppActions

    private var screen: NSScreen { strip.screen }

    private var size: StripItemSize { stage.stripSettings.itemSize }

    /// 見本の高さ（アイコンの並びでは見本を出さず、アイコンを並べるだけにする）
    private var mapHeight: CGFloat {
        switch size {
        case .grid: 0
        // サムネイルでも見本は大きくしない（ウインドウの欄を狭めないように）
        case .list, .thumbnail: 72
        }
    }

    var body: some View {
        // 起動していないアプリは、呼び出したときに起動し直すので、見本では薄く描く
        let running = NSWorkspace.shared.runningBundleIDs
        Group {
            if strip.isCompact {
                GroupIconTile(
                    group: group, running: running, shortcut: shortcutLabel, isRecalling: stage.recallingGroupID == group.id,
                    isSmall: stage.stripSettings.iconSize == .small, memberDrag: memberDrag
                )
            } else if strip.isHorizontal {
                barRow(running: running)
            } else {
                columnRow(running: running)
            }
        }
        // ウインドウを重ねているときは、ここに入ることが分かるように光らせる
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(isDropTarget ? 1 : 0)
                .allowsHitTesting(false)
        )
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(GroupDropTargets.space)) } action: { strip.groupTargets.frames[group.id] = $0 }
        .onDisappear { strip.groupTargets.frames[group.id] = nil }
        .modifier(ReorderDrag(
            index: position,
            count: visibleCount,
            space: ReorderState.groupSpace,
            layout: strip.isHorizontal ? .columns : .rows,
            reorder: reorder,
            strip: strip,
            onTap: { Task { await stage.recall(group, fallback: screen) } },
            onMove: { stage.moveGroup(from: position, dropIndex: $0, on: screen) }
        ))
        .help(helpText(running: running))
        .contextMenu {
            Button("編集…") { actions.editGroup(group) }
            Button("名前を変更…") {
                if let name = TextPrompt.ask(title: "グループの名前", defaultValue: group.name) {
                    stage.renameGroup(group.id, to: name)
                }
            }
            Button("いまのステージで上書き保存") { stage.overwriteGroup(group.id, on: screen) }
                .disabled(stage.stage(on: screen).selection.isEmpty)
            Button("見えている画面で上書き記録") { stage.rerecordGroup(group.id, on: screen) }
            Divider()
            Button(strip.isHorizontal ? "左へ" : "上へ") { stage.moveGroup(from: position, dropIndex: position - 1, on: screen) }
                .disabled(position == 0)
            Button(strip.isHorizontal ? "右へ" : "下へ") { stage.moveGroup(from: position, dropIndex: position + 2, on: screen) }
                .disabled(position == visibleCount - 1)
            Divider()
            Button("グループのアプリを終了…") { stage.quitApps(of: group) }
                .disabled(!group.bundleIDsToQuit.contains(where: running.contains))
            Divider()
            Button("削除", role: .destructive) { stage.deleteGroup(group.id) }
        }
    }

    /// 左右のストリップでの行。名前の下に見本を出す（アイコンの並びでは、見本の代わりに中身のアイコンを名前の前に並べる）
    private func columnRow(running: Set<String>) -> some View {
        let showsMap = mapHeight > 0
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                leadingMark(running: running, showsMap: showsMap)
                nameText
                Spacer(minLength: 0)
                trailing
            }
            if showsMap {
                map(running: running)
                    // 行の幅いっぱいに、画面と同じ横長の形で描く（高さは上限まで）
                    .aspectRatio(GroupPreview.aspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: mapHeight)
            }
            if let display = stage.displayName(for: group) {
                Label(display, systemImage: "display")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HoverRowBackground())
    }

    /// 横長の帯（上下のストリップ）での行。名前と中身のアイコンを 1 行で出し、サムネイルの形式では、見本も出す
    private func barRow(running: Set<String>) -> some View {
        let showsMap = size == .thumbnail
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                leadingMark(running: running, showsMap: showsMap)
                if showsMap {
                    // 見本を出す行は幅を決めているので、名前は収まるところで切る
                    nameText
                    Spacer(minLength: 0)
                } else {
                    // 名前の長さに合わせた幅にする（長い名前は、上限で切る）
                    nameText
                        .frame(maxWidth: Self.barNameWidth, alignment: .leading)
                        .fixedSize()
                }
                trailing
            }
            if showsMap {
                map(running: running)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, showsMap ? 7 : 0)
        .frame(width: showsMap ? Self.barMapWidth : nil, height: StripRowSizing.barRowHeight(kind: strip.rowKind))
        .modifier(HoverRowBackground())
    }

    /// 名前の前の印（見本を出すときはグループの印、出さないときは中身のアイコン）
    @ViewBuilder
    private func leadingMark(running: Set<String>, showsMap: Bool) -> some View {
        if showsMap {
            Image(systemName: "square.stack.3d.up.fill")
                .foregroundStyle(Color.accentColor)
        } else {
            MemberIcons(members: group.members, running: running, memberDrag: memberDrag)
        }
    }

    private var nameText: some View {
        Text(group.name)
            .font(.callout)
            .lineLimit(1)
    }

    /// グループの見本（呼び出したときの並び）
    private func map(running: Set<String>) -> some View {
        GroupMap(
            slots: GroupPreview.slots(for: group, customLayouts: stage.library.customLayouts),
            members: group.members,
            running: running,
            memberDrag: memberDrag
        )
    }

    /// 横長の帯での、名前の幅の上限と、見本を出すときの行の幅
    private static let barNameWidth: CGFloat = 120
    private static let barMapWidth: CGFloat = 150

    /// ウインドウ・ほかのグループの中身を、このグループに重ねているか
    private var isDropTarget: Bool {
        strip.groupTargets.hovered == group.id
    }

    /// 見本のアイコンをドラッグして、外す・ほかのグループへ移すための手がかり
    private var memberDrag: MemberDragContext {
        MemberDragContext(groupID: group.id, strip: strip, stage: stage)
    }

    /// このグループのショートカット（割り当てていなければ nil）
    private var shortcutLabel: String? {
        ShortcutAction.group(at: index).flatMap { shortcuts.shortcut(for: $0) }?.displayString
    }

    @ViewBuilder
    private var trailing: some View {
        if stage.recallingGroupID == group.id {
            ProgressView().controlSize(.small)
        } else if let action = ShortcutAction.group(at: index), let shortcut = shortcuts.shortcut(for: action) {
            Text(shortcut.displayString)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    /// ポインタを乗せたときに出す中身の一覧（番号は並べる順番。大きい番号ほど前面）
    private func helpText(running: Set<String>) -> String {
        let lines = group.members.enumerated().map { index, member in
            let app = AppIcons.name(for: member.bundleID)
            let title = member.title.isEmpty ? "" : "「\(member.title)」"
            let note = running.contains(member.bundleID) ? "" : "（起動していません。呼び出すと起動します）"
            return "\(index + 1). \(app)\(title)\(note)"
        }
        return (["\(group.name)・\(stage.layoutTitle(group.layout))"] + lines).joined(separator: "\n")
    }
}

/// 細い帯（アイコンの並びを狭めたとき）のグループ（中身のアイコンを 2×2 で並べ、下にショートカットを添える）
private struct GroupIconTile: View {
    let group: StageGroup
    let running: Set<String>
    let shortcut: String?
    let isRecalling: Bool
    /// アイコンの並びのアイコンが小さいか（細い帯の幅に合わせて、タイルも小さくする）
    var isSmall = false
    var memberDrag: MemberDragContext?

    /// タイルの一辺と、中のアイコンの一辺
    private var tileSize: CGFloat { isSmall ? 36 : 44 }
    private var iconSize: CGFloat { isSmall ? 13 : 17 }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6)))
                LazyVGrid(columns: [GridItem(.fixed(iconSize), spacing: 2), GridItem(.fixed(iconSize), spacing: 2)], spacing: 2) {
                    ForEach(Array(group.members.prefix(4).enumerated()), id: \.offset) { index, member in
                        MemberIcon(bundleID: member.bundleID, size: iconSize, isRunning: running.contains(member.bundleID))
                            .modifier(MemberDrag(context: memberDrag, index: index, swaps: true))
                    }
                }
                if isRecalling {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: tileSize, height: tileSize)
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 9).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

/// グループの中身のアプリのアイコンを、少し重ねて並べる（大きさが「小」のとき）
private struct MemberIcons: View {
    let members: [WindowSignature]
    let running: Set<String>
    var memberDrag: MemberDragContext?
    /// 並べるアイコンの数（多いときは「+n」を添える）
    private static let limit = 4

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(members.prefix(Self.limit).enumerated()), id: \.offset) { index, member in
                MemberIcon(bundleID: member.bundleID, size: 16, isRunning: running.contains(member.bundleID))
                    .modifier(MemberDrag(context: memberDrag, index: index, swaps: false))
            }
            if members.count > Self.limit {
                Text("+\(members.count - Self.limit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
            }
        }
    }
}

/// グループの行の地（ポインタを乗せたら少し濃くする）
private struct HoverRowBackground: ViewModifier {
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(
                isHovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                in: RoundedRectangle(cornerRadius: StripStyle.cornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}
