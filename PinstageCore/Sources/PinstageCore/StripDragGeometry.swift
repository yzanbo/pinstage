import CoreGraphics

/// ドラッグ中の判定と、ポインタについて動く見本の位置。座標は AppKit と同じ（左下が原点）。
public enum StripDragGeometry {
    /// 並べ替えのはみ出しを許す。ただし隣のディスプレイまで並べ替えの範囲にはしない。
    public static func isInReorderArea(
        pointer: CGPoint, strip: CGRect, display: CGRect, horizontal: Bool, tolerance: CGFloat
    ) -> Bool {
        guard display.contains(pointer) else { return false }
        let area = horizontal ? strip.insetBy(dx: 0, dy: -tolerance) : strip.insetBy(dx: -tolerance, dy: 0)
        return area.contains(pointer)
    }

    /// ポインタの右下に出す。端で収まらないときは反対側に回し、ディスプレイの中に収める。
    public static func previewFrame(pointer: CGPoint, size: CGSize, in visible: CGRect) -> CGRect {
        let gap: CGFloat = 14
        let width = min(size.width, visible.width)
        let height = min(size.height, visible.height)
        let x = pointer.x + gap + width <= visible.maxX ? pointer.x + gap : pointer.x - gap - width
        let y = pointer.y - gap - height >= visible.minY ? pointer.y - gap - height : pointer.y + gap
        return CGRect(
            x: min(max(x, visible.minX), visible.maxX - width),
            y: min(max(y, visible.minY), visible.maxY - height),
            width: width, height: height
        )
    }
}
