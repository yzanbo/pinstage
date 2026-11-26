import AppKit

/// アプリのアイコン。アイコンを出すところは、すべてここから使う
///
/// 絵は scripts/make-app-icon.swift で描いて、make icon で Assets.xcassets に書き出す。
/// - 色付きのアイコン（AppIcon）: Finder・Dock・ログイン項目など
/// - 1 色の印（AppSymbol）: 同じ絵（ストリップ・2 枚のウインドウ・ピン）を 1 色にしたもの。メニューバー
///   新しい版があるときは、右下に下向きの矢印の丸を入れたもの（symbolWithUpdateBadge）をメニューバーに出す
enum AppIcon {
    /// 色付きのアイコン。アプリの中のアイコンのファイル（AppIcon.icns）を直接読む。
    /// macOS が覚えているアイコンは、アイコンを入れる前の仮のもののことがあるため（Pinshot・Pinshelf と同じ）
    static let image: NSImage = Bundle.main.image(forResource: "AppIcon") ?? NSApp.applicationIconImage

    /// アプリのアイコン（Dock・確認の画面などに出るもの）を、作ったアイコンにする。
    ///
    /// メニューバーだけに常駐している間に設定しても、Dock に出たときには使われず、macOS が覚えているアイコン
    /// （アイコンを入れる前の仮のものなど）で出ることがある。そのため、起動したときと Dock に出すたびに呼ぶ。
    /// 同じものを設定し直しても反映されないことがあるので、毎回写しを渡す
    static func applyToApp() {
        NSApp.applicationIconImage = image.copy() as? NSImage ?? image
    }

    /// 1 色の印の、アセットカタログでの名前
    static let symbolName = "AppSymbol"

    /// 1 色の印（AppKit。メニューバー用）。テンプレート画像なので、メニューバーの明るさや押したときに合わせて、macOS が色を付ける
    static func symbol(accessibilityDescription: String) -> NSImage? {
        guard let image = NSImage(named: symbolName)?.copy() as? NSImage else { return nil }
        return template(image, accessibilityDescription: accessibilityDescription)
    }

    /// 新しい版があるときの 1 色の印（メニューバー用）
    ///
    /// 1 色の印の右下を丸く切り抜き、下向きの矢印を抜いた丸を置く（Ollama と同じ考え方。Pinshelf と同じ形）。
    /// メニューバーのアプリは、色を付けずに 1 色のまま知らせるのが一般的なので、テンプレート画像のままにする
    /// （色付きの点は、マイク・カメラの使用中の印と紛れやすい）。見慣れた形が欠けるので、小さな点より気づきやすい
    static func symbolWithUpdateBadge(accessibilityDescription: String) -> NSImage? {
        guard let base = NSImage(named: symbolName)?.copy() as? NSImage else { return nil }
        let image = NSImage(size: base.size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            base.draw(in: rect)
            drawUpdateBadge(in: context, rect: rect)
            return true
        }
        return template(image, accessibilityDescription: accessibilityDescription)
    }

    /// テンプレート画像にして、読み上げ用の説明を付ける
    private static func template(_ image: NSImage, accessibilityDescription: String) -> NSImage {
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// 右下の丸と矢印を描く（大きさは 18pt の印のときの値。印の大きさに合わせて伸び縮みする。Pinshelf と同じ値）
    ///
    /// 丸は直径 10pt。切り抜くのは右のウインドウの下半分（と、左のウインドウの右下の角）で、左のストリップ・左のウインドウ・
    /// 右のウインドウの上のピンは残るので、Pinstage の形は分かる（描いて確かめた）
    private static func drawUpdateBadge(in context: CGContext, rect: CGRect) {
        let unit = rect.width / 18
        /// 丸の中心の、右下の角からの距離
        let inset: CGFloat = 5.0
        /// 切り抜く半径（丸の半径より 1.1 大きくして、印の本体とのあいだにすき間を作る）
        let cutoutRadius: CGFloat = 6.1
        /// 丸の半径
        let dotRadius: CGFloat = 5.0
        /// 矢印の倍率（下の矢印の座標と線の太さに掛ける）
        let arrow: CGFloat = 1.2
        let center = CGPoint(x: rect.maxX - inset * unit, y: rect.minY + inset * unit)
        func circle(radius: CGFloat) -> CGRect {
            CGRect(x: center.x - radius * unit, y: center.y - radius * unit, width: radius * 2 * unit, height: radius * 2 * unit)
        }
        func point(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: center.x + dx * arrow * unit, y: center.y + dy * arrow * unit)
        }
        // 丸の周りを切り抜く
        context.setBlendMode(.clear)
        context.fillEllipse(in: circle(radius: cutoutRadius))
        // 丸（テンプレート画像なので、色は何でもよい。macOS が形だけを使って色を付ける）
        context.setBlendMode(.normal)
        context.setFillColor(NSColor.black.cgColor)
        context.fillEllipse(in: circle(radius: dotRadius))
        // 下向きの矢印を、丸から抜く
        context.setBlendMode(.clear)
        context.setLineWidth(1.4 * arrow * unit)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let tip = point(0, -2.0)
        context.move(to: point(0, 2.3))
        context.addLine(to: tip)
        context.move(to: point(-1.9, -0.1))
        context.addLine(to: tip)
        context.addLine(to: point(1.9, -0.1))
        context.strokePath()
    }
}
