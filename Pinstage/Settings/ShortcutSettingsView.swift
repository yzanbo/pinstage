import AppKit
import PinstageCore
import SwiftUI

/// 「ショートカット」のタブ
struct ShortcutSettingsView: View {
    let shortcuts: ShortcutCenter
    let recorder: ShortcutRecorderModel

    var body: some View {
        SettingsPane {
            Section {
                rows(for: ShortcutAction.stageActions)
            } header: {
                SettingTitle("ステージ", info: "ボタンを押してからキーを押すと割り当てられます（⌘・⌥・⌃ のどれかと一緒に）。どのアプリを使っていても効きます。")
            }
            Section {
                rows(for: ShortcutAction.cycleActions)
            } header: {
                SettingTitle("切り替え", info: "グループは、最後に呼び出したグループの次・前を呼び出します。ウインドウは、ポインタのあるディスプレイで、いま前に出しているウインドウの次・前（ストリップの並び順）だけを出します。端まで行ったら反対の端に戻ります。")
            }
            Section {
                rows(for: ShortcutAction.groupActions)
            } header: {
                SettingTitle("グループ", info: "ストリップのグループの、上から数えた番号です。グループはストリップで右クリックして並べ替えられます。")
            } footer: {
                HStack {
                    Spacer()
                    Button("初期設定に戻す") {
                        recorder.stop()
                        shortcuts.resetToDefaults()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func rows(for actions: [ShortcutAction]) -> some View {
        ForEach(actions) { action in
            LabeledContent(action.title) {
                ShortcutRecorder(shortcuts: shortcuts, model: recorder, action: action)
            }
        }
    }
}

/// クリックしてからキーを押すと、そのキーをショートカットとして記録する
struct ShortcutRecorder: View {
    let shortcuts: ShortcutCenter
    let model: ShortcutRecorderModel
    let action: ShortcutAction

    private var isRecording: Bool { shortcuts.recordingAction == action }
    private var current: Shortcut? { shortcuts.shortcut(for: action) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    model.toggle(action)
                } label: {
                    Text(isRecording ? "キーを押してください…" : (current?.displayString ?? "なし"))
                        .foregroundStyle(current == nil && !isRecording ? .secondary : .primary)
                        .frame(minWidth: 130)
                }
                Button {
                    shortcuts.set(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("ショートカットを外す")
                .disabled(current == nil)
                .opacity(current == nil ? 0.3 : 1)
            }
            if let message = model.message, message.action == action {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if shortcuts.unavailable.contains(action), !isRecording {
                // ほかのアプリが同じキーを使っていると、登録できない
                Label("ほかのアプリが使っているため、効きません", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { model.stop() }
    }
}

/// ショートカットの記録（Pinshot と同じ作り）
@Observable
final class ShortcutRecorderModel {
    /// 記録の案内や、ほかの操作から外したことを知らせる文（どの操作の行に出すか）
    private(set) var message: (action: ShortcutAction, text: String)?
    /// 設定のウインドウ。記録するのは、このウインドウで押したキーだけ（ほかのウインドウのキーは横取りしない）
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let shortcuts: ShortcutCenter
    @ObservationIgnored private var monitor: Any?

    init(shortcuts: ShortcutCenter) {
        self.shortcuts = shortcuts
    }

    func toggle(_ action: ShortcutAction) {
        if shortcuts.recordingAction == action {
            stop()
        } else {
            start(action)
        }
    }

    func start(_ action: ShortcutAction) {
        stop()
        shortcuts.recordingAction = action
        // いま割り当てているキーを押しても、ここに届くよう、記録している間は止める
        shortcuts.pause()
        message = (action, "esc でやめる")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // キーを受け取ったら nil を返して、ほかへは渡さない
            let consumed = MainActor.assumeIsolated { self?.handle(event, for: action) ?? false }
            return consumed ? nil : event
        }
    }

    /// 記録中に押されたキーを受け取る（受け取ったら true）
    private func handle(_ event: NSEvent, for action: ShortcutAction) -> Bool {
        if let window, event.window !== window { return false }
        if event.keyCode == 53 { // esc
            stop()
            return true
        }
        guard let shortcut = Shortcut(event: event) else {
            message = (action, "⌘・⌥・⌃ のどれかと一緒に押してください")
            return true
        }
        stop()
        if let removed = shortcuts.set(shortcut, for: action) {
            message = (action, "「\(removed.title)」から外して、ここに割り当てました")
        }
        return true
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        let wasRecording = shortcuts.recordingAction != nil
        monitor = nil
        message = nil
        shortcuts.recordingAction = nil
        if wasRecording { shortcuts.resume() }
    }
}
