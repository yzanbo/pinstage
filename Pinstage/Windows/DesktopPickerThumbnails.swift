import AppKit

/// パネルの寿命に合わせて、見えているカードの足りないサムネイルだけを撮る。
final class DesktopPickerThumbnails {
    private let thumbnails: ThumbnailStore
    private var visibleRows: [DesktopPickerRowID: WindowItem] = [:]
    private var attempted: Set<AXUIElement> = []
    private var task: Task<Void, Never>?
    private var isOpen = true

    init(thumbnails: ThumbnailStore) {
        self.thumbnails = thumbnails
    }

    func setVisible(_ row: DesktopPickerRowID, window: WindowItem, _ visible: Bool) {
        guard isOpen else { return }
        visibleRows[row] = visible ? window : nil
        schedule()
    }

    func finish() {
        isOpen = false
        task?.cancel()
        task = nil
        visibleRows.removeAll()
    }

    private var pending: [WindowItem] {
        var seen = attempted
        return visibleRows.values.filter { item in
            !item.isMinimized && thumbnails.images[item.id] == nil && seen.insert(item.id).inserted
        }
    }

    private func schedule() {
        guard isOpen, task == nil, thumbnails.hasPermission, !pending.isEmpty else { return }
        task = Task { [weak self] in
            // 最初の描画とスクロールを待たせない。続けて見えたカードをまとめて撮る。
            try? await Task.sleep(for: .milliseconds(70))
            guard let self, !Task.isCancelled, isOpen else { return }
            let batch = Array(pending.prefix(12))
            if !batch.isEmpty {
                let processed = await thumbnails.captureForSwitcher(batch) { id in
                    self.visibleRows.values.contains { $0.id == id }
                }
                guard !Task.isCancelled else { return }
                attempted.formUnion(processed)
            }
            task = nil
            schedule()
        }
    }
}
