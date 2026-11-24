import AppKit
import Carbon.HIToolbox

/// Carbon の RegisterEventHotKey を使った、どこからでも使えるショートカット
///
/// アクセシビリティの許可が要らず、サンドボックスの中でも使えるので、常駐アプリのショートカットに向いている。
/// （Pinshot・Pinshelf の HotKey と同じ作り）
final class HotKey {
    nonisolated let id: UInt32
    nonisolated let action: @MainActor () -> Void
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var handlerRef: EventHandlerRef?

    private static var nextID: UInt32 = 1

    /// 登録できなければ nil（ほかのアプリが同じキーを使っているときなど）
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        guard InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &eventType, userData, &handlerRef) == noErr else {
            return nil
        }

        // 'PNST' という識別子
        let hotKeyID = EventHotKeyID(signature: OSType(0x504E_5354), id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

/// ショートカットが押されたときに Carbon から呼ばれる
private nonisolated func hotKeyHandler(_ handler: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
    guard hotKeyID.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
    let action = hotKey.action
    Task { @MainActor in action() }
    return noErr
}

