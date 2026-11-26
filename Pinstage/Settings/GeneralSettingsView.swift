import AppKit
import PinstageCore
import SwiftUI

/// 「一般」のタブ: 起動・ステージ・macOS の設定・アップデートとバージョン（ウインドウバー・ウインドウスイッチャーの設定は、それぞれのタブ）
struct GeneralSettingsView: View {
    let stage: StageController
    let thumbnails: ThumbnailStore
    let launchAtLogin: LaunchAtLogin
    let updates: AppUpdates
    var body: some View {
        SettingsPane {
            Section("起動") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin.isRegistered },
                    set: { launchAtLogin.setEnabled($0) }
                )) {
                    SettingTitle(
                        "ログイン時に起動",
                        info: "Mac にログインしたときに、Pinstage を起動してウインドウバーを出します。システム設定の「一般」→「ログイン項目」でも切り替えられます。"
                    )
                }
                if launchAtLogin.needsApproval {
                    NoticeRow(
                        text: "システム設定の「ログイン項目」で許可すると、ログイン時に起動します。",
                        button: "ログイン項目を開く",
                        action: launchAtLogin.openSystemSettings
                    )
                }
                if let message = launchAtLogin.errorMessage {
                    Label(message, systemImage: "xmark.octagon.fill")
                        .symbolRenderingMode(.multicolor)
                        .font(.callout)
                }
            }

            Section("ステージ") {
                OptionPicker(
                    "1 枚だけ出すときの大きさ",
                    info: "ウインドウバーでウインドウを 1 つだけクリックしたときの大きさです（登録した型・記録した配置のときは、型の大きさになります）。ダブルクリックすると、いつもステージいっぱいに広げます。",
                    selection: Binding(get: { stage.singleWindowSize }, set: { stage.singleWindowSize = $0 })
                )
            }

            Section("macOS の設定") {
                SystemStatusRow(
                    title: "アクセシビリティ",
                    note: "ほかのアプリのウインドウを動かす・前に出すために使います。",
                    isOK: stage.isTrusted,
                    okLabel: "許可しています",
                    button: "システム設定を開く",
                    action: AccessibilityPermission.openSettings
                )
                SystemStatusRow(
                    title: "画面収録",
                    note: "ウインドウバー・\(WindowSwitcherSettings.title)をサムネイルで表示するときだけ、ウインドウの中身を映すために使います。",
                    isOK: thumbnails.hasPermission,
                    okLabel: "許可しています",
                    button: "システム設定を開く",
                    action: ThumbnailStore.openSettings
                )
                SystemStatusRow(
                    title: "ステージマネージャ",
                    note: "オンだと、macOS がウインドウの位置と大きさを抑えるので、Pinstage で並べたとおりになりません。",
                    isOK: !stage.isSystemStageManagerOn,
                    okLabel: "オフです",
                    button: "オフにする（システム設定を開く）",
                    action: SystemStageManager.openSettings
                )
            }

            Section {
                // 更新の機能を使えるビルドだけ（公開鍵の入っていないビルドでは、版だけを出す）
                if updates.isAvailable {
                    Toggle(isOn: Binding(
                        get: { updates.checksAutomatically },
                        set: { updates.setChecksAutomatically($0) }
                    )) {
                        SettingTitle(
                            "新しい版を自動で確かめる",
                            info: "1 時間に 1 回、GitHub に新しい版がないかを確かめます。見つかると、メニューバーのアイコンの右下に下向きの矢印の印が付き、メニューのいちばん上から更新できます（画面には割り込みません）。オフにしても、メニューの「アップデートを確認…」でいつでも確かめられます。"
                        )
                    }
                }
                LabeledContent("バージョン") {
                    HStack(spacing: 10) {
                        Text(Self.version)
                        if updates.isAvailable {
                            Button("アップデートを確認…") { updates.check() }
                                .disabled(!updates.canCheck)
                        }
                    }
                }
            } header: {
                Text("アップデート")
            } footer: {
                if updates.isAvailable {
                    SettingsNote(Self.lastCheckNote(updates.lastCheckDate))
                } else {
                    SettingsNote("このビルドには、更新ファイルを確かめる鍵が入っていないので、アップデートの確認は使えません。")
                }
            }
        }
        // システム設定で変えられることがあるので、開いたとき・戻ってきたときに問い合わせ直す
        .onAppear(perform: refreshSystemState)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            thumbnails.captureNow()
            stage.refresh()
            refreshSystemState()
        }
    }

    /// macOS と更新の仕組みに、今の状態を聞き直す（ログイン項目・自動で確かめるか・最後に確かめた日時。Pinshelf と同じ）
    private func refreshSystemState() {
        launchAtLogin.refresh()
        updates.refresh()
    }

    /// 最後に確かめた日時の説明
    private static func lastCheckNote(_ date: Date?) -> String {
        guard let date else { return "まだ確かめていません。" }
        return "最後に確かめた日時：\(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// 版（1.0.0 より前は「（β 版）」を付ける。決まりは PinstageCore の AppVersion）
    private static var version: String {
        AppVersion.displayName(Bundle.main.shortVersion ?? "—")
    }
}

/// macOS の設定の状態の 1 行（項目名の下に、何に使うかを小さく添える。右に、よければ緑の印、よくなければシステム設定を開くボタン）
private struct SystemStatusRow: View {
    let title: String
    let note: String
    let isOK: Bool
    let okLabel: String
    let button: String
    let action: () -> Void

    var body: some View {
        LabeledContent {
            if isOK {
                Label(okLabel, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button(button, action: action)
            }
        } label: {
            Text(title)
            Text(note)
        }
    }
}
