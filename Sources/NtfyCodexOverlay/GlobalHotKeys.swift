import Carbon
import Foundation

final class GlobalHotKeys {
    enum Action {
        case toggle
        case open(Int)
        case dismiss(Int)
    }

    private let handler: (Action) -> Void
    private var eventHandler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private let signature: OSType = 0x4E_54_46_59 // NTFY

    init(handler: @escaping (Action) -> Void) {
        self.handler = handler
        installHandler()
        registerAll()
    }

    deinit {
        registrations.forEach { _ = UnregisterEventHotKey($0) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func installHandler() {
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
            let manager = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            manager.dispatch(id: hotKeyID.id)
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

    private func registerAll() {
        register(keyCode: UInt32(kVK_ANSI_0), modifiers: UInt32(controlKey | shiftKey), id: 100)
        let numberKeys: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]
        for (index, keyCode) in numberKeys.enumerated() {
            register(keyCode: keyCode, modifiers: UInt32(controlKey | shiftKey), id: UInt32(index + 1))
            register(keyCode: keyCode, modifiers: UInt32(optionKey | shiftKey), id: UInt32(index + 201))
        }
    }

    private func register(keyCode: UInt32, modifiers: UInt32, id: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            registrations.append(reference)
        } else {
            NSLog("Could not register global shortcut id %d (status %d)", id, status)
        }
    }

    private func dispatch(id: UInt32) {
        DispatchQueue.main.async { [handler] in
            switch id {
            case 100: handler(.toggle)
            case 1...9: handler(.open(Int(id - 1)))
            case 201...209: handler(.dismiss(Int(id - 201)))
            default: break
            }
        }
    }
}
