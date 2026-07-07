import AppKit
import Carbon
import Foundation

struct HotKeyShortcut: Equatable, Sendable {
  enum Modifier: String, CaseIterable, Sendable {
    case command = "Command"
    case shift = "Shift"
    case option = "Option"
    case control = "Control"

    var display: String {
      switch self {
      case .command: "⌘"
      case .shift: "⇧"
      case .option: "⌥"
      case .control: "⌃"
      }
    }

    var carbonFlag: UInt32 {
      switch self {
      case .command: UInt32(cmdKey)
      case .shift: UInt32(shiftKey)
      case .option: UInt32(optionKey)
      case .control: UInt32(controlKey)
      }
    }
  }

  enum CaptureError: Error, Equatable {
    case missingModifier
    case unsupportedKey

    var message: String {
      switch self {
      case .missingModifier:
        "快捷键需要包含 Command、Option、Control 或 Shift。"
      case .unsupportedKey:
        "暂不支持这个按键。"
      }
    }
  }

  let modifiers: [Modifier]
  let key: String

  var stringValue: String {
    (modifiers.map(\.rawValue) + [key]).joined(separator: "+")
  }

  var displayParts: [String] {
    modifiers.map(\.display) + [Self.displayName(for: key)]
  }

  var keyCode: UInt32? {
    Self.keyCodes[key.lowercased()]
  }

  var carbonModifiers: UInt32 {
    modifiers.reduce(0) { $0 | $1.carbonFlag }
  }

  init?(text: String) {
    let parts = text
      .split(separator: "+")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    guard let keyText = parts.last else { return nil }

    var modifiers: [Modifier] = []
    for part in parts.dropLast() {
      guard let modifier = Self.modifier(from: part) else { return nil }
      if !modifiers.contains(modifier) {
        modifiers.append(modifier)
      }
    }

    guard !modifiers.isEmpty,
      let key = Self.canonicalKey(from: keyText)
    else { return nil }

    self.modifiers = Self.ordered(modifiers)
    self.key = key
  }

  static func capture(from event: NSEvent) -> Result<HotKeyShortcut, CaptureError> {
    guard let key = canonicalKey(forKeyCode: event.keyCode) else {
      return .failure(.unsupportedKey)
    }

    let modifiers = ordered(Modifier.allCases.filter { modifier in
      switch modifier {
      case .command:
        event.modifierFlags.contains(.command)
      case .shift:
        event.modifierFlags.contains(.shift)
      case .option:
        event.modifierFlags.contains(.option)
      case .control:
        event.modifierFlags.contains(.control)
      }
    })

    guard !modifiers.isEmpty else {
      return .failure(.missingModifier)
    }

    return .success(HotKeyShortcut(modifiers: modifiers, key: key))
  }

  static func conflicts(_ lhs: String, _ rhs: String) -> Bool {
    guard let lhs = HotKeyShortcut(text: lhs), let rhs = HotKeyShortcut(text: rhs) else {
      return false
    }
    return lhs == rhs
  }

  private init(modifiers: [Modifier], key: String) {
    self.modifiers = modifiers
    self.key = key
  }

  private static func ordered(_ modifiers: [Modifier]) -> [Modifier] {
    Modifier.allCases.filter { modifiers.contains($0) }
  }

  private static func modifier(from text: String) -> Modifier? {
    switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "command", "cmd", "⌘":
      .command
    case "shift", "⇧":
      .shift
    case "option", "alt", "⌥":
      .option
    case "control", "ctrl", "⌃":
      .control
    default:
      nil
    }
  }

  private static func canonicalKey(from text: String) -> String? {
    let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return keyAliases[lowercased] ?? keyCodes[lowercased].map { _ in displayName(for: lowercased) }
  }

  private static func canonicalKey(forKeyCode keyCode: UInt16) -> String? {
    keyCodeNames[keyCode]
  }

  private static func displayName(for key: String) -> String {
    switch key.lowercased() {
    case "space": "Space"
    case "return": "Return"
    case "escape": "Escape"
    case "tab": "Tab"
    case "delete": "Delete"
    case "left": "Left"
    case "right": "Right"
    case "up": "Up"
    case "down": "Down"
    default:
      if key.range(of: #"^f(?:[1-9]|1[0-2])$"#, options: .regularExpression) != nil {
        key.uppercased()
      } else {
        key.count == 1 ? key.uppercased() : key
      }
    }
  }

  private static let keyAliases: [String: String] = [
    "enter": "Return",
    "esc": "Escape",
    "backspace": "Delete",
    "arrowleft": "Left",
    "arrowright": "Right",
    "arrowup": "Up",
    "arrowdown": "Down",
  ]

  static let keyCodes: [String: UInt32] = [
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
    "escape": UInt32(kVK_Escape),
    "tab": UInt32(kVK_Tab),
    "delete": UInt32(kVK_Delete),
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
    "f12": UInt32(kVK_F12),
  ]

  private static let keyCodeNames: [UInt16: String] =
    Dictionary(uniqueKeysWithValues: keyCodes.map { (UInt16($0.value), displayName(for: $0.key)) })
}
