import CoreGraphics

/// ストリップに並べる「ふつうのウインドウ」かを決める
///
/// アクセシビリティの API の種類（subrole）が「ふつうのウインドウ」（AXStandardWindow）のものは並べる。
/// 枠を自前で描くウインドウ（Electron の frame: false など）は、見た目はふつうのウインドウでも、種類が「不明」（AXUnknown）や
/// 種類なしになることがあるので、画面のふつうの高さにある・大きさのあるウインドウなら並べる。
/// パネル・ダイアログ・ツールチップ・メニューは並べない。
public enum WindowEligibility {
    /// 種類だけを見た結果
    public enum Verdict: Equatable, Sendable {
        /// ふつうのウインドウ。並べる
        case accept
        /// 種類からは決められない。高さ（レベル）と大きさを確かめる
        case needsGeometry
        /// パネル・ダイアログなど。並べない
        case reject
    }

    /// アクセシビリティの API の、ウインドウの種類の名前（ApplicationServices の kAXStandardWindowSubrole・kAXUnknownSubrole と同じ）
    static let standardSubrole = "AXStandardWindow"
    static let unknownSubrole = "AXUnknown"

    /// これより小さいものは、ふつうのウインドウではないとみなす（pt。タブのバー・メニュー・ツールチップなどの部品）
    public static let minimumSize: CGFloat = 100

    public static func verdict(subrole: String?) -> Verdict {
        switch subrole {
        case standardSubrole: .accept
        case nil, unknownSubrole: .needsGeometry
        default: .reject
        }
    }

    /// ウインドウと言える大きさがあるか
    public static func hasWindowSize(_ size: CGSize) -> Bool {
        size.width >= minimumSize && size.height >= minimumSize
    }

    /// ふつうの高さ（レベル 0。ほかのウインドウの上に浮くパネルではない）にある、大きさのあるウインドウか
    public static func isNormalWindow(layer: Int, size: CGSize) -> Bool {
        layer == 0 && hasWindowSize(size)
    }
}
