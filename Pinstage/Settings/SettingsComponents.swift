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
    /// 選択肢をボタンの形で横に並べるか（選択肢が少なく、短いとき。開かずに一目で選べる）。false ならメニュー
    let segmented: Bool

    init(_ title: String, info: String? = nil, selection: Binding<Option>, segmented: Bool = false) {
        self.title = title
        self.info = info
        _selection = selection
        self.segmented = segmented
    }

    var body: some View {
        if segmented {
            // 右端を、ほかの行のスイッチ・メニューの右端にそろえる（幅は選択肢に合わせる）
            LabeledContent {
                Picker(title, selection: $selection) { options }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
            } label: {
                SettingTitle(title, info: info)
            }
        } else {
            Picker(selection: $selection) {
                options
            } label: {
                SettingTitle(title, info: info)
            }
        }
    }

    private var options: some View {
        ForEach(Array(Option.allCases), id: \.self) { option in
            Text(option.title).tag(option)
        }
    }
}

/// 案内の 1 行（注意の印つきの説明と、その下の右に、システム設定を開くボタン）。
/// 説明が長くても細く折り返さないよう、ボタンは説明の下に置く
struct NoticeRow: View {
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(text, systemImage: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(button, action: action)
            }
        }
    }
}

/// 画面収録の許可がない間の案内（サムネイルの代わりにアイコンで表示していること。システム設定を開くボタン付き）
struct ScreenCapturePermissionNotice: View {
    let text: String

    var body: some View {
        NoticeRow(text: text, button: "画面収録を開く", action: ThumbnailStore.openSettings)
    }
}

extension View {
    /// システム設定で画面収録の許可を変えて戻ってきたときに、許可を問い合わせ直す（撮り直しは「一般」のタブが行う）
    func refreshesScreenCapturePermission(_ thumbnails: ThumbnailStore, then action: @escaping () -> Void = {}) -> some View {
        onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            thumbnails.refreshPermission()
            action()
        }
    }
}
