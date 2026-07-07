import AppKit
import Carbon
import XCTest

@testable import JustChat

final class HotKeyShortcutTests: XCTestCase {
  func testNormalizesShortcutText() {
    let shortcut = HotKeyShortcut(text: "cmd + shift + space")

    XCTAssertEqual(shortcut?.stringValue, "Command+Shift+Space")
    XCTAssertEqual(shortcut?.displayParts, ["⌘", "⇧", "Space"])
  }

  func testRejectsShortcutWithoutModifier() {
    XCTAssertNil(HotKeyShortcut(text: "K"))
  }

  func testDetectsEquivalentShortcutConflicts() {
    XCTAssertTrue(HotKeyShortcut.conflicts("Command+Shift+Space", "cmd+shift+space"))
    XCTAssertFalse(HotKeyShortcut.conflicts("Command+Shift+Space", "Command+Option+Space"))
  }

  func testCapturesPhysicalKeyEvent() throws {
    let event = try XCTUnwrap(NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [.command, .shift],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: "k",
      charactersIgnoringModifiers: "k",
      isARepeat: false,
      keyCode: UInt16(kVK_ANSI_K)
    ))

    let shortcut = try HotKeyShortcut.capture(from: event).get()

    XCTAssertEqual(shortcut.stringValue, "Command+Shift+K")
  }
}
