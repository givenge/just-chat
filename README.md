# Just Chat

Just Chat is a native macOS AI chat client planned from Cherry Studio's core workflows and simplified for SwiftUI/AppKit.

Current scope:

- Main chat window with conversations, assistant/model controls, citations, and composer.
- Model service settings for OpenAI Chat Completions, OpenAI Responses, and Anthropic Messages.
- Quick Assistant floating panel.
- Selection Assistant toolbar/result panel.
- Tavily search plus provider-native search support for OpenAI Responses.

Build:

```bash
swift build
swift test
```

Run:

```bash
swift run JustChat
```

Create a local `.app` bundle:

```bash
chmod +x scripts/package-app.sh
scripts/package-app.sh
open .build/JustChat.app
```

Artifacts:

- OpenDesign reference: `design/opendesign/index.html`
- Implementation plan: `docs/2026-06-30-just-chat-macos-plan.md`

Configuration:

- Open **Settings -> 模型服务** and paste provider API keys directly into the provider cards.
- Open **Settings -> 网络搜索** and paste the Tavily API key.
- Providers, assistants, conversations, messages, search settings, app preferences, and API keys are persisted in SQLite under Application Support.

Current implementation status:

- Native SwiftUI/AppKit app shell with main chat window, settings, menu bar entry, Quick Assistant panel, and Selection Assistant panel.
- SQLite persistence for conversations, messages, providers, assistants, and search settings.
- SQLite persistence for API keys.
- Streaming request adapters for OpenAI Chat Completions, OpenAI Responses, and Anthropic Messages.
- Tavily search request/response normalization and context injection for non-native search.
- OpenAI Responses native `web_search` tool toggle.
- Local `.app` bundle packaging script at `scripts/package-app.sh`.
