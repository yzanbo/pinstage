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

    /// グループの欄の高さの上限（ストリップの高さに対する割合）。超えたらスクロールする
    private static let maximumShare: CGFloat = 0.4

    var body: some View {
        let isIconOnly = stage.stripSettings.itemSize.isIconOnly
        let maximum = strip.screen.visibleFrame.height * Self.maximumShare
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
    @State private var isHovering = false
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

    /// 見本の高さ（小では見本を出さず、アイコンを並べるだけにする）
    private var mapHeight: CGFloat {
        switch size {
        case .icons, .grid: 0
        // サムネイルでも見本は大きくしない（ウインドウの欄を狭めないように）
        case .list, .thumbnail: 72
        }
    }

    var body: some View {
        // 起動していないアプリは、呼び出したときに起動し直すので、見本では薄く描く
        let running = NSWorkspace.shared.runningBundleIDs
        Group {
            if size.isIconOnly {
                GroupIconTile(group: group, running: running, shortcut: shortcutLabel, isRecalling: stage.recallingGroupID == group.id, memberDrag: memberDrag)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        if mapHeight == 0 {
                            MemberIcons(members: group.members, running: running, memberDrag: memberDrag)
                        } else {
                            Image(systemName: "square.stack.3d.up.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                        Text(group.name)
                            .font(.callout)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        trailing
                    }
                    if mapHeight > 0 {
                        GroupMap(
                            slots: GroupPreview.slots(for: group, customLayouts: stage.library.customLayouts),
                            members: group.members,
                            running: running,
                            memberDrag: memberDrag
                        )
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
                .background(
                    isHovering ? StripStyle.rowHoverFill : StripStyle.rowFill,
                    in: RoundedRectangle(cornerRadius: StripStyle.cornerRadius, style: .continuous)
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
                .animation(.easeOut(duration: 0.12), value: isHovering)
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
            Button("上へ") { stage.moveGroup(from: position, dropIndex: position - 1, on: screen) }
                .disabled(position == 0)
            Button("下へ") { stage.moveGroup(from: position, dropIndex: position + 2, on: screen) }
                .disabled(position == visibleCount - 1)
            Divider()
            Button("グループのアプリを終了…") { stage.quitApps(of: group) }
                .disabled(!group.bundleIDsToQuit.contains(where: running.contains))
            Divider()
            Button("削除", role: .destructive) { stage.deleteGroup(group.id) }
        }
    }

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

/// アイコンだけのときのグループ（中身のアイコンを 2×2 で並べ、下にショートカットを添える）
private struct GroupIconTile: View {
    let group: StageGroup
    let running: Set<String>
    let shortcut: String?
    let isRecalling: Bool
    var memberDrag: MemberDragContext?

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6)))
                LazyVGrid(columns: [GridItem(.fixed(17), spacing: 2), GridItem(.fixed(17), spacing: 2)], spacing: 2) {
                    ForEach(Array(group.members.prefix(4).enumerated()), id: \.offset) { index, member in
                        MemberIcon(bundleID: member.bundleID, size: 17, isRunning: running.contains(member.bundleID))
                            .modifier(MemberDrag(context: memberDrag, index: index, swaps: true))
                    }
                }
                if isRecalling {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 44, height: 44)
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
