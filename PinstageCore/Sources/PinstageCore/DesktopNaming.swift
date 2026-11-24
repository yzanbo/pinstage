/// デスクトップの名前（「デスクトップ 3」・「フルスクリーン」）
///
/// 番号を持っておき、名前と短い印はそこから作る（名前の文字から番号を読み戻さない）
public struct DesktopName: Hashable, Sendable {
    /// ディスプレイごとに左から数えた番号（1 から。フルスクリーンのアプリのデスクトップは nil）
    public let number: Int?

    public init(number: Int?) {
        self.number = number
    }

    /// 名前（「デスクトップ 3」。フルスクリーンのものは「フルスクリーン」）
    public var title: String {
        number.map { "デスクトップ \($0)" } ?? "フルスクリーン"
    }

    /// ストリップの行に添える短い印（「3」。フルスクリーンのものは「フルスクリーン」）
    public var shortLabel: String {
        number.map(String.init) ?? "フルスクリーン"
    }
}

/// デスクトップに名前を付ける計算
public enum DesktopNaming {
    /// 1 つのデスクトップ（名前を付けるのに使うところだけ）
    public struct Space: Equatable, Sendable {
        public let id: UInt64
        /// フルスクリーンのアプリのデスクトップか
        public let isFullScreen: Bool

        public init(id: UInt64, isFullScreen: Bool) {
            self.id = id
            self.isFullScreen = isFullScreen
        }
    }

    /// デスクトップごとの名前
    /// - Parameter displays: ディスプレイごとの、デスクトップ（左から順）
    /// - Returns: ディスプレイごとに左から「デスクトップ 1」「デスクトップ 2」…（フルスクリーンのものは数えない）
    public static func names(displays: [[Space]]) -> [UInt64: DesktopName] {
        var names: [UInt64: DesktopName] = [:]
        for spaces in displays {
            var number = 0
            for space in spaces {
                if space.isFullScreen {
                    names[space.id] = DesktopName(number: nil)
                } else {
                    number += 1
                    names[space.id] = DesktopName(number: number)
                }
            }
        }
        return names
    }
}
