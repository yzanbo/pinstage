import AppKit
import PinstageCore
import SwiftUI

/// 「ストリップ」のタブ: 置き方・見た目・並べるウインドウ
struct StripSettingsView: View {
    let stage: StageController
    let thumbnails: ThumbnailStore
    /// ストリップと同じ辺で重なる、自動で隠れる Dock・メニューバー（タブを開いたとき・戻ってきたとき・位置を変えたときに読み直す）
    @State private var edgeConflict: StripEdgeConflict?

    var body: some View {
        SettingsPane {
            Section("置き方") {
                OptionPicker(
                    "出し方",
                    info: "「常に出す」はいつも画面の端に出し、ステージはストリップを除いた残りを使います。「自動で隠す」はポインタを、ストリップのある端に寄せたときだけ出し、ステージは画面いっぱいを使います。",
                    selection: binding(\.mode),
                    segmented: true
                )
                // 「常に出す」のときだけ使うので、出し方のすぐ下に置く
                Toggle(isOn: binding(\.keepsWindowsOffStrip)) {
                    SettingTitle(
                        "ストリップの後ろにウインドウを入り込ませない",
                        info: "「常に出す」のときに、ウインドウを広げる（タイトルバーのダブルクリック・緑のボタン・「フィル」など）か動かして、ストリップの後ろに入り込んだら、ステージ（ストリップを除いた残り）に戻します。広げたウインドウはステージいっぱいに収め、もう一度ダブルクリックすると元の大きさに戻ります。ドラッグしている間は動かさず、離してから戻します。"
                    )
                }
                .disabled(stage.stripSettings.mode != .alwaysShown)
                OptionPicker(
                    "位置",
                    info: "ストリップを出す辺です。「左」「右」は縦長の帯で、ステージの側の縁をドラッグして幅を変えられます。「上」「下」は横長の帯で、ウインドウを横に並べます（高さは形式と大きさで決まります）。常に表示している Dock・メニューバーと同じ辺では、その内側に並びます。ストリップの見出しの、見た目のボタンでも切り替えられます。",
                    selection: binding(\.edge),
                    segmented: true
                )
                if let conflict = edgeConflict {
                    NoticeRow(
                        text: conflict.message,
                        button: conflict == .autoHidingDock ? "Dock の設定を開く" : "メニューバーの設定を開く",
                        action: conflict == .autoHidingDock ? SystemBars.openDockSettings : SystemBars.openMenuBarSettings
                    )
                }
                OptionPicker(
                    "出すディスプレイ",
                    info: "「すべてのディスプレイ」では、ディスプレイごとにストリップとステージを持ちます。ストリップを押したディスプレイに並べます。",
                    selection: binding(\.displays)
                )
            }

            Section("見た目") {
                OptionPicker(
                    "形式",
                    info: "ウインドウの並べ方です。「アイコンの並び」はアイコンだけを、幅に入るだけ並べます（名前はポインタを乗せると出ます。幅を狭めると 1 列になります）。「一覧」は、ブラウザの縦のタブのように、アイコンと名前を 1 行で並べます。「サムネイル」はウインドウの中身を映します（画面収録の許可が要ります。映した画像は Mac の中だけで使い、保存も送信もしません）。ストリップの見出しのボタンでも切り替えられます。",
                    selection: binding(\.itemSize)
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
                    info: "どの形式にもかかる大きさです。「一覧」では行の高さ・アイコン・文字（「小」はブラウザの縦のタブと同じくらい）、「サムネイル」では映す大きさのいちばん小さい値、「アイコンの並び」ではアイコンの大きさが変わります。アイコンの並びは、ステージの側の縁をドラッグして、アイコンが 1 列になる幅（細い帯）まで狭められます。アイコンの並びの幅は、一覧・サムネイルの幅とは別に覚えます。ストリップの見出しの、見た目のボタンでも切り替えられます。",
                    selection: binding(\.iconSize),
                    segmented: true
                )
                LabeledContent {
                    // 数を左、増やす・減らすボタンを右に（macOS の設定と同じ並び）
                    HStack(spacing: 6) {
                        Text("\(stage.stripSettings.visibleCount) 個")
                            .monospacedDigit()
                        Stepper("並べる数", value: binding(\.visibleCount), in: StripSettings.visibleCountRange)
                            .labelsHidden()
                    }
                } label: {
                    SettingTitle("並べる数", info: "これより多いウインドウは「ほかのウインドウ」にたたみます。新しく開いたウインドウが上に来ます。")
                }
            }

            Section("並べるウインドウ") {
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

    /// ストリップの設定の 1 項目とつなぐ
    private func binding<Value>(_ keyPath: WritableKeyPath<StripSettings, Value>) -> Binding<Value> {
        Binding(
            get: { stage.stripSettings[keyPath: keyPath] },
            set: { stage.stripSettings[keyPath: keyPath] = $0 }
        )
    }
}
