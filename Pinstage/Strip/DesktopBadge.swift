import SwiftUI

// デスクトップの印（ウインドウバーの行と、ウインドウスイッチャーで同じものを使う）

/// デスクトップの短い印（絵と短い名前。名前を押しのけないように短くする。名前がなければ絵だけ）
struct DesktopBadge: View {
    private let symbol: String
    private let label: String?
    /// 文字の大きさ（ウインドウバーの行は 9pt。切り替え画面の一覧は少し大きく）
    private let fontSize: CGFloat

    /// ほかのデスクトップのウインドウの印の絵（四角が 2 つ重なった形。番号を添える）
    private static let otherDesktopSymbolName = "rectangle.on.rectangle"
    /// すべてのデスクトップに割り当てたウインドウの印の絵（デスクトップが重なった形）
    private static let allDesktopsSymbolName = "rectangle.stack"
    static let allDesktopsDescription = "すべてのデスクトップに割り当てたウインドウ"

    static func allDesktops(_ label: String? = "すべて", fontSize: CGFloat = 9) -> Self {
        Self(symbol: allDesktopsSymbolName, label: label, fontSize: fontSize)
    }

    static func otherDesktop(_ label: String, fontSize: CGFloat = 9) -> Self {
        Self(symbol: otherDesktopSymbolName, label: label, fontSize: fontSize)
    }

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: symbol)
            if let label { Text(label) }
        }
        .font(.system(size: fontSize, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 4)
        .padding(.vertical, 1)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }

    /// アプリ側のバッジと重ならないよう、アイコンの右下に添える印。
    static func allDesktopsIcon(iconSize: CGFloat) -> some View {
        let diameter = max(11, (iconSize * 0.45).rounded())
        return Image(systemName: allDesktopsSymbolName)
            .font(.system(size: diameter * 0.6, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: diameter, height: diameter)
            .background(Circle().fill(.regularMaterial))
            // アイコンの下に出るウインドウ名には重ねない。
            .offset(x: diameter * 0.35, y: diameter * 0.12)
            .help(allDesktopsDescription)
    }
}
