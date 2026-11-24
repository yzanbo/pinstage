import AppKit
import PinstageCore
import SwiftUI

/// 「一般」のタブ: 起動・ステージ・macOS の設定・バージョン（ストリップの設定は「ストリップ」のタブ）
struct GeneralSettingsView: View {
    let stage: StageController
    let thumbnails: ThumbnailStore
    let launchAtLogin: LaunchAtLogin
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

            Section("ウインドウを出すとき") {
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
                    note: "形式が「サムネイル」のときだけ、ウインドウの中身を映すために使います。",
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
                LabeledContent("バージョン", value: Self.version)
            }
        }
        // システム設定で変えられることがあるので、戻ってきたときに問い合わせ直す
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            thumbnails.captureNow()
            stage.refresh()
            launchAtLogin.refresh()
        }
    }

    private static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return version.hasPrefix("0.") ? "\(version)（試作）" : version
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
