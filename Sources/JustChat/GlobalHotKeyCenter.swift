import Carbon
import Dispatch
import Foundation

@MainActor
final class GlobalHotKeyCenter {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var quickAction: (() -> Void)?
    private var selectionAction: (() -> Void)?

    init() {
        Self.active = self
    }

    func registerHotKeys(preferences: AppPreferences, quick: @escaping () -> Void, selection: @escaping () -> Void) {
        quickAction = quick
        selectionAction = selection
        unregister()
        installHandlerIfNeeded()
        if let quickHotKey = HotKeyDescriptor(preferences.quickAssistantHotKey) {
            registerHotKey(id: HotKeyID.quick.rawValue, descriptor: quickHotKey)
        }
        if let selectionHotKey = HotKeyDescriptor(preferences.selectionAssistantHotKey) {
            registerHotKey(id: HotKeyID.selection.rawValue, descriptor: selectionHotKey)
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                let pressedHotKeyID = hotKeyID.id
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        GlobalHotKeyCenter.active?.perform(id: pressedHotKeyID)
                    }
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    private func registerHotKey(id: UInt32, descriptor: HotKeyDescriptor) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(descriptor.keyCode, descriptor.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
        }
    }

    private func perform(id: UInt32) {
        switch HotKeyID(rawValue: id) {
        case .quick:
            quickAction?()
        case .selection:
            selectionAction?()
        case nil:
            break
        }
    }

    private func unregister() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    private static weak var active: GlobalHotKeyCenter?
    private static let signature = OSType(
        UInt32(Character("J").asciiValue!) << 24 |
        UInt32(Character("C").asciiValue!) << 16 |
        UInt32(Character("H").asciiValue!) << 8 |
        UInt32(Character("T").asciiValue!)
    )
}

private enum HotKeyID: UInt32 {
    case quick = 1
    case selection = 2
}

private struct HotKeyDescriptor {
    let keyCode: UInt32
    let modifiers: UInt32

    init?(_ text: String) {
        let parts = text
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard let keyText = parts.last,
              let keyCode = Self.keyCodes[keyText]
        else { return nil }

        var modifiers: UInt32 = 0
        for modifier in parts.dropLast() {
            switch modifier {
            case "command", "cmd", "⌘":
                modifiers |= UInt32(cmdKey)
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
            case "option", "alt", "⌥":
                modifiers |= UInt32(optionKey)
            case "control", "ctrl", "⌃":
                modifiers |= UInt32(controlKey)
            default:
                return nil
            }
        }

        guard modifiers != 0 else { return nil }
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private static let keyCodes: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A),
        "b": UInt32(kVK_ANSI_B),
        "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D),
        "e": UInt32(kVK_ANSI_E),
        "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G),
        "h": UInt32(kVK_ANSI_H),
        "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J),
        "k": UInt32(kVK_ANSI_K),
        "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M),
        "n": UInt32(kVK_ANSI_N),
        "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P),
        "q": UInt32(kVK_ANSI_Q),
        "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S),
        "t": UInt32(kVK_ANSI_T),
        "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V),
        "w": UInt32(kVK_ANSI_W),
        "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y),
        "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0),
        "1": UInt32(kVK_ANSI_1),
        "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3),
        "4": UInt32(kVK_ANSI_4),
        "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6),
        "7": UInt32(kVK_ANSI_7),
        "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space),
        "return": UInt32(kVK_Return),
        "enter": UInt32(kVK_Return),
        "escape": UInt32(kVK_Escape),
        "esc": UInt32(kVK_Escape),
        "tab": UInt32(kVK_Tab),
        "delete": UInt32(kVK_Delete),
        "backspace": UInt32(kVK_Delete),
        "left": UInt32(kVK_LeftArrow),
        "right": UInt32(kVK_RightArrow),
        "up": UInt32(kVK_UpArrow),
        "down": UInt32(kVK_DownArrow),
        "f1": UInt32(kVK_F1),
        "f2": UInt32(kVK_F2),
        "f3": UInt32(kVK_F3),
        "f4": UInt32(kVK_F4),
        "f5": UInt32(kVK_F5),
        "f6": UInt32(kVK_F6),
        "f7": UInt32(kVK_F7),
        "f8": UInt32(kVK_F8),
        "f9": UInt32(kVK_F9),
        "f10": UInt32(kVK_F10),
        "f11": UInt32(kVK_F11),
        "f12": UInt32(kVK_F12)
    ]
}
