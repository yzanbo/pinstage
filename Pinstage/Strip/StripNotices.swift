import SwiftUI

/// ストリップの上に出す案内（オレンジの箱。アイコンだけのときは、押すとシステム設定を開くボタン）
struct StripNotice: View {
    /// アイコンだけのストリップか
    let compact: Bool
    let symbol: String
    let title: String
    let message: String
    /// アイコンだけのときに、ポインタを乗せると出す説明
    let compactHelp: String
    let openSettings: () -> Void
    /// × で閉じたときにすること（nil なら × を出さない）
    var onDismiss: (() -> Void)?

    var body: some View {
        if compact {
            Button(action: openSettings) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .help(compactHelp)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                heading
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("システム設定を開く", action: openSettings)
                    .controlSize(.small)
            }
            .padding(8)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var heading: some View {
        let label = Label(title, systemImage: symbol)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.orange)
        if let onDismiss {
            HStack(alignment: .firstTextBaseline) {
                label
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("この案内を閉じる（Pinstage を開き直すと、また出ます）")
            }
        } else {
            label
        }
    }
}

extension StripNotice {
    /// アクセシビリティの許可がないときの案内
    static func permission(compact: Bool) -> StripNotice {
        StripNotice(
            compact: compact,
            symbol: "exclamationmark.triangle.fill",
            title: "アクセシビリティの許可が必要です",
            message: "ほかのアプリのウインドウを動かすために使います。システム設定で Pinstage をオンにしてください。",
            compactHelp: "アクセシビリティの許可が必要です。押すとシステム設定を開きます",
            openSettings: AccessibilityPermission.openSettings
        )
    }

    /// macOS のステージマネージャがオンのときの案内（オンだと、並べたとおりにならない）
    static func stageManager(compact: Bool, onDismiss: @escaping () -> Void) -> StripNotice {
        StripNotice(
            compact: compact,
            symbol: "rectangle.stack.badge.minus",
            title: "ステージマネージャがオンです",
            message: "macOS のステージマネージャがウインドウの位置と大きさを抑えるので、Pinstage で並べたとおりになりません。コントロールセンターか、システム設定の「デスクトップと Dock」でオフにしてください。",
            compactHelp: "macOS のステージマネージャがオンです。オンのままだと、Pinstage で並べたとおりになりません。押すとシステム設定を開きます",
            openSettings: SystemStageManager.openSettings,
            onDismiss: onDismiss
        )
    }
}
