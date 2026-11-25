import AppKit
import PinstageCore
import SwiftUI

/// 「ウインドウスイッチャー」のタブ: 開き方（ショートカット・確定のしかた）・表示・使えるキー
///
/// ウインドウバーとは別の画面（⌥Tab・ウインドウバーのデスクトップのボタンで開く）なので、タブを分ける
struct SwitcherSettingsView: View {
    @Bindable var stage: StageController
    let thumbnails: ThumbnailStore
    let shortcuts: ShortcutCenter
    let recorder: ShortcutRecorderModel

    var body: some View {
        SettingsPane {
            Section("開き方") {
                LabeledContent {
                    ShortcutRecorder(shortcuts: shortcuts, model: recorder, action: .desktopList)
                } label: {
                    SettingTitle(
                        "ショートカット",
                        info: "どのアプリを使っていても、このキーで開きます（「ショートカット」のタブと同じ設定）。ウインドウバーのデスクトップのボタンからも開けます（ボタンの表示は「ウインドウバー」のタブで切り替えます）。"
                    )
                }
                OptionPicker(
                    "確定のしかた",
                    info: "「修飾キーを離して確定」は ⌘Tab と同じく、⌥ を押したまま Tab で選び、⌥ を離すとそのウインドウに切り替えます。「Enter で確定」は、開いたまま選んで、Enter かクリックで切り替えます。ウインドウバーのボタンから開いたときは、いつも Enter かクリックで切り替えます。開いた画面の右上でも変えられます。",
                    selection: $stage.windowSwitcherSettings.confirmation,
                    segmented: true
                )
            }

            Section("表示") {
                OptionPicker(
                    "グループ分け",
                    info: "「デスクトップ別」はデスクトップごと（複数のディスプレイでは、ディスプレイごと）にまとめます。「まとめて表示」は最近使った順に並べ、ほかのデスクトップのウインドウには番号を付けます。開いた画面の右上・⌘G でも変えられます。",
                    selection: $stage.windowSwitcherSettings.grouping,
                    segmented: true
                )
                OptionPicker(
                    "見た目",
                    info: "「一覧」はアイコンと名前を行に、「アイコンだけ」はアイコンと名前を格子に並べます。「サムネイル」はウインドウの中身を映します（画面収録の許可が要ります。撮れないウインドウはアイコンと名前で表示します）。開いた画面の右上・⌘1〜3 でも変えられます。",
                    selection: Binding(
                        get: { stage.windowSwitcherSettings.appearance },
                        set: { stage.setWindowSwitcherAppearance($0, thumbnails: thumbnails) }
                    ),
                    segmented: true
                )
                if stage.windowSwitcherSettings.appearance == .thumbnails, !thumbnails.hasPermission {
                    ScreenCapturePermissionNotice(text: "画面収録の許可がない間は、アイコンだけで表示します。")
                }
                OptionPicker(
                    "大きさ",
                    info: "アイコン・一覧の行・サムネイルの大きさです。ウインドウバーの大きさには影響しません。開いた画面の右上でも変えられます。",
                    selection: $stage.windowSwitcherSettings.displaySize,
                    segmented: true
                )
            }

            Section {
                // 画面の下の案内と同じものから作る（PinstageCore の WindowSwitcherKeyGuide）
                ForEach(WindowSwitcherKeyGuide.entries, id: \.keys) { entry in
                    LabeledContent {
                        Text(entry.keys)
                            .font(.callout.monospaced())
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(entry.detail)
                    }
                }
            } header: {
                SettingTitle("開いているときに使えるキー", info: "画面の下にも、同じ案内が出ます。")
            }
        }
        .refreshesScreenCapturePermission(thumbnails)
    }
}
