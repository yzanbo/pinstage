import CoreGraphics
import Testing
@testable import PinstageCore

@Suite("ウインドウバーからのドラッグ")
struct StripDragGeometryTests {
    @Test("同じディスプレイでは少しはみ出しても並べ替え、境界の先では隣のディスプレイへの移動になる")
    func reorderToleranceDoesNotCrossDisplays() {
        let display = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let rightStrip = StripGeometry.shownFrame(in: display, edge: .right, thickness: 64)
        #expect(StripDragGeometry.isInReorderArea(
            pointer: CGPoint(x: 1525, y: 500), strip: rightStrip, display: display, horizontal: false, tolerance: 24
        ))
        #expect(!StripDragGeometry.isInReorderArea(
            pointer: CGPoint(x: 1605, y: 500), strip: rightStrip, display: display, horizontal: false, tolerance: 24
        ))

        let topStrip = StripGeometry.shownFrame(in: display, edge: .top, thickness: 64)
        #expect(StripDragGeometry.isInReorderArea(
            pointer: CGPoint(x: 800, y: 925), strip: topStrip, display: display, horizontal: true, tolerance: 24
        ))
        #expect(!StripDragGeometry.isInReorderArea(
            pointer: CGPoint(x: 800, y: 1005), strip: topStrip, display: display, horizontal: true, tolerance: 24
        ))
    }

    @Test("見本はポインタの右下に出て、移動量についていく")
    func followsPointer() {
        let visible = CGRect(x: 0, y: 30, width: 1000, height: 600)
        let size = CGSize(width: 210, height: 44)
        let first = StripDragGeometry.previewFrame(pointer: CGPoint(x: 100, y: 250), size: size, in: visible)
        let next = StripDragGeometry.previewFrame(pointer: CGPoint(x: 130, y: 230), size: size, in: visible)
        #expect(first == CGRect(x: 114, y: 192, width: 210, height: 44))
        #expect(next == first.offsetBy(dx: 30, dy: -20))
    }

    @Test("左隣など原点が負のディスプレイでも、端に来たら見本を反対側に回して画面内に収める")
    func flipsAtDisplayEdges() {
        let visible = CGRect(x: -800, y: 100, width: 800, height: 600)
        let pointer = CGPoint(x: -8, y: 109)
        let frame = StripDragGeometry.previewFrame(pointer: pointer, size: CGSize(width: 210, height: 44), in: visible)
        #expect(frame == CGRect(x: -232, y: 123, width: 210, height: 44))
        #expect(visible.contains(frame))
        #expect(!frame.contains(pointer))
    }
}
