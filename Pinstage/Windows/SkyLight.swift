import AppKit
import ApplicationServices

/// macOS の非公開の API（SkyLight・アクセシビリティの非公開の関数）の窓口
///
/// デスクトップ（操作スペース）を扱う公開の API はないので、非公開の関数を使う。
/// 関数は名前で探し、見つからなければ使わない（macOS が変わって消えたときは、公開の API だけの推測の仕組みに戻る）。
/// 非公開の関数は、ここの外からは呼ばない。
enum SkyLight {
    /// 1 つのデスクトップ
    struct Space: Equatable {
        let id: UInt64
        /// フルスクリーンのアプリのデスクトップか
        let isFullScreen: Bool
        /// デスクトップの UUID（macOS が設定ファイルに保存していて、再起動しても変わらない。番号の id は変わることがある）。
        /// 空のときは nil（最初のデスクトップが空になる環境があるとされる）
        var uuid: String? = nil
    }

    /// 1 つのディスプレイのデスクトップ（左から順）
    struct Display: Equatable {
        /// ディスプレイの UUID（NSScreen.displayUUID と同じ形）。デスクトップがすべてのディスプレイにまたがる設定では "Main"
        let identifier: String
        let spaces: [Space]
        /// いま表に出ているデスクトップ
        let current: UInt64
    }

    // MARK: - 関数を探す

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias WindowsSpacesFunction = @convention(c) (Int32, CFArray, CFArray) -> Void
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias GetProcessForPIDFunction = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private typealias SetFrontProcessFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private typealias PostEventRecordFunction = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    private static let library = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func function<T>(_ names: [String], as type: T.Type) -> T? {
        for name in names {
            // SkyLight の中を探し、なければ読み込んであるすべての中を探す（古い名前は CoreGraphics にある）
            if let pointer = library.flatMap({ dlsym($0, name) }) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) {
                return unsafeBitCast(pointer, to: type)
            }
        }
        return nil
    }

    private static let mainConnection = function(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnectionFunction.self)
    private static let copyDisplaySpaces = function(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: CopyDisplaySpacesFunction.self)
    private static let copySpacesForWindows = function(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], as: CopySpacesForWindowsFunction.self)
    private static let addWindowsToSpaces = function(["SLSAddWindowsToSpaces", "CGSAddWindowsToSpaces"], as: WindowsSpacesFunction.self)
    private static let removeWindowsFromSpaces = function(["SLSRemoveWindowsFromSpaces", "CGSRemoveWindowsFromSpaces"], as: WindowsSpacesFunction.self)
    private static let getWindow = function(["_AXUIElementGetWindow"], as: GetWindowFunction.self)
    private static let getProcessForPID = function(["GetProcessForPID"], as: GetProcessForPIDFunction.self)
    private static let setFrontProcess = function(["_SLPSSetFrontProcessWithOptions"], as: SetFrontProcessFunction.self)
    private static let postEventRecord = function(["SLPSPostEventRecordTo"], as: PostEventRecordFunction.self)

    private static let connection: Int32? = mainConnection?()

    /// デスクトップを扱う関数がそろっているか（そろっていなければ、公開の API だけの推測の仕組みを使う）
    static let isAvailable: Bool = connection != nil && copyDisplaySpaces != nil && copySpacesForWindows != nil
        && addWindowsToSpaces != nil && removeWindowsFromSpaces != nil && displays() != nil

    // MARK: - デスクトップ

    /// ディスプレイごとのデスクトップの一覧（取れなければ nil）
    static func displays() -> [Display]? {
        guard let connection, let copyDisplaySpaces,
              let list = copyDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        let displays = list.compactMap { entry -> Display? in
            guard let identifier = entry["Display Identifier"] as? String else { return nil }
            let spaces = (entry["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> Space? in
                guard let id = Self.spaceID(space["ManagedSpaceID"]) else { return nil }
                // 種類: 0 = ふつうのデスクトップ、4 = フルスクリーンのアプリ
                let uuid = (space["uuid"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return Space(id: id, isFullScreen: (space["type"] as? Int) == 4, uuid: uuid)
            }
            let current = Self.spaceID((entry["Current Space"] as? [String: Any])?["ManagedSpaceID"]) ?? 0
            return Display(identifier: identifier, spaces: spaces, current: current)
        }
        return displays.isEmpty ? nil : displays
    }

    /// そのウインドウがあるデスクトップ（最小化したもの・隠しているだけのものは空のことがある）
    static func spaces(ofWindow id: CGWindowID) -> Set<UInt64> {
        guard let connection, let copySpacesForWindows,
              let list = copySpacesForWindows(connection, allSpacesMask, [id] as CFArray)?.takeRetainedValue() as? [Any]
        else { return [] }
        return Set(list.compactMap(Self.spaceID))
    }

    /// このアプリのウインドウを、そのデスクトップへ移す（見ていないデスクトップにも置ける）
    static func move(windowNumber: Int, to space: UInt64) {
        guard let connection, let addWindowsToSpaces, let removeWindowsFromSpaces else { return }
        let windows = [windowNumber] as CFArray
        let current = spaces(ofWindow: CGWindowID(windowNumber)).subtracting([space])
        addWindowsToSpaces(connection, windows, [space] as CFArray)
        if !current.isEmpty {
            removeWindowsFromSpaces(connection, windows, Array(current) as CFArray)
        }
    }

    /// そのディスプレイ（StageController.displayKey）のデスクトップの一覧。
    /// デスクトップがすべてのディスプレイにまたがる設定では、ディスプレイの名前が "Main" の 1 つだけになるので、それを使う
    static func display(forKey key: String, in displays: [Display]) -> Display? {
        displays.first { $0.identifier == key }
            ?? displays.first { $0.identifier == "Main" }
            ?? (displays.count == 1 ? displays[0] : nil)
    }

    /// いま表に出ているデスクトップ（ディスプレイごと）
    static func currentSpaces() -> Set<UInt64> {
        Set(displays()?.map(\.current) ?? [])
    }

    /// そのウインドウを、ほかのデスクトップにあっても前に出す（そのデスクトップへ移る）。出せたら true
    @discardableResult
    static func focus(windowID: CGWindowID, pid: pid_t) -> Bool {
        guard let getProcessForPID, let setFrontProcess, let postEventRecord else { return false }
        var process = ProcessSerialNumber()
        guard getProcessForPID(pid, &process) == noErr else { return false }
        // 利用者の操作として、そのウインドウのアプリを前に出す
        let userGenerated: UInt32 = 0x200
        guard setFrontProcess(&process, windowID, userGenerated) == .success else { return false }
        // そのウインドウを、キーウインドウにする知らせを送る
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: windowID) { bytes.replaceSubrange(0x3c..<0x40, with: $0) }
        for index in 0x20..<0x30 { bytes[index] = 0xff }
        bytes[0x08] = 0x01
        _ = postEventRecord(&process, &bytes)
        bytes[0x08] = 0x02
        _ = postEventRecord(&process, &bytes)
        return true
    }

    // MARK: - ウインドウの番号

    /// アクセシビリティの要素から、macOS のウインドウの番号を得る（得られなければ nil）
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var id: CGWindowID = 0
        return getWindow(element, &id) == .success && id != 0 ? id : nil
    }

    // MARK: -

    /// すべての種類のデスクトップ（いまのもの・ほかのもの・フルスクリーンのもの）
    private static let allSpacesMask: Int32 = 7

    private static func spaceID(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}
