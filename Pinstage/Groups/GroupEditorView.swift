import AppKit
import PinstageCore
import SwiftUI

/// グループの編集画面（名前・中身・並べ方・出すディスプレイ）
///
/// 中身の並び順は、並べたときの順番（後ろほど前面。型の枠の番号と同じ）。
struct GroupEditorView: View {
    let stage: StageController
    let onSave: (StageGroup) -> Void
    let onCancel: () -> Void
    @State private var group: StageGroup

    init(group: StageGroup, stage: StageController, onSave: @escaping (StageGroup) -> Void, onCancel: @escaping () -> Void) {
        _group = State(initialValue: group)
        self.stage = stage
        self.onSave = onSave
        self.onCancel = onCancel
    }

    /// 足せるウインドウ（いま開いていて、まだ中身に入っていないもの）
    private var addableWindows: [WindowItem] {
        stage.windows.filter { window in
            guard let signature = window.signature else { return false }
            return !group.members.contains(signature)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("グループの名前", text: $group.name)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            HStack(alignment: .top, spacing: 16) {
                members
                    .frame(minWidth: 320)
                VStack(alignment: .leading, spacing: 10) {
                    Text("並びの見本").font(.caption).foregroundStyle(.secondary)
                    GroupMap(
                        slots: GroupPreview.slots(for: group, customLayouts: stage.library.customLayouts),
                        members: group.members,
                        running: NSWorkspace.shared.runningBundleIDs
                    )
                    .frame(width: 200, height: 125)
                    layoutControls
                }
                .frame(width: 220)
            }

            EditorFooter(canSave: !group.members.isEmpty, onCancel: onCancel) { onSave(group) }
        }
        .padding(16)
        .frame(width: 600)
    }

    /// 中身の一覧（並べ替え・外す・足す）
    private var members: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("中身（上から順に並べる。下ほど前面）").font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(Array(group.members.enumerated()), id: \.offset) { index, member in
                    HStack(spacing: 8) {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        MemberIcon(bundleID: member.bundleID, size: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(AppIcons.name(for: member.bundleID)).lineLimit(1)
                            if !member.title.isEmpty {
                                Text(member.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Button {
                            group.members.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("グループから外す")
                    }
                }
                .onMove { source, destination in
                    group.members.move(fromOffsets: source, toOffset: destination)
                }
            }
            .frame(height: 220)
            .overlay {
                if group.members.isEmpty {
                    Text("ウインドウがありません").foregroundStyle(.secondary)
                }
            }

            Menu {
                if addableWindows.isEmpty {
                    Text("足せるウインドウがありません")
                }
                ForEach(addableWindows) { window in
                    Button {
                        if let signature = window.signature { group.members.append(signature) }
                    } label: {
                        if let icon = window.icon {
                            Label { Text("\(window.displayTitle)（\(window.appName)）") } icon: { Image(nsImage: icon) }
                        } else {
                            Text("\(window.displayTitle)（\(window.appName)）")
                        }
                    }
                }
            } label: {
                Label("ウインドウを足す", systemImage: "plus")
            }
            .fixedSize()
            Text("ドラッグで並べ替えられます。閉じているアプリのウインドウは、呼び出したときに起動し直します。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 並べ方・出すディスプレイ
    private var layoutControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("並べ方", selection: $group.layout) {
                ForEach(LayoutKind.allCases) { kind in
                    Text(kind.title).tag(LayoutChoice.builtIn(kind))
                }
                if !stage.library.customLayouts.isEmpty {
                    Divider()
                    ForEach(stage.library.customLayouts) { custom in
                        Text(custom.name).tag(LayoutChoice.custom(custom.id))
                    }
                }
                // 見えている画面を記録したグループは、その配置のまま選べるようにしておく
                if case .recorded = group.layout {
                    Divider()
                    Text(LayoutChoice.recordedTitle).tag(group.layout)
                }
            }
            Picker("ディスプレイ", selection: $group.displayID) {
                Text("ポインタのあるディスプレイ").tag(String?.none)
                ForEach(NSScreen.screens, id: \.displayUUID) { screen in
                    Text(screen.localizedName).tag(screen.displayUUID)
                }
                // 覚えているディスプレイがつながっていなければ、そのまま選べるようにしておく
                if let id = group.displayID, NSScreen.screen(withDisplayUUID: id) == nil {
                    Text(NSScreen.displayName(forDisplayUUID: id)).tag(String?.some(id))
                }
            }
        }
    }
}

/// グループの編集画面のウインドウ（一度に 1 つ。開いている間は Dock に出す）
final class GroupEditorWindowController {
    private let stage: StageController
    private let window = EditorWindow()

    init(stage: StageController) {
        self.stage = stage
    }

    func edit(_ group: StageGroup) {
        let view = GroupEditorView(
            group: group,
            stage: stage,
            onSave: { [weak self] edited in
                self?.stage.updateGroup(edited)
                self?.window.close()
            },
            onCancel: { [weak self] in self?.window.close() }
        )
        window.present(title: "グループを編集", rootView: view)
    }
}
