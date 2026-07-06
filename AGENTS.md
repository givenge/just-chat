# Repository Guidelines

## Project Structure & Module Organization
`Sources/JustChat/` contains the single executable target. `JustChatApp.swift` is the `@main` entry point, `AppState.swift` is the shared state/orchestration layer, and most UI lives in `MainWindowView.swift`, `SettingsView.swift`, `Panels.swift`, and `MarkdownView.swift`. Networking and persistence live in files such as `ChatSessionService.swift`, `ChatModelAdapters.swift`, `TavilySearchService.swift`, and `SQLiteStore.swift`. `Tests/JustChatTests/` mirrors core areas with XCTest coverage. `Resources/` stores bundle assets like `AppIcon.icns`, `scripts/` contains packaging helpers, and `docs/` holds plans and design specs. Treat `.build/` as generated output.

## Build, Test, and Development Commands
`swift build` builds the debug app.  
`swift build -c release` builds the release binary used for packaging.  
`swift run JustChat` launches the app from the Swift package.  
`swift test` runs the full XCTest suite.  
`./scripts/package-app.sh` creates `.build/JustChat.app`, writes `Info.plist`, copies `Resources/AppIcon.icns`, and signs the bundle.

## Coding Style & Naming Conventions
Follow the existing Swift 6 style: types in UpperCamelCase, properties and methods in lowerCamelCase, and tests named with a `test...` prefix. The repository mostly uses 2-space indentation, short helper types near their call sites, and feature-oriented files instead of deep folder nesting. Keep UI state centralized in `AppState` and push behavioral changes through explicit methods rather than duplicating business logic inside views. No repo-wide formatter config is checked in, so match surrounding code and keep any `swiftlint` suppressions narrow.

## Testing Guidelines
Use XCTest in `Tests/JustChatTests/`. Add or update focused tests for any change in adapters, SSE streaming, SQLite persistence, panel behavior, or Tavily search flow. Name files `<Area>Tests.swift` and methods `test<Behavior>()`. Run `swift test` before opening a PR.

## Commit & Pull Request Guidelines
Recent commits use short, imperative subjects and may be English or Chinese, for example `Fix streaming parsing and UI polish` and `添加助手拖拽排序、清空话题、右键菜单功能`. Keep each commit scoped to one logical change. PRs should summarize user-visible impact, list verification steps, link related issues when relevant, and include screenshots or short recordings for UI or panel changes.

## Agent Notes
This repository already includes a `.codegraph/` index. Prefer `mcp__codegraph.codegraph_explore` for structural questions such as entry points, call paths, and impact analysis; reserve plain text search for literal strings or comments.
