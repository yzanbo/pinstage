import PinstageCore
import SwiftUI

// ストリップの見た目の共通の部品（大きさ・色・ポインタを乗せたときの見え方をそろえる）

/// ストリップの見た目の決まり
enum StripStyle {
    /// 行・ボタンの角の丸み
    static let cornerRadius: CGFloat = 8
    /// 欄（ウインドウ・グループ・ステージ）どうしの間
    static let sectionSpacing: CGFloat = 14
    /// 行の地の色（ふだん・ポインタを乗せたとき）
    static let rowFill = Color.primary.opacity(0.045)
    static let rowHoverFill = Color.primary.opacity(0.09)
    /// ステージに出しているものの地の色
    static let selectedFill = Color.accentColor.opacity(0.16)
}

/// 小さなアイコンのボタンの中身（大きさをそろえ、ポインタを乗せたら背景を出す。isActive なら色を付ける）
struct StripIconLabel: View {
    let systemName: String
    var isActive = false
    @State private var isHovering = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isActive ? Color.accentColor : .secondary)
            .frame(width: 26, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovering ? Color.primary.opacity(0.1) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
    }
}

/// 欄の見出し（名前と数）
struct SectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
            if let count, count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 2)
    }
}

extension View {
    /// メニューを、ボタンと同じ見た目で出す（枠と ▾ を出さない。中身のラベルがそのまま見える）
    func stripMenuButton() -> some View {
        menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
    }

    /// 欄の形（検索の欄・並べ方の欄）の地。ポインタを乗せたら少し濃くする
    func stripPill(isHovering: Bool) -> some View {
        padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.1 : 0.06))
            )
            .contentShape(Rectangle())
    }
}

/// ストリップのいちばん上の帯（検索・見た目・ピン）
struct StripToolbar: View {
    let stage: StageController
    let shortcuts: ShortcutCenter
    let actions: AppActions

    private var isIconOnly: Bool { stage.stripSettings.itemSize.isIconOnly }

    var body: some View {
        if isIconOnly {
            // 細い帯: アイコンを縦に並べる
            VStack(spacing: 2) {
                Button { actions.openSearch() } label: { StripIconLabel(systemName: "magnifyingglass") }
                    .buttonStyle(.plain)
                    .help("ウインドウ・グループを検索")
                StripLookButton(stage: stage)
                StripModeButton(stage: stage)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 2) {
                SearchField(shortcut: shortcuts.shortcut(for: .search)?.displayString, action: actions.openSearch)
                StripLookButton(stage: stage)
                StripModeButton(stage: stage)
            }
        }
    }
}

/// 検索の欄の形のボタン（押すと検索の欄を出す。幅が狭いときは虫めがねだけ）
private struct SearchField: View {
    let shortcut: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("検索")
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let shortcut {
                        Text(shortcut)
                            .font(.system(size: 10).monospaced())
                            .lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                    Text("検索").lineLimit(1)
                    Spacer(minLength: 0)
                }
                Image(systemName: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .stripPill(isHovering: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("ウインドウ・グループを検索")
    }
}

/// ストリップの見た目（細い帯・アイコンの並び・一覧・サムネイル）を選ぶボタン
struct StripLookButton: View {
    let stage: StageController

    private var look: StripItemSize { stage.stripSettings.itemSize }

    var body: some View {
        Menu {
            Picker("見た目", selection: Binding(get: { look }, set: { stage.stripSettings.itemSize = $0 })) {
                ForEach(StripItemSize.allCases) { size in
                    Label(size.title, systemImage: size.symbolName).tag(size)
                }
            }
            .pickerStyle(.inline)
        } label: {
            StripIconLabel(systemName: look.symbolName)
        }
        .stripMenuButton()
        .fixedSize()
        .help("見た目: \(look.title)")
    }
}

/// ストリップの出し方を切り替えるボタン（押すたびに「常に出す」と「自動で隠す」が入れ替わる）
struct StripModeButton: View {
    let stage: StageController

    private var mode: StripMode { stage.stripSettings.mode }

    var body: some View {
        Button {
            stage.stripSettings.mode = mode == .alwaysShown ? .autoHide : .alwaysShown
        } label: {
            StripIconLabel(systemName: mode == .alwaysShown ? "pin.fill" : "pin.slash", isActive: mode == .alwaysShown)
        }
        .buttonStyle(.plain)
        .help(mode == .alwaysShown
            ? "常に出しています。押すと、左に寄せたときだけ出します"
            : "左に寄せたときだけ出しています。押すと、常に出します")
    }
}

/// 強調するボタンの見た目（ストリップは前面のウインドウにならないので、標準の強調ボタンだと灰色になる。いつも色を付ける）
struct StripPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? Color.accentColor.opacity(configuration.isPressed ? 0.75 : 1) : Color.primary.opacity(0.08))
            )
            .contentShape(Rectangle())
    }
}
