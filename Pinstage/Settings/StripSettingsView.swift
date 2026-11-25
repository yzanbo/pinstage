import AppKit
import PinstageCore
import SwiftUI

/// 「ストリップ」のタブ: 置き方・見た目・並べるウインドウ
struct StripSettingsView: View {
    @Bindable var stage: StageController
    let thumbnails: ThumbnailStore
    /// ストリップと同じ辺で重なる、自動で隠れる Dock・メニューバー（タブを開いたとき・戻ってきたとき・位置を変えたときに読み直す）
    @State private var edgeConflict: StripEdgeConflict?

    var body: some View {
        SettingsPane {
            Section("置き方") {
                OptionPicker(
                    "出し方",
                    info: "「常に出す」はいつも画面の端に出し、ステージはウインドウバーを除いた残りになります。「自動で隠す」はポインタを、ウインドウバーのある端に寄せたときだけ出し、ステージは画面いっぱいになります。",
                    selection: $stage.stripSettings.mode,
                    segmented: true
                )
                // 「常に出す」のときだけ使うので、出し方のすぐ下に置く
                Toggle(isOn: $stage.stripSettings.keepsWindowsOffStrip) {
                    SettingTitle(
                        "ウインドウバーの後ろにウインドウを入り込ませない",
                        info: "「常に出す」のときに、ウインドウを広げる（タイトルバーのダブルクリック・緑のボタン・「フィル」など）か動かして、ウインドウバーの後ろに入り込んだら、ステージ（ウインドウバーを除いた残り）に戻します。広げたウインドウはステージいっぱいに収め、もう一度ダブルクリックすると元の大きさに戻ります。ドラッグしている間は動かさず、離してから戻します。"
                    )
                }
                .disabled(stage.stripSettings.mode != .alwaysShown)
                OptionPicker(
                    "位置",
                    info: "ウインドウバーを出す辺です。「左」「右」は縦長の帯で、内側の縁をドラッグして幅を変えられます。「上」「下」は横長の帯で、ウインドウを横に並べます（高さは形式と大きさで決まります）。常に表示している Dock・メニューバーと同じ辺では、その内側に並びます。ウインドウバーの見出しの、見た目のボタンでも切り替えられます。",
                    selection: $stage.stripSettings.edge,
                    segmented: true
                )
                if let conflict = edgeConflict {
                    NoticeRow(
                        text: conflict.message,
                        button: conflict == .autoHidingDock ? "Dock の設定を開く" : "メニューバーの設定を開く",
                        action: conflict == .autoHidingDock ? SystemBars.openDockSettings : SystemBars.openMenuBarSettings
                    )
                }
                LabeledContent {
                    // 数を左、増やす・減らすボタンを右に（macOS の設定と同じ並び）
                    HStack(spacing: 6) {
                        Text("\(Int(stage.stripSettings.stageGap)) pt")
                            .monospacedDigit()
                        Stepper("ステージとの間", value: $stage.stripSettings.stageGap, in: StripGeometry.stageGapRange, step: 2)
                            .labelsHidden()
                    }
                } label: {
                    SettingTitle("ステージとの間", info: "「常に出す」のときの、ウインドウバーと、並べたウインドウ（ステージ）との間です。0 にすると、ウインドウバーのすぐ横から並べます。ウインドウバーは、画面の端にはすき間なく付けます。")
                }
                .disabled(stage.stripSettings.mode != .alwaysShown)
                OptionPicker(
                    "出すディスプレイ",
                    info: "「すべてのディスプレイ」では、ディスプレイごとにウインドウバーとステージを持ちます。ウインドウバーを押したディスプレイに並べます。",
                    selection: $stage.stripSettings.displays
                )
            }

            Section("見た目") {
                OptionPicker(
                    "形式",
                    info: "ウインドウの並べ方です。「アイコンの並び」はアイコンだけを、幅に入るだけ並べます（名前はポインタを乗せると出ます。幅を狭めると 1 列になります）。「一覧」は、ブラウザの縦のタブのように、アイコンと名前を 1 行で並べます。「サムネイル」はウインドウの中身を映します（画面収録の許可が要ります。映した画像は Mac の中だけで使い、保存も送信もしません）。ウインドウバーの見出しのボタンでも切り替えられます。",
                    selection: $stage.stripSettings.itemSize
                )
                if stage.stripSettings.itemSize.showsThumbnails, !thumbnails.hasPermission {
                    NoticeRow(
                        text: "画面収録の許可がないため、サムネイルを出せません（アイコンで出しています）。許可したあと、Pinstage を開き直してください。",
                        button: "画面収録を開く",
                        action: ThumbnailStore.openSettings
                    )
                }
                OptionPicker(
                    "大きさ",
                    info: "どの形式にもかかる大きさです。「一覧」では行の高さ・アイコン・文字（「小」はブラウザの縦のタブと同じくらい）、「サムネイル」では映す大きさのいちばん小さい値、「アイコンの並び」ではアイコンの大きさが変わります。アイコンの並びは、内側の縁をドラッグして、アイコンが 1 列になる幅（細い帯）まで狭められます。アイコンの並びの幅は、一覧・サムネイルの幅とは別に覚えます。ウインドウバーの見出しの、見た目のボタンでも切り替えられます。",
                    selection: $stage.stripSettings.iconSize,
                    segmented: true
                )
            }

            Section("並べるウインドウ") {
                Toggle(isOn: $stage.stripSettings.showsDesktopList) {
                    SettingTitle(
                        "デスクトップボタンを表示",
                        info: "ウインドウバーにデスクトップごとのボタンを並べます。ボタンを押すと、\(WindowSwitcherSettings.title)がそのデスクトップの最初のウインドウを選んだ状態で開きます。オフでも、ショートカットから開けます。"
                    )
                }
                Toggle(isOn: $stage.stripSettings.groupsSameApp) {
                    SettingTitle(
                        "同じアプリのウインドウをまとめる",
                        info: "オンのときは、同じアプリのウインドウを、いつもとなりに並べて 1 つの枠でつなぎます。ドラッグすると、同じアプリのウインドウがまとまったまま動きます（ステージやグループの上で離すと、まとまりのウインドウをすべて足します）。オフのときは、新しく開いたウインドウを同じアプリのウインドウのすぐ後ろに入れるだけで、ドラッグで 1 つずつ離して置けます。"
                    )
                }
            }

            Section(WindowSwitcherSettings.title) {
                OptionPicker(
                    "グループ分け",
                    info: "ショートカット（初期設定は ⌥Tab）と、ウインドウバーのデスクトップのボタンで開く画面に適用します。開いた画面の右上でも変えられます。「まとめて表示」では最近使った順に並び、ほかのデスクトップにあるウインドウには番号を付けます。",
                    selection: $stage.windowSwitcherSettings.grouping
                )
                OptionPicker(
                    "見た目",
                    info: "「一覧」はアイコンと名前を行に、「アイコンだけ」はアイコンと名前を格子に並べます。「サムネイル」は画面収録の許可が必要で、撮れないウインドウはアイコンと名前で表示します。",
                    selection: Binding(
                        get: { stage.windowSwitcherSettings.appearance },
                        set: { stage.setWindowSwitcherAppearance($0, thumbnails: thumbnails) }
                    )
                )
                OptionPicker(
                    "大きさ",
                    info: "アイコン、一覧の行、サムネイルの大きさです。ウィンドウスイッチャーの右上でも変えられます。ウインドウバーの大きさには影響しません。",
                    selection: $stage.windowSwitcherSettings.displaySize,
                    segmented: true
                )
                OptionPicker(
                    "確定方法",
                    info: "ショートカットで開いたとき、修飾キー（⌥Tab の ⌥ など）を離して確定するか、Enter やクリックを待つかを選びます。ウィンドウスイッチャーの右上でも変えられます。ウインドウバーのボタンから開いたときは、常に Enter やクリックで確定します。",
                    selection: $stage.windowSwitcherSettings.confirmation
                )
                if stage.windowSwitcherSettings.appearance == .thumbnails, !thumbnails.hasPermission {
                    NoticeRow(
                        text: "画面収録の許可がない間は、\(WindowSwitcherSettings.title)をアイコンだけで表示します。",
                        button: "画面収録を開く",
                        action: ThumbnailStore.openSettings
                    )
                }
            }
        }
        .onAppear { checkEdgeConflict() }
        .onChange(of: stage.stripSettings.edge) { checkEdgeConflict() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // 画面収録の許可・Dock とメニューバーの設定を、システム設定で変えて戻ってきたときに読み直す
            // （撮り直しは「一般」のタブが行うので、ここでは許可を問い合わせるだけ）
            thumbnails.refreshPermission()
            checkEdgeConflict()
        }
    }

    private func checkEdgeConflict() {
        edgeConflict = SystemBars.conflict(for: stage.stripSettings.edge)
    }

}
