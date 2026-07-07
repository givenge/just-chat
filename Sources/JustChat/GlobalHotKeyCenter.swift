import Carbon
import Dispatch
import Foundation

enum HotKeyRegistrationStatus: Equatable, Sendable {
    case empty
    case invalid
    case registered
    case occupied
}

struct HotKeyRegistrationResults: Equatable, Sendable {
    var quick: HotKeyRegistrationStatus = .empty
    var selection: HotKeyRegistrationStatus = .empty
}

@MainActor
final class GlobalHotKeyCenter {
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var quickAction: (() -> Void)?
    private var selectionAction: (() -> Void)?

    init() {
        Self.active = self
    }

    func registerHotKeys(preferences: AppPreferences, quick: @escaping () -> Void, selection: @escaping () -> Void) -> HotKeyRegistrationResults {
        quickAction = quick
        selectionAction = selection
        unregister()
        installHandlerIfNeeded()
        return HotKeyRegistrationResults(
            quick: registerHotKey(id: HotKeyID.quick.rawValue, text: preferences.quickAssistantHotKey),
            selection: registerHotKey(id: HotKeyID.selection.rawValue, text: preferences.selectionAssistantHotKey)
        )
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

    private func registerHotKey(id: UInt32, text: String) -> HotKeyRegistrationStatus {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        guard let descriptor = HotKeyDescriptor(text) else {
            return .invalid
        }

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(descriptor.keyCode, descriptor.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRefs.append(ref)
            return .registered
        }
        return .occupied
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
        guard let shortcut = HotKeyShortcut(text: text),
              let keyCode = shortcut.keyCode
        else { return nil }

        self.keyCode = keyCode
        self.modifiers = shortcut.carbonModifiers
    }
}
