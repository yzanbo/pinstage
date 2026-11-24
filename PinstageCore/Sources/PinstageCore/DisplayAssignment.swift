import CoreGraphics

/// ウインドウが、どのディスプレイのものかを決める（ディスプレイごとのストリップに、そのディスプレイのウインドウを並べるため）
public enum DisplayAssignment {
    /// いちばん大きく重なっているディスプレイの番号。どこにも重なっていなければ、いちばん近いディスプレイ
    ///
    /// - Parameters:
    ///   - frame: ウインドウの枠
    ///   - displays: ディスプレイの枠（ウインドウの枠と同じ座標）
    public static func displayIndex(for frame: CGRect, displays: [CGRect]) -> Int? {
        guard !displays.isEmpty else { return nil }
        var best: (index: Int, area: CGFloat)?
        for (index, display) in displays.enumerated() {
            let overlap = display.intersection(frame)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if best == nil || area > best!.area { best = (index, area) }
        }
        if let best, best.area > 0 { return best.index }
        // どこにも重なっていない（画面の外に出したウインドウなど）ときは、真ん中がいちばん近いディスプレイ
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return displays.indices.min { distance(center, displays[$0]) < distance(center, displays[$1]) }
    }

    private static func distance(_ point: CGPoint, _ rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }
}
