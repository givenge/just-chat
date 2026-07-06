# Hotkey Recorder Design

Date: 2026-07-06

## Goal

Replace the current free-form shortcut text inputs with a Cherry Studio style recorder that captures key combinations directly, while keeping the existing persisted string format and Carbon hotkey registration path.

## User Experience

The hotkey settings pane keeps the same two rows for `快捷助手` and `划词助手`, but each row uses a recorder control instead of a `TextField`.

Default state shows the current shortcut as keycaps. Clicking the control enters recording mode, focuses a non-text control, and replaces the display with `按下快捷键`. While recording:

- Pressing a valid combination records it immediately.
- `Escape` cancels recording without changing the saved value.
- Losing focus exits recording mode.
- IME composing key events are ignored.

Each row also exposes a clear action that removes the shortcut binding. When a shortcut differs from the default value, the row shows a reset-to-default action.

Conflict feedback matches Cherry Studio behavior:

- If the two Just Chat actions use the same shortcut, the row shows an inline conflict message and does not save.
- If the system or another application already occupies the shortcut, the row shows an inline occupied message after registration fails.

## Data Flow

`AppPreferences.quickAssistantHotKey` and `AppPreferences.selectionAssistantHotKey` remain strings such as `Command+Shift+Space`. No migration is needed.

The recorder converts the captured key event into the same canonical string format already consumed by `HotKeyDescriptor`. This keeps persistence, decoding defaults, and `GlobalHotKeyCenter.registerHotKeys(...)` compatible with existing data.

The settings UI saves immediately after a successful recording, clear, or reset action by reusing `appState.persistConfiguration()`.

## Implementation Shape

The shortest path is to keep the current storage model and add one small shared shortcut utility plus one recorder view.

1. `SettingsView.swift`

- Replace `ShortcutTextField` with a recorder row view.
- Add local editing state, pending shortcut display, clear action, reset action, and inline error text.

2. Shortcut utility

- Add a small Swift helper that maps `NSEvent` modifier flags and key codes to:
  - a canonical persisted string for Just Chat
  - a display representation for keycaps
  - validation rules

3. `GlobalHotKeyCenter.swift`

- Keep Carbon registration.
- Return registration results per hotkey so the settings view can distinguish:
  - parsed and registered
  - parsed but occupied by system or another app
  - invalid or empty

No new persistence types, no new dependency, and no separate shortcut service are needed.

## Validation Rules

A shortcut is valid only when:

- it includes at least one modifier key
- it includes one non-modifier end key that `HotKeyDescriptor` can register

An empty shortcut is allowed only through the explicit clear action.

Before saving, the settings view checks for an in-app conflict between the two configured shortcuts. After saving, `GlobalHotKeyCenter` reports registration failures so the UI can surface external conflicts.

## Testing

Add focused tests for the new shortcut utility:

- canonical formatting for common modifier combinations
- invalid shortcut rejection when only modifiers are pressed
- equality/conflict checks between the two app shortcuts

Manual verification should cover:

- click to record
- `Escape` cancel
- clear shortcut
- reset to default
- duplicate shortcut conflict between the two rows
- external registration failure message when a shortcut is occupied
