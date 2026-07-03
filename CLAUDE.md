# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test

```bash
swift build                # Debug build
swift build -c release     # Release build
swift test                 # Run all tests
swift run JustChat         # Run the app from CLI
```

Package the app as a `.app` bundle:

```bash
chmod +x scripts/package-app.sh
scripts/package-app.sh
open .build/JustChat.app
```

## Architecture

Just Chat is a native macOS AI chat client — a single Swift Package target (Swift 6, macOS 14+) using SwiftUI for the app shell and AppKit for floating panels and global hotkeys. It has one external dependency: `apple/swift-markdown` (linked as the `Markdown` product) used for rendering model output.

**Entry point:** `JustChatApp.swift` — `@main` struct, creates `AppState` as a `@StateObject`, injects it via `.environmentObject`. Defines the main window and menu bar extra (`MenuBarExtra`); a `CommandMenu` with toggle buttons for the Quick/Selection panels. Actual global hotkeys are registered via `GlobalHotKeyCenter.swift` (Carbon `RegisterEventHotKey`), wired through `AppState`.

**Central state:** `AppState.swift` is the `@MainActor ObservableObject` that owns all domain state and orchestrates persistence, chat streaming, and panel presentation. It owns:
- `SQLiteStore` — raw SQLite3 via `sqlite3.h` (no ORM). Stores conversations, messages, providers (including API keys in the `api_key` column), assistants, search settings, and app preferences.
- `ChatSessionService` — created per-request; runs streaming chat with web search injection.
- `QuickAssistantController` / `SelectionAssistantController` — `NSPanel`-based floating windows (defined in `Panels.swift`, not separate files).
- `ChatStreamEventQueue` — lock-backed event queue that decouples adapter SSE emission from UI consumption on the main thread.

**Request flow:**
1. `AppState.sendMessage()` creates a user message, appends a streaming assistant message, builds a `ChatRequest`.
2. `ChatSessionService.run()` optionally runs Tavily search, injects search context as a system message, then uses `chatAdapter(for:)` to get the correct adapter.
3. The adapter (`ChatModelAdapter` protocol) builds a provider-specific `URLRequest` and parses SSE events into `ChatStreamEvent` enum values (`.delta`, `.reasoningDelta`, `.citation`, `.usage`, `.completed`).
4. `ChatSessionService` parses streaming SSE lines into `SSEEvent` structs before handing them to the adapter.

**Three adapters** in `ChatModelAdapters.swift`:
- `OpenAIChatCompletionsAdapter` — `/v1/chat/completions`, classic `choices[0].delta.content` SSE parsing.
- `OpenAIResponsesAdapter` — `/v1/responses`, `response.output_text.delta` events, optional `web_search` tool.
- `AnthropicMessagesAdapter` — `/v1/messages`, `x-api-key` header, `content_block_delta` events, system prompt extracted from messages.

**Web search** (`WebSearchMode`):
- `.disabled` — no search.
- `.tavily` — `TavilySearchService` calls Tavily API, results injected as a system message at position 0.
- `.providerNative` — only for OpenAI Responses, adds `tools: [{"type": "web_search"}]` to the request body.

**Data model** (`Models.swift`): Model types are `Codable`/`Sendable`, with `Equatable` or `Identifiable` only where call sites need it. Key types: `Conversation`, `ChatMessage` (note: has both `content` and `reasoningContent`), `AssistantProfile`, `ModelProvider` (carries both `providerType: ProviderCatalogType` for catalog/display and `kind: ProviderKind` for the request API), `SearchSettings`, `AppPreferences`, `Citation`, `TokenUsage`. `ProviderCatalogType` enumerates provider brands (openAI, openAIResponse, anthropic, gemini, azureOpenAI, newAPI, cherryIN, ollama) and provides default base URL and models; `ProviderKind` is the actual API shape (openAIChatCompletions, OpenAI Responses, Anthropic Messages).

**Navigation:** `RootSection` is `.home` / `.settings` — there is no top nav bar. The home sidebar has a **助手 / 话题 segmented tab** (`HomeSidebarTab` / `AppState.homeSidebarTab`): assistants list, or topics (conversations) filtered to the selected assistant. A **设置 button is pinned to the bottom-left of the sidebar** (sets `rootSection = .settings`). The settings screen has a **返回 button** at the top of its nav column (sets `rootSection = .home`).

**Topic management:** conversations are per-assistant (`Conversation.assistantId`). `AppState` exposes `createConversation()` / `renameConversation(id:title:)` / `deleteConversation(id:)` (SQLiteStore `updateConversationTitle` / `deleteConversation` delete the conversation and its messages). `ensureConversationForSelectedAssistant()` respects the currently selected topic if it belongs to the active assistant, so `sendMessage` writes to the topic the user picked rather than the first one.

**Assistant editing** (`MainWindowView.AssistantEditorDrawer`): Assistant settings are **not** a settings pane — they're a right-side pop-out drawer overlaid on the home screen, toggled by `AppState.assistantEditorPresented`. Triggered from the `AssistantRow` "编辑助手" menu and the `ChatHeader` `slider.horizontal.3` button. The drawer wraps `AssistantEditor` (defined in `MainWindowView.swift`) with a close (×) header; it slides in from `.trailing` and dismisses on outside-tap. `SettingsPane.assistants` was removed.

**Markdown / code rendering** (`MarkdownView.swift`): `MarkdownText(content:)` parses with `import Markdown` (`Document(parsing:)`) and walks the block tree into SwiftUI — headings, paragraphs (inline via `AttributedString(markdown:)`), fenced/indented code blocks, blockquotes, ordered/unordered lists (nested), tables, thematic breaks. Used by both `MessageBubble` and `Panels.ResultBlock`. `CodeBlockView` renders a code block with a language label, copy-to-clipboard button (`NSPasteboard`), and horizontal scroll. `SyntaxHighlighter.highlight(code:language:)` is a lightweight regex tokenizer that colors comments/strings/numbers/keywords/types via the `justCode*` tokens in `Theme.swift`. **Name-collision gotcha:** `swift-markdown` exports `Text`, `Table`, `Link` which clash with SwiftUI — qualify as `Markdown.Table` / `SwiftUI.Text` inside `MarkdownView.swift`. The `blockView`/`blocksView` pair is mutually recursive, so `blocksView` wraps each child in `AnyView(...)` to break the opaque-type cycle.

**Chat layout** (`MainWindowView.MessageBubble`): assistant messages are full-width (avatar + `Just Chat` header + timestamp + token meta + `MarkdownText`, no bubble); user messages are right-aligned tinted glass bubbles (maxWidth ~520). The transcript uses `.padding(.horizontal, 28)` for code width. The `ChatHeader` model picker lists **all providers as submenus** (each with its models) and calls `AppState.setSelectedAssistantProviderAndModel(providerId:modelId:)` to rebind provider+model in one step — not just the current provider's models.

**Context limit:** `AssistantProfile.contextMessageCount` (default 20, 0 = send only the last message) caps how many recent messages `AppState.sendMessage` includes in the `ChatRequest` (`Array(requestMessages.suffix(limit))` when >0, `suffix(1)` when 0). Set via a stepper in the assistant editor's 参数 card. Persisted in the `assistants.context_message_count` column (added via `addColumnIfNeeded` migration).

**Design system** (`Theme.swift`): Single source of truth for active colors, radii, shadows, hover surfaces, and the shared `Card` surface. Colors are dark-mode aware without an asset catalog — each `Color.just*` constant is backed by `NSColor(name:dynamicProvider:)` wrapped in `Color(nsColor:)`, resolving to light/dark values from `@Environment(\.colorScheme)`. Accent is blue (`#0071E3` light / `#0A84FF` dark). Provides `Radius`, `Card<Content>`, `hoverSurface()`, `cardShadow()`/`raisedShadow()`, `LinearGradient.justAccent`. `SettingsView.SettingsCard` mirrors `Card`'s styling. **Avoid hardcoded `Color(r,g,b)` fills in views — use the active `just*` tokens or materials (`.regularMaterial`/`.ultraThinMaterial`) so dark mode stays correct.** Floating `NSPanel`s set `isOpaque = false` + `backgroundColor = .clear` so hosted materials actually frost the desktop.

**Panels** (`Panels.swift`): `QuickAssistantPanel` (floating chat with quick actions) and `SelectionAssistantPanel` (selection toolbar with Copy/Search/Translate/Explain/Summarize). Both are SwiftUI views hosted in AppKit `NSPanel` windows.

**Global hotkeys** (`GlobalHotKeyCenter.swift`): Carbon `RegisterEventHotKey` for `Cmd+Shift+Space` (quick assistant) and `Cmd+Shift+E` (selection assistant). Static weak reference pattern for the event handler callback.

**Settings** (`SettingsView.swift`): Three-column layout with navigation (topped by a 返回 button), optional provider list (shown only on `.providers` pane), and detail pane. `SettingsPane` cases include `providers`, `defaultModel`, `search`, `quickAssistant`, `selectionAssistant`, `hotKeys`, plus placeholder panes (no `assistants` — assistant editing is the right-side drawer, see above). `AddProviderSheet` picks a `ProviderCatalogType` and calls `AppState.addProvider(type:name:)`. All cards use the private `SettingsCard`, which shares styling with `Theme.Card`.

**Defaults** (`Defaults.swift`): Hardcoded fallback providers and four assistant profiles (default, English translator, Chinese translator, weekly report). Used only when the SQLite store is empty; `AppState.loadOrSeed` also backfills missing starter assistants and normalizes legacy provider types/names.

## Key Patterns

- All UI state lives in `AppState`; views read via `@EnvironmentObject` and mutate through `AppState` methods or bindings.
- `AppState` is the single source of truth — panels and settings all use the same instance.
- Database operations are synchronous (SQLite on the main actor is fine for this scale).
- Streaming uses `URLSession.bytes(for:)` with `AsyncSequence` iteration.
- API keys are stored directly in SQLite (`providers.api_key` column) — there is no Keychain dependency.
- Tests use `@testable import JustChat` to access internal types.
