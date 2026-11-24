import SwiftUI

/// 設定のタブの共通の見た目
struct SettingsPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        // タブを切り替えても横幅が変わらないよう、どのタブも同じ幅にする（高さは中身に合わせる）
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// 項目の下に添える小さな説明
struct SettingsNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// 項目名と、その横の ⓘ（押すと説明が出る）。長い説明を並べず、画面を短く保つ
struct SettingTitle: View {
    let title: String
    let info: String?

    init(_ title: String, info: String? = nil) {
        self.title = title
        self.info = info
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            if let info {
                InfoButton(info)
            }
        }
    }
}

/// 押すと説明を吹き出しで出す ⓘ のボタン
struct InfoButton: View {
    let text: String
    @State private var isShown = false

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Button {
            isShown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.borderless)
        .help("説明を見る")
        .popover(isPresented: $isShown, arrowEdge: .bottom) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 300, alignment: .leading)
                .padding(14)
        }
    }
}

/// 設定の選択肢（名前を持ち、すべての値を並べられる）
protocol SettingsOption: CaseIterable, Hashable {
    var title: String { get }
}

/// 選択肢をすべて並べた Picker
struct OptionPicker<Option: SettingsOption>: View where Option.AllCases: RandomAccessCollection {
    let title: String
    let info: String?
    @Binding var selection: Option

    init(_ title: String, info: String? = nil, selection: Binding<Option>) {
        self.title = title
        self.info = info
        _selection = selection
    }

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                Text(option.title).tag(option)
            }
        } label: {
            SettingTitle(title, info: info)
        }
    }
}
