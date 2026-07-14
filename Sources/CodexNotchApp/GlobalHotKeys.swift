import Carbon
import Foundation

final class GlobalHotKeys {
    enum Action: Equatable {
        case toggle
        case open(Int)
        case dismiss(Int)
    }

    struct NerdBinding: Equatable {
        let keyCode: UInt32
        let keyLabel: String
        let action: Action

        var displayLabel: String { "⌃⇧\(keyLabel)" }
    }

    static let nerdBindings: [NerdBinding] = [
        NerdBinding(keyCode: UInt32(kVK_ANSI_H), keyLabel: "H", action: .toggle),
        NerdBinding(keyCode: UInt32(kVK_ANSI_J), keyLabel: "J", action: .open(0)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_K), keyLabel: "K", action: .open(1)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_L), keyLabel: "L", action: .open(2)),
        // This physical key is Ö on the Swiss German keyboard layout.
        NerdBinding(keyCode: UInt32(kVK_ANSI_Semicolon), keyLabel: "Ö", action: .open(3)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_U), keyLabel: "U", action: .open(4)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_I), keyLabel: "I", action: .open(5)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_O), keyLabel: "O", action: .open(6)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_P), keyLabel: "P", action: .open(7)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_N), keyLabel: "N", action: .open(8)),
        NerdBinding(keyCode: UInt32(kVK_ANSI_M), keyLabel: "M", action: .open(9)),
    ]

    static func toggleShortcutLabel() -> String {
        nerdBindings.first(where: { $0.action == .toggle })?.displayLabel ?? "⌃⇧H"
    }

    static func openShortcutLabel(at index: Int) -> String? {
        nerdBindings.first(where: { $0.action == .open(index) })?.displayLabel
    }

    static func dismissShortcutLabel(at index: Int) -> String? {
        let labels = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        guard labels.indices.contains(index) else { return nil }
        return "⌥⇧\(labels[index])"
    }

    private let handler: (Action) -> Void
    private var eventHandler: EventHandlerRef?
    private var registrations: [EventHotKeyRef] = []
    private let signature: OSType = 0x4E_4F_54_43 // NOTC
    private static let nerdIDBase: UInt32 = 300

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
        let openNumberKeys: [UInt32] = [
            UInt32(kVK_ANSI_1), UInt32(kVK_ANSI_2), UInt32(kVK_ANSI_3),
            UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5), UInt32(kVK_ANSI_6),
            UInt32(kVK_ANSI_7), UInt32(kVK_ANSI_8), UInt32(kVK_ANSI_9),
        ]
        for (index, keyCode) in openNumberKeys.enumerated() {
            register(keyCode: keyCode, modifiers: UInt32(controlKey | shiftKey), id: UInt32(index + 1))
        }
        let dismissNumberKeys = openNumberKeys + [UInt32(kVK_ANSI_0)]
        for (index, keyCode) in dismissNumberKeys.enumerated() {
            register(keyCode: keyCode, modifiers: UInt32(optionKey | shiftKey), id: UInt32(index + 201))
        }
        for (index, binding) in Self.nerdBindings.enumerated() {
            register(
                keyCode: binding.keyCode,
                modifiers: UInt32(controlKey | shiftKey),
                id: Self.nerdIDBase + UInt32(index)
            )
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

    static func action(forHotKeyID id: UInt32) -> Action? {
        let nerdIndex = Int(id) - Int(nerdIDBase)
        if nerdBindings.indices.contains(nerdIndex) {
            return nerdBindings[nerdIndex].action
        }
        switch id {
        case 100: return .toggle
        case 1...9: return .open(Int(id - 1))
        case 201...210: return .dismiss(Int(id - 201))
        default: return nil
        }
    }

    private func dispatch(id: UInt32) {
        DispatchQueue.main.async { [handler] in
            guard let action = Self.action(forHotKeyID: id) else { return }
            handler(action)
        }
    }
}
