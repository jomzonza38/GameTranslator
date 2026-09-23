import Carbon.HIToolbox
import Foundation

/// System-wide hotkeys via Carbon's RegisterEventHotKey.
/// Works while other apps (the game) are focused and needs no Accessibility permission.
final class HotKeyManager {
    static let shared = HotKeyManager()

    private var handlers: [UInt32: () -> Void] = [:]
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1

    /// "GTrn"
    private let signature: OSType = 0x4754_726E

    private init() {}

    /// Register a hotkey. `keyCode` is a kVK_* constant, `modifiers` a mask of
    /// Carbon cmdKey/shiftKey/optionKey/controlKey. The handler runs on the main thread.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping () -> Void) -> Bool {
        installEventHandlerIfNeeded()

        let id = nextID
        nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else {
            GameLog.log("Hotkey registration failed (keyCode \(keyCode)): \(status) — probably used by another app")
            return false
        }

        hotKeyRefs.append(ref)
        handlers[id] = handler
        return true
    }

    func unregisterAll() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        handlers.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
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

            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handlers[hotKeyID.id]?()
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }
}
