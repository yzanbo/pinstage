import AppKit
import Observation
import PinstageCore
import ScreenCaptureKit

/// ストリップとウインドウスイッチャーに出すサムネイル
///
/// ScreenCaptureKit でウインドウだけを撮る（ほかのウインドウに隠れていても、そのウインドウの中身が撮れる）。
/// 画面収録の許可が要る。ストリップは少しずつ撮り直し、切り替え画面では見えているカードの足りない画像だけを撮る。
@Observable
final class ThumbnailStore {
    /// ウインドウごとのサムネイル
    private(set) var images: [AXUIElement: NSImage] = [:]
    /// 画面収録の許可があるか
    private(set) var hasPermission = CGPreflightScreenCaptureAccess()

    /// 撮り直す間隔（秒）
    static let interval: TimeInterval = 3
    /// サムネイルの横幅（ピクセル。ストリップの幅の 2 倍あれば、Retina でもぼやけない）
    static let pixelWidth: CGFloat = 480

    /// 撮るウインドウ（ストリップに並べているもの）。撮らないときは空
    @ObservationIgnored var targets: () -> [WindowItem] = { [] }
    /// いま開いているウインドウ（閉じたウインドウのサムネイルを捨てるのに使う）
    @ObservationIgnored var existing: () -> Set<AXUIElement> = { [] }
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isCapturing = false

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureNow() }
        }
    }

    func stop() {
        timer?.invalidate()
    }

    /// 画面収録の許可を求める（初めてなら、macOS の確かめるダイアログが出る）
    func requestPermission() {
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    /// システム設定の「画面収録」を開く
    static func openSettings() {
        NSWorkspace.shared.open(urlString: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    /// 閉じたウインドウのサムネイルを捨てる
    func prune(keeping ids: Set<AXUIElement>) {
        images = images.filter { ids.contains($0.key) }
    }

    /// 画面収録の許可を問い合わせ直す（システム設定で変えて戻ってきたとき）
    func refreshPermission() {
        hasPermission = CGPreflightScreenCaptureAccess()
    }

    /// 開くときは許可を確認するだけ。サムネイルに設定を変更したときだけ、必要なら許可を求める。
    func windowSwitcherAppearance(
        _ preferred: WindowSwitcherSettings.Appearance, requestsPermission: Bool = false
    ) -> WindowSwitcherSettings.Appearance {
        if preferred == .thumbnails {
            refreshPermission()
            if requestsPermission, !hasPermission { requestPermission() }
        }
        return preferred.displayed(hasScreenCapturePermission: hasPermission)
    }

    /// いま撮り直す
    func captureNow() {
        refreshPermission()
        let items = targets()
        DesktopTrace.log("サムネイル", "許可=\(hasPermission) 撮るウインドウ=\(items.count)")
        guard hasPermission, !items.isEmpty, !isCapturing else { return }
        isCapturing = true
        Task {
            _ = await capture(items)
            isCapturing = false
        }
    }

    /// 切り替え画面が開いている間に、見えているカードだけ撮る。試したウインドウを返す。
    func captureForSwitcher(_ items: [WindowItem], isVisible: (AXUIElement) -> Bool) async -> Set<AXUIElement> {
        guard hasPermission else { return Set(items.map(\.id)) }
        return await capture(items) { id in isVisible(id) && self.images[id] == nil }
    }

    private func capture(
        _ items: [WindowItem], shouldCapture: (AXUIElement) -> Bool = { _ in true }
    ) async -> Set<AXUIElement> {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        } catch {
            guard !Task.isCancelled else { return [] }
            DesktopTrace.log("サムネイルの失敗", "ウインドウの一覧を読めない: \(error.localizedDescription)")
            return Set(items.map(\.id).filter(shouldCapture))
        }
        guard !Task.isCancelled else { return [] }
        let windows = content.windows.filter { $0.windowLayer == 0 && $0.owningApplication != nil }
        let candidates = windows.map {
            CaptureWindowMatcher.Window(pid: $0.owningApplication?.processID ?? 0, title: $0.title ?? "", frame: $0.frame)
        }
        // ウインドウの番号が分かるものは番号で、分からないものはアプリ・名前・位置で照らし合わせる
        let byNumber = Dictionary(windows.enumerated().map { ($1.windowID, $0) }, uniquingKeysWith: { first, _ in first })
        let fallback = items.indices.filter { items[$0].windowID == nil }
        var matches: [Int?] = items.map { item in item.windowID.flatMap { byNumber[$0] } }
        if !fallback.isEmpty {
            let targets = fallback.map { items[$0].matchKey(frame: AXWindow.frame(of: items[$0].id)) }
            for (index, match) in zip(fallback, CaptureWindowMatcher.match(targets, candidates: candidates)) {
                matches[index] = match
            }
        }
        // 閉じたウインドウのサムネイルは捨てる。いま撮らないウインドウ（ほかのデスクトップのものなど）は、前に撮ったものを残す
        prune(keeping: existing().union(items.map(\.id)))
        var captured = 0
        var attempted: Set<AXUIElement> = []
        for (item, match) in zip(items, matches) {
            guard !Task.isCancelled else { return attempted }
            guard shouldCapture(item.id) else { continue }
            attempted.insert(item.id)
            // しまってあるウインドウは撮れないので、前に撮ったものを残す
            guard let match, !item.isMinimized else { continue }
            let image = await captureImage(of: windows[match])
            guard !Task.isCancelled else { return attempted }
            if let image {
                images[item.id] = image
                captured += 1
            }
        }
        // 撮れないときに、許可・照らし合わせ・撮影のどこで止まったかを確かめるための記録
        DesktopTrace.log("サムネイルの結果", "照らし合わせた=\(matches.compactMap { $0 }.count) 撮れた=\(captured)")
        return attempted
    }

    private func captureImage(of window: SCWindow) async -> NSImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let rect = filter.contentRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let config = SCStreamConfiguration()
        let scale = min(1, Self.pixelWidth / rect.width) * CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(rect.width * scale))
        config.height = max(1, Int(rect.height * scale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        do {
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: rect.size)
        } catch {
            DesktopTrace.log("サムネイルの失敗", "撮れない: \(error.localizedDescription)")
            return nil
        }
    }
}
