import AppKit
import ApplicationServices

/// ほかのデスクトップのウインドウを見つける（非公開の API）
///
/// アクセシビリティの API のウインドウの一覧は、多くのアプリで、いま見ているデスクトップのウインドウしか返さない。
/// そこで、ウインドウの部品を番号から作り（_AXUIElementCreateWithRemoteToken）、
/// 探しているウインドウの番号のものを見つける。総当たりに近いので、メインの処理の外で、見つけていないウインドウがあるアプリだけ探す。
nonisolated enum RemoteWindows {
    /// 見つけたウインドウの部品（部品は、メインの処理の外で作って渡すだけ）
    struct Found: @unchecked Sendable {
        let element: AXUIElement
        let windowID: CGWindowID
    }

    private typealias CreateWithTokenFunction = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    private static let createWithToken: CreateWithTokenFunction? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementCreateWithRemoteToken")
        .map { unsafeBitCast($0, to: CreateWithTokenFunction.self) }
    private static let getWindow: GetWindowFunction? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow")
        .map { unsafeBitCast($0, to: GetWindowFunction.self) }

    /// 探せるか（関数がそろっているか）
    static var isAvailable: Bool { createWithToken != nil && getWindow != nil }

    /// 部品の番号を、いくつまで試すか（ふつうのアプリのウインドウは、小さな番号に収まる）
    private static let maximumElementID: UInt64 = 2000
    /// 1 つのアプリを探すのにかける時間の上限（秒）
    private static let timeLimit: TimeInterval = 0.3

    /// そのアプリの、wanted の番号のウインドウ（ふつうのウインドウだけ）を探す
    static func find(pid: pid_t, wanted: Set<CGWindowID>) -> [Found] {
        guard let createWithToken, let getWindow, !wanted.isEmpty else { return [] }
        var remaining = wanted
        var found: [Found] = []
        let deadline = Date().addingTimeInterval(timeLimit)
        // 部品の番号の作り方: アプリの番号（4 バイト）・0（4 バイト）・"coco"（4 バイト）・部品の番号（8 バイト）
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: UInt32(0x636f_636f)) { Data($0) })
        for elementID in 0..<maximumElementID {
            if remaining.isEmpty || Date() > deadline { break }
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            guard let element = createWithToken(token as CFData)?.takeRetainedValue() else { continue }
            var windowID: CGWindowID = 0
            guard getWindow(element, &windowID) == .success, remaining.contains(windowID) else { continue }
            var subrole: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
            guard (subrole as? String) == kAXStandardWindowSubrole else { continue }
            remaining.remove(windowID)
            found.append(Found(element: element, windowID: windowID))
        }
        return found
    }
}

extension RemoteWindows {
    /// まだ部品を持っていない、どこかのデスクトップにあるふつうのウインドウ（アプリごと）。
    /// 画面に出ているウインドウの一覧（画面の外のものも含む）から、ふつうのアプリの、大きさのあるウインドウのうち、
    /// どこかのデスクトップにあるもの（隠しているだけのものは、どのデスクトップにもない）を選ぶ
    @MainActor
    static func missingWindows(known: Set<CGWindowID>) -> [pid_t: Set<CGWindowID>] {
        let apps = Set(NSWorkspace.shared.runningApplications.filter(\.hasManageableWindows).map(\.processIdentifier))
        let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [pid_t: Set<CGWindowID>] = [:]
        for info in list {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, apps.contains(pid),
                  let number = info[kCGWindowNumber as String] as? Int,
                  !known.contains(CGWindowID(number)),
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
                  bounds.width >= minimumSize, bounds.height >= minimumSize,
                  !SkyLight.spaces(ofWindow: CGWindowID(number)).isEmpty
            else { continue }
            result[pid, default: []].insert(CGWindowID(number))
        }
        return result
    }

    /// これより小さいものは、ふつうのウインドウではないとみなす（タブのバー・メニューなどの部品）
    private static let minimumSize: CGFloat = 100
}
