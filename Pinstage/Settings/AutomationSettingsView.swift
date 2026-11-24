import AppKit
import PinstageCore
import SwiftUI

/// 「自動化」のタブ: 「ショートカット」アプリでの使い方と、操作の URL（グループごとの URL をコピーできる）
struct AutomationSettingsView: View {
    let stage: StageController

    /// グループ以外の操作の URL
    private static let commandURLs: [(title: String, url: String)] = [
        ("ストリップを切り替える", "pinstage://strip/toggle"),
        ("ストリップを出す", "pinstage://strip/show"),
        ("ストリップを隠す", "pinstage://strip/hide"),
        ("検索の欄を出す", "pinstage://search"),
        ("次のグループを呼び出す", "pinstage://group/next"),
        ("前のグループを呼び出す", "pinstage://group/previous"),
        ("ステージをグループとして保存", "pinstage://save?name=名前"),
    ]

    var body: some View {
        SettingsPane {
            Section {
                SettingsNote("「ショートカット」アプリで、Pinstage の操作（グループを呼び出す・ストリップを出す／隠す・ステージをグループとして保存・検索）を使えます。「オートメーション」と組み合わせると、時刻・アプリの起動・ディスプレイの接続・集中モードなどをきっかけに、自動で動かせます。Siri・Spotlight からも呼び出せます。")
                HStack {
                    Spacer()
                    Button("「ショートカット」アプリを開く") {
                        NSWorkspace.shared.open(urlString: "shortcuts://")
                    }
                }
            } header: {
                SettingTitle("「ショートカット」アプリ", info: "例: オートメーションで「Xcode を開いたとき」を選び、Pinstage の「グループを呼び出す」で「開発」を選ぶと、Xcode を開くたびに「開発」グループが並びます。")
            }

            Section {
                ForEach(stage.library.groups) { group in
                    URLRow(title: group.name, url: PinstageURL.groupURL(name: group.name)?.absoluteString ?? "")
                }
                if stage.library.groups.isEmpty {
                    SettingsNote("グループを保存すると、ここにグループを呼び出す URL が並びます。")
                }
            } header: {
                SettingTitle("グループを呼び出す URL", info: "Stream Deck・Alfred・Raycast・ターミナルの open コマンドなどから開くと、そのグループを呼び出します。グループの名前を変えたら、URL も変わります。")
            }

            Section("そのほかの操作の URL") {
                ForEach(Self.commandURLs, id: \.url) { command in
                    URLRow(title: command.title, url: command.url)
                }
            }
        }
    }
}

/// URL の 1 行（コピーのボタンつき）
private struct URLRow: View {
    let title: String
    let url: String
    @State private var copied = false

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                // URL に使えない文字（日本語など）は、そのまま読める形で見せる
                Text(url.removingPercentEncoding ?? url)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("URL をコピー")
            }
        } label: {
            Text(title)
        }
    }
}
