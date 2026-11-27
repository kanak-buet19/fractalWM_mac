import Carbon.HIToolbox

/// A system-wide hotkey via Carbon's RegisterEventHotKey.
/// Works without Accessibility permission and has no dependencies.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static let signature: OSType = 0x4657_4D21 // "FWM!"

    private let id: UInt32
    private var ref: EventHotKeyRef?

    /// - Parameters:
    ///   - keyCode: a `kVK_*` virtual key code.
    ///   - modifiers: Carbon modifier flags, e.g. `controlKey | optionKey | cmdKey`.
    init(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) {
        HotKey.installHandlerIfNeeded()
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.handlers[id] = handler

        let hotKeyID = EventHotKeyID(signature: HotKey.signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status != noErr {
            NSLog("fractalWM: failed to register hotkey (keyCode \(keyCode)), status \(status)")
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
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
            guard status == noErr, hotKeyID.signature == HotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            HotKey.handlers[hotKeyID.id]?()
            return noErr
        }, 1, &spec, nil, nil)
    }
}
