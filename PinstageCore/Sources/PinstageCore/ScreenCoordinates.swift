import CoreGraphics

/// 2 つの座標の向きを変換する
///
/// - macOS の画面座標（AppKit）: いちばん目の画面（メニューバーのある画面）の左下が原点。上へ行くほど y が大きい
/// - アクセシビリティの API の座標: いちばん目の画面の左上が原点。下へ行くほど y が大きい
///
/// どちらも x の向きは同じなので、y だけをいちばん目の画面の高さで折り返す。
public enum ScreenCoordinates {
    /// AppKit の枠を、アクセシビリティの API の枠にする（向きを折り返すだけなので、逆向きも同じ計算になる）
    public static func toAccessibility(_ rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
