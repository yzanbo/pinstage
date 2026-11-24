import AppKit
import PinstageCore
import SwiftUI

/// 「一般」のタブ: ストリップ・許可・バージョン
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
                        info: "Mac にログインしたときに、Pinstage を起動してストリップを出します。システム設定の「一般」→「ログイン項目」でも切り替えられます。"
                    )
                }
                if launchAtLogin.needsApproval {
                    PermissionRow(
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

            Section("ストリップ") {
                OptionPicker(
                    "出し方",
                    info: "「常に出す」はいつも画面の左端に出し、ステージはその右側を使います。「自動で隠す」はポインタを画面の左端に寄せたときだけ出し、ステージは画面いっぱいを使います。",
                    selection: binding(\.mode)
                )
                OptionPicker(
                    "出すディスプレイ",
                    info: "「すべてのディスプレイ」では、ディスプレイごとにストリップとステージを持ちます。ストリップを押したディスプレイに並べます。",
                    selection: binding(\.displays)
                )
                OptionPicker(
                    "見た目",
                    info: "「細い帯」はストリップごと細くして、アイコンだけを縦に並べます。「アイコンの並び」はストリップの幅はそのままで、アイコンだけを何個か並べます（どちらも名前はポインタを乗せると出ます）。「一覧」は名前も出します。「サムネイル」はウインドウの中身を映します（画面収録の許可が要ります。映した画像は Mac の中だけで使い、保存も送信もしません）。ストリップの見出しのボタンでも切り替えられます。",
                    selection: binding(\.itemSize)
                )
                Toggle(isOn: binding(\.keepsWindowsOffStrip)) {
                    SettingTitle(
                        "ストリップの後ろにウインドウを入り込ませない",
                        info: "「常に出す」のときに、ウインドウを広げる（タイトルバーのダブルクリック・緑のボタン・「フィル」など）か動かして、ストリップの後ろに入り込んだら、ストリップの右側に戻します。広げたウインドウはストリップの右側いっぱいに収め、もう一度ダブルクリックすると元の大きさに戻ります。ドラッグしている間は動かさず、離してから戻します。"
                    )
                }
                .disabled(stage.stripSettings.mode != .alwaysShown)
                Toggle(isOn: binding(\.showsOtherDisplays)) {
                    SettingTitle(
                        "ほかのディスプレイのウインドウ・グループも出す",
                        info: "オフのときは、ディスプレイごとのストリップに、そのディスプレイにあるウインドウ（一番大きく重なっているディスプレイのもの）と、そのディスプレイに出すグループだけを並べます。ディスプレイを決めていないグループはどのストリップにも、つながっていないディスプレイのグループはメインのディスプレイのストリップに並べます。ストリップがメインのディスプレイだけのときは、すべて並べます。"
                    )
                }
                .disabled(stage.stripSettings.displays == .mainOnly)
                Toggle(isOn: binding(\.showsOtherSpaces)) {
                    SettingTitle(
                        "ほかのデスクトップのウインドウも出す",
                        info: "オフのときは、いま見ているデスクトップ（操作スペース）のウインドウだけをストリップに並べます。しまってある（最小化した）ウインドウと、隠したアプリのウインドウは、どのデスクトップでも並べます。検索とグループの呼び出しは、オフでもすべてのウインドウを使います。"
                    )
                }
                Stepper(value: binding(\.visibleCount), in: StripSettings.visibleCountRange) {
                    SettingTitle("並べる数: \(stage.stripSettings.visibleCount) 個", info: "これより多いウインドウは「ほかのウインドウ」にたたみます。新しく開いたウインドウが上に来ます。")
                }
                if stage.stripSettings.itemSize.showsThumbnails, !thumbnails.hasPermission {
                    PermissionRow(
                        text: "画面収録の許可がないため、サムネイルを出せません（アイコンで出しています）。許可したあと、Pinstage を開き直してください。",
                        button: "画面収録を開く",
                        action: ThumbnailStore.openSettings
                    )
                }
            }

            Section("ステージ") {
                OptionPicker(
                    "1 枚だけ出すときの大きさ",
                    info: "ストリップでウインドウを 1 つだけクリックしたときの大きさです（並べ方が「重ねる」のときと、登録した型のときは、型の大きさになります）。ダブルクリックすると、いつもステージいっぱいに広げます。",
                    selection: Binding(get: { stage.singleWindowSize }, set: { stage.singleWindowSize = $0 })
                )
            }

            Section("許可") {
                LabeledContent("アクセシビリティ") {
                    if stage.isTrusted {
                        Label("許可しています", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("システム設定を開く") { AccessibilityPermission.openSettings() }
                    }
                }
                SettingsNote("ほかのアプリのウインドウを動かす・前に出すために使います。")
                LabeledContent("macOS のステージマネージャ") {
                    if stage.isSystemStageManagerOn {
                        Button("オフにする（システム設定を開く）") { SystemStageManager.openSettings() }
                    } else {
                        Label("オフです", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                SettingsNote("ステージマネージャがオンだと、macOS がウインドウの位置と大きさを抑えるので、Pinstage で並べたとおりになりません。Pinstage を使うときはオフにしてください。")
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

    /// ストリップの設定の 1 項目とつなぐ
    private func binding<Value>(_ keyPath: WritableKeyPath<StripSettings, Value>) -> Binding<Value> {
        Binding(
            get: { stage.stripSettings[keyPath: keyPath] },
            set: { stage.stripSettings[keyPath: keyPath] = $0 }
        )
    }

    private static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return version.hasPrefix("0.") ? "\(version)（試作）" : version
    }
}

/// 許可がないときの 1 行（説明と、システム設定を開くボタン）
private struct PermissionRow: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(button, action: action)
        }
    }
}
