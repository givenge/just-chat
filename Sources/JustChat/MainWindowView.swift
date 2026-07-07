import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindowView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    ZStack {
      if appState.rootSection == .home {
        HomeWorkspace()
      } else {
        SettingsView()
          .environmentObject(appState)
      }

      if appState.rootSection == .home, appState.assistantEditorPresented {
        HStack(spacing: 0) {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { appState.assistantEditorPresented = false }
          AssistantEditorDrawer()
        }
        .transition(.move(edge: .trailing))
      }
    }
    .animation(.easeInOut(duration: 0.25), value: appState.assistantEditorPresented)
    .background(Color.justWindowBackground)
    .preferredColorScheme(appState.preferences.appearanceMode.preferredColorScheme)
    .onAppear {
      appState.startHotKeys()
    }
    .onChange(of: appState.selectedConversationId) {
      appState.loadSelectedConversationMessages()
    }
    .onChange(of: appState.preferences.appearanceMode) {
      appState.refreshFloatingPanelAppearance()
    }
  }
}

private struct AssistantEditorDrawer: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    HStack(spacing: 0) {
      VStack(spacing: 0) {
        HStack {
          Text("编辑助手")
            .font(.system(size: 17, weight: .bold))
          Spacer()
          Button {
            appState.assistantEditorPresented = false
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.secondary)
              .frame(width: 28, height: 28)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .hoverSurface(radius: Radius.sm)
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)

        Divider()

        AssistantEditor()
      }
      .frame(width: 420)
      .background(.regularMaterial)
      .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .stroke(Color.justBorderSoft, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
      .raisedShadow()
    }
  }
}

private struct HomeWorkspace: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    HStack(spacing: 0) {
      HomeSidebar()
        .frame(width: appState.preferences.homeSidebarWidth)

      SidebarResizeHandle(width: $appState.preferences.homeSidebarWidth) {
        appState.persistConfiguration()
      }

      ChatWorkspace()
    }
  }
}

private struct HomeSidebar: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 0) {
      Picker("首页列表", selection: $appState.homeSidebarTab) {
        ForEach(HomeSidebarTab.allCases, id: \.self) { tab in
          Text(tab.rawValue).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 18)
      .padding(.top, 14)
      .padding(.bottom, 10)

      if appState.homeSidebarTab == .assistants {
        AssistantsHomeList()
          .frame(maxHeight: .infinity)
      } else {
        TopicList()
          .frame(maxHeight: .infinity)
      }

      Divider()

      Button {
        appState.assistantEditorPresented = false
        appState.rootSection = .settings
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "gearshape")
            .font(.system(size: 15, weight: .medium))
          Text("设置")
            .font(.system(size: 15, weight: .semibold))
          Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .hoverSurface(radius: Radius.sm, opacity: 0.5)
      .padding(.horizontal, 12)
      .padding(.bottom, 12)
    }
    .background(Color.justSidebarBackground)
  }
}

private struct TopicList: View {
  @EnvironmentObject private var appState: AppState
  @State private var renamingId: UUID?
  @State private var renameText = ""

  private var topics: [Conversation] {
    appState.conversations.filter { $0.assistantId == appState.selectedAssistantId }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        appState.createConversation()
      } label: {
        Label("新话题", systemImage: "square.and.pencil")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .hoverSurface(radius: Radius.sm, opacity: 0.5)
      .padding(.horizontal, 20)
      .padding(.top, 6)

      ScrollView {
        LazyVStack(spacing: 8) {
          ForEach(topics) { conversation in
            TopicRow(
              conversation: conversation,
              isSelected: appState.selectedConversationId == conversation.id,
              renaming: renamingId == conversation.id,
              renameText: $renameText,
              onStartRename: {
                renamingId = conversation.id
                renameText = conversation.title
              },
              onCommitRename: {
                appState.renameConversation(id: conversation.id, title: renameText)
                renamingId = nil
              },
              onCancelRename: { renamingId = nil },
              onSelect: { appState.selectedConversationId = conversation.id },
              onDelete: { appState.deleteConversation(id: conversation.id) })
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
      }
    }
  }
}

private struct TopicRow: View {
  var conversation: Conversation
  var isSelected: Bool
  var renaming: Bool
  @Binding var renameText: String
  var onStartRename: () -> Void
  var onCommitRename: () -> Void
  var onCancelRename: () -> Void
  var onSelect: () -> Void
  var onDelete: () -> Void

  var body: some View {
    if renaming {
      HStack(spacing: 8) {
        Image(systemName: "text.bubble")
          .foregroundStyle(Color.justAccent)
        TextField("话题名称", text: $renameText, onCommit: onCommitRename)
          .textFieldStyle(.plain)
          .font(.system(size: 14, weight: .semibold))
          .onSubmit(onCommitRename)
        Button(action: onCommitRename) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.justSuccess)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverSurface(radius: Radius.pill, opacity: 0.5)
        Button(action: onCancelRename) {
          Image(systemName: "xmark.circle.fill")
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverSurface(radius: Radius.pill, opacity: 0.5)
      }
      .padding(.horizontal, 12)
      .frame(height: 50)
      .background(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .fill(Color.justControlBackground)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .stroke(Color.justAccent.opacity(0.5), lineWidth: 1)
      )
    } else {
      Button(action: onSelect) {
        HStack(spacing: 8) {
          Image(systemName: "text.bubble")
            .foregroundStyle(.secondary)
          VStack(alignment: .leading, spacing: 2) {
            Text(conversation.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(.primary)
              .lineLimit(1)
          }
          Spacer()
          if isSelected {
            Menu {
              Button("重命名", action: onStartRename)
              Button("删除", role: .destructive, action: onDelete)
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.justControlBackground.opacity(0.85))
                .clipShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .focusable(false)
            .hoverSurface(radius: Radius.pill, opacity: 0.45)
          }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 50)
        .background(
          RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(isSelected ? Color.justControlBackground : Color.clear)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .stroke(Color.justBorderSoft, lineWidth: isSelected ? 1 : 0)
        )
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .hoverSurface(radius: Radius.md, opacity: 0.5)
    }
  }
}

private struct AssistantsHomeList: View {
  @EnvironmentObject private var appState: AppState
  @State private var draggingAssistant: AssistantProfile?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button {
        appState.addAssistant()
      } label: {
        Label("添加助手", systemImage: "plus")
          .font(.system(size: 15, weight: .medium))
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .frame(height: 34)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .focusable(false)
      .hoverSurface(radius: Radius.sm, opacity: 0.5)
      .padding(.horizontal, 20)
      .padding(.top, 6)

      ScrollView {
        VStack(spacing: 8) {
          ForEach(appState.assistants) { assistant in
            AssistantRow(assistant: assistant)
              .opacity(draggingAssistant?.id == assistant.id ? 0.0 : 1.0)
              .onDrag {
                draggingAssistant = assistant
                return NSItemProvider(object: assistant.id.uuidString as NSString)
              }
              .onDrop(of: [.text], delegate: AssistantDropDelegate(
                assistant: assistant,
                assistants: appState.assistants,
                draggingAssistant: $draggingAssistant,
                onMove: appState.moveAssistant
              ))
          }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
      }
    }
  }
}

private struct AssistantDropDelegate: DropDelegate {
  let assistant: AssistantProfile
  let assistants: [AssistantProfile]
  @Binding var draggingAssistant: AssistantProfile?
  let onMove: (IndexSet, Int) -> Void

  func performDrop(info: DropInfo) -> Bool {
    draggingAssistant = nil
    return true
  }

  func dropUpdated(info: DropInfo) -> DropProposal? {
    return DropProposal(operation: .move)
  }

  func dropEntered(info: DropInfo) {
    guard let dragging = draggingAssistant,
          let fromIndex = assistants.firstIndex(where: { $0.id == dragging.id }),
          let toIndex = assistants.firstIndex(where: { $0.id == assistant.id }),
          fromIndex != toIndex else { return }

    withAnimation(.easeInOut(duration: 0.2)) {
      onMove(IndexSet(integer: fromIndex), toIndex > fromIndex ? toIndex + 1 : toIndex)
    }
  }
}

private struct AssistantRow: View {
  @EnvironmentObject private var appState: AppState
  var assistant: AssistantProfile

  private var isSelected: Bool {
    appState.selectedAssistantId == assistant.id
  }

  var body: some View {
    Button {
      appState.selectAssistant(assistant.id)
    } label: {
      HStack(spacing: 12) {
        AssistantAvatar(name: assistant.name)
          .frame(width: 32, height: 32)

        Text(assistant.name)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)

        Spacer()

        if isSelected {
          Menu {
            Button("清空话题") {
              appState.clearTopicsForSelectedAssistant()
            }
            Button("编辑助手") {
              appState.assistantEditorPresented = true
            }
            Button("删除助手", role: .destructive) {
              appState.deleteSelectedAssistant()
            }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 15, weight: .semibold))
              .frame(width: 26, height: 26)
              .background(Color.justControlBackground.opacity(0.85))
              .clipShape(Circle())
          }
          .menuStyle(.button)
          .buttonStyle(.plain)
          .focusable(false)
          .hoverSurface(radius: Radius.pill, opacity: 0.45)
        }
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: 46)
      .background(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .fill(isSelected ? Color.justControlBackground : Color.clear)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .stroke(Color.justBorderSoft, lineWidth: isSelected ? 1 : 0)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .focusable(false)
    .hoverSurface(radius: Radius.md, opacity: 0.5)
    .contextMenu {
      Button("清空话题") {
        appState.clearTopicsForSelectedAssistant()
      }
      Button("编辑助手") {
        appState.assistantEditorPresented = true
      }
      Button("删除助手", role: .destructive) {
        appState.deleteSelectedAssistant()
      }
    }
  }
}

private struct ChatWorkspace: View {
  @EnvironmentObject private var appState: AppState
  @State private var isSearchPresented = false
  @State private var searchText = ""
  @State private var selectedSearchMatchIndex = 0

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var searchMatches: [UUID] {
    guard !searchQuery.isEmpty else { return [] }
    return appState.messages
      .filter { $0.matches(searchQuery) }
      .map(\.id)
  }

  private var activeSearchMessageId: UUID? {
    guard !searchMatches.isEmpty else { return nil }
    return searchMatches[min(selectedSearchMatchIndex, searchMatches.count - 1)]
  }

  var body: some View {
    VStack(spacing: 0) {
      ChatHeader(
        isSearchPresented: $isSearchPresented,
        searchText: $searchText,
        searchMatchCount: searchMatches.count,
        selectedSearchMatchIndex: activeSearchMessageId == nil ? nil : selectedSearchMatchIndex,
        onPreviousSearchMatch: { advanceSearchSelection(by: -1) },
        onNextSearchMatch: { advanceSearchSelection(by: 1) }
      )
      Divider()
      ChatTranscriptView(searchText: searchText, activeSearchMessageId: activeSearchMessageId)
      ComposerView()
    }
    .background(Color.justWindowBackground)
    .onChange(of: searchText) {
      selectedSearchMatchIndex = 0
    }
    .onChange(of: searchMatches) {
      clampSearchSelection()
    }
  }

  private func advanceSearchSelection(by offset: Int) {
    guard !searchMatches.isEmpty else { return }
    selectedSearchMatchIndex =
      (selectedSearchMatchIndex + offset + searchMatches.count) % searchMatches.count
  }

  private func clampSearchSelection() {
    guard !searchMatches.isEmpty else {
      selectedSearchMatchIndex = 0
      return
    }
    selectedSearchMatchIndex = min(selectedSearchMatchIndex, searchMatches.count - 1)
  }
}

private struct ChatHeader: View {
  @EnvironmentObject private var appState: AppState
  @Binding var isSearchPresented: Bool
  @Binding var searchText: String
  var searchMatchCount: Int
  var selectedSearchMatchIndex: Int?
  var onPreviousSearchMatch: () -> Void
  var onNextSearchMatch: () -> Void
  @FocusState private var searchFocused: Bool

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  var body: some View {
    HStack(spacing: 14) {
      AssistantAvatar(name: appState.selectedAssistant.name)
        .frame(width: 34, height: 34)

      Menu {
        ForEach(appState.assistants) { assistant in
          Button(assistant.name) {
            appState.selectAssistant(assistant.id)
          }
        }
      } label: {
        HStack(spacing: 8) {
          Text(appState.selectedAssistant.name)
            .font(.system(size: 15, weight: .semibold))
          Image(systemName: "chevron.right")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
      }
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface(radius: Radius.sm, opacity: 0.45)

      Menu {
        ForEach(appState.providers) { provider in
          Menu(provider.name) {
            ForEach(provider.models, id: \.self) { model in
              Button(model) {
                appState.setSelectedAssistantProviderAndModel(
                  providerId: provider.id,
                  modelId: model
                )
              }
            }
          }
        }
      } label: {
        HStack(spacing: 8) {
          Text("\(appState.selectedAssistant.modelId) | \(appState.activeProvider.name)")
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(Capsule().fill(Color.justControlBackground))
        .overlay(Capsule().stroke(Color.justBorderSoft, lineWidth: 1))
      }
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface(radius: Radius.pill, opacity: 0.45)

      Spacer()

      if isSearchPresented {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.secondary)
          TextField("搜索当前话题", text: $searchText)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .focused($searchFocused)
            .onSubmit {
              onNextSearchMatch()
            }
          if !searchQuery.isEmpty {
            Text(searchCounterText)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(searchMatchCount == 0 ? Color.justDanger : Color.justMeta)
              .monospacedDigit()
            Button(action: onPreviousSearchMatch) {
              Image(systemName: "chevron.up")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
            }
            .disabled(searchMatchCount == 0)
            .buttonStyle(.plain)
            .suppressFocusRing()
            .hoverSurface(radius: Radius.sm, opacity: 0.45)
            Button(action: onNextSearchMatch) {
              Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 22)
                .contentShape(Rectangle())
            }
            .disabled(searchMatchCount == 0)
            .buttonStyle(.plain)
            .suppressFocusRing()
            .hoverSurface(radius: Radius.sm, opacity: 0.45)
          }
          Button {
            searchText = ""
            isSearchPresented = false
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(width: 22, height: 22)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .suppressFocusRing()
          .hoverSurface(radius: Radius.pill, opacity: 0.45)
        }
        .padding(.horizontal, 10)
        .frame(width: 360, height: 34)
        .background(Capsule().fill(Color.justControlBackground))
        .overlay(Capsule().stroke(Color.justBorderSoft, lineWidth: 1))
        .onAppear {
          searchFocused = true
        }
      }

      Button {
        appState.assistantEditorPresented = true
      } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.system(size: 17, weight: .medium))
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface()

      Button {
        isSearchPresented.toggle()
        if !isSearchPresented {
          searchText = ""
        }
      } label: {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 18, weight: .medium))
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface()
    }
    .padding(.horizontal, 24)
    .frame(height: 58)
  }

  private var searchCounterText: String {
    guard searchMatchCount > 0, let selectedSearchMatchIndex else {
      return "0/0"
    }
    return "\(selectedSearchMatchIndex + 1)/\(searchMatchCount)"
  }
}

private struct ChatTranscriptView: View {
  @EnvironmentObject private var appState: AppState
  var searchText: String
  var activeSearchMessageId: UUID?

  private var searchQuery: String {
    searchText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isSearching: Bool {
    !searchQuery.isEmpty
  }

  private var hasSearchMatches: Bool {
    appState.messages.contains { $0.matches(searchQuery) }
  }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 18) {
          if appState.messages.isEmpty {
            EmptyConversationView()
          } else if isSearching && !hasSearchMatches {
            EmptySearchResultView(query: searchText)
          }

          if !appState.messages.isEmpty {
            ForEach(appState.messages) { message in
              MessageBubble(message: message, assistantName: appState.selectedAssistant.name)
                .id(message.id)
                .searchHitHighlight(
                  isMatch: isSearching && message.matches(searchQuery),
                  isActive: activeSearchMessageId == message.id
                )
            }
          }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
      }
      .onChange(of: appState.messages.count) {
        if !isSearching, let last = appState.messages.last {
          proxy.scrollTo(last.id, anchor: .bottom)
        }
      }
      .onChange(of: activeSearchMessageId) {
        guard let activeSearchMessageId else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
          proxy.scrollTo(activeSearchMessageId, anchor: .center)
        }
      }
    }
  }
}

private struct EmptySearchResultView: View {
  var query: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("没有找到匹配内容")
          .font(.system(size: 13, weight: .semibold))
        Text(query.trimmingCharacters(in: .whitespacesAndNewlines))
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 12)
    .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(Color.justControlBackground.opacity(0.7))
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .stroke(Color.justBorderSoft, lineWidth: 1)
    )
  }
}

private struct SearchHitHighlight: ViewModifier {
  var isMatch: Bool
  var isActive: Bool

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .fill(highlightFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
          .stroke(highlightStroke, lineWidth: isActive ? 1 : 0)
      )
  }

  private var highlightFill: Color {
    if isActive {
      return Color.justAccent.opacity(0.08)
    }
    if isMatch {
      return Color.justAccent.opacity(0.035)
    }
    return .clear
  }

  private var highlightStroke: Color {
    isActive ? Color.justAccent.opacity(0.45) : .clear
  }
}

extension View {
  fileprivate func searchHitHighlight(isMatch: Bool, isActive: Bool) -> some View {
    modifier(SearchHitHighlight(isMatch: isMatch, isActive: isActive))
  }
}

extension ChatMessage {
  fileprivate func matches(_ query: String) -> Bool {
    let needle = query.localizedLowercase
    let haystacks = [
      content,
      reasoningContent,
      citations.map { "\($0.title) \($0.snippet) \($0.url.absoluteString)" }.joined(
        separator: " "),
    ]
    return haystacks.contains { $0.localizedLowercase.contains(needle) }
  }
}

private struct EmptyConversationView: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 16) {
      AssistantAvatar(name: appState.selectedAssistant.name)
        .frame(width: 54, height: 54)
      Text(appState.selectedAssistant.name)
        .font(.system(size: 22, weight: .bold))
      Text("选择下面的提示词，或直接输入消息开始对话。")
        .font(.system(size: 14))
        .foregroundStyle(.secondary)

      LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 10) {
        ForEach(appState.selectedAssistant.quickTemplates) { template in
          Button {
            appState.composerText = template.prompt + "\n"
          } label: {
            HStack {
              Image(systemName: "sparkle")
                .foregroundStyle(Color.justAccent)
              Text(template.title)
                .foregroundStyle(.primary)
                .lineLimit(1)
              Spacer()
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(
              RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(.ultraThinMaterial)
            )
            .overlay(
              RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
          .hoverSurface(radius: Radius.sm, opacity: 0.6)
        }
      }
      .frame(maxWidth: 560)
    }
    .frame(maxWidth: .infinity, minHeight: 360)
  }
}

private struct MessageBubble: View {
  @EnvironmentObject private var appState: AppState
  var message: ChatMessage
  var assistantName: String

  private var isUser: Bool { message.role == .user }
  private var fontSize: CGFloat { CGFloat(appState.preferences.chatFontSize) }
  private var isDisplayStreaming: Bool {
    message.status == .streaming || appState.displayStreamingMessageIds.contains(message.id)
  }

  var body: some View {
    if isUser {
      HStack(alignment: .top, spacing: 0) {
        Spacer(minLength: 0)
        VStack(alignment: .trailing, spacing: 6) {
          Text(message.createdAt, style: .time)
            .font(.caption2)
            .foregroundStyle(Color.justMeta)
          VStack(alignment: .leading, spacing: 10) {
            if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
              MarkdownText(content: message.content, fontSize: fontSize)
            }
            if !message.attachments.isEmpty {
              MessageAttachmentGrid(attachments: message.attachments)
            }
          }
          .frame(maxWidth: 620, alignment: .leading)
          .padding(.vertical, 12)
          .padding(.horizontal, 16)
          .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
              .fill(Color.justAccent.opacity(0.12))
          )
          .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
              .stroke(Color.justAccent.opacity(0.12), lineWidth: 1)
          )
          .cardShadow()
        }
      }
    } else {
      HStack(alignment: .top, spacing: 12) {
        AssistantAvatar(name: assistantName)
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 8) {
          HStack(spacing: 8) {
            Text("Just Chat")
              .font(.system(size: 13, weight: .semibold))
            if message.status == .streaming {
              ProgressView()
                .controlSize(.small)
            }
            Spacer(minLength: 0)
            Text(message.createdAt, style: .time)
              .font(.caption2)
              .foregroundStyle(Color.justMeta)
            if let usage = message.usage, let total = usage.totalTokens {
              Text("· \(total) tokens")
                .font(.caption2)
                .foregroundStyle(Color.justMeta)
            }
          }

          if !message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ThinkingBlock(
              id: message.id,
              text: message.reasoningContent,
              isStreaming: isDisplayStreaming && message.content.isEmpty
            )
          }

          if !message.citations.isEmpty {
            SearchResultsBlock(citations: message.citations)
          }

          if message.content.isEmpty && message.reasoningContent.isEmpty && message.status == .streaming {
            TypingIndicator()
          } else {
            SmoothStreamingMarkdownView(
              content: message.content,
              isStreaming: isDisplayStreaming,
              fontSize: fontSize
            )
          }

          AssistantMessageFooter(message: message)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

private struct MessageAttachmentGrid: View {
  var attachments: [MessageImage]

  var body: some View {
    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
      ForEach(attachments) { attachment in
        attachmentView(attachment)
      }
    }
  }

  private var columns: [GridItem] {
    [GridItem(.adaptive(minimum: 120, maximum: 220), spacing: 8)]
  }

  @ViewBuilder
  private func attachmentView(_ attachment: MessageImage) -> some View {
    if let image = NSImage(data: attachment.data) {
      Image(nsImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 180, height: 120)
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .stroke(Color.justBorderSoft, lineWidth: 1)
        )
    } else {
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(Color.justControlBackground)
        .frame(width: 180, height: 120)
        .overlay(Image(systemName: "photo"))
    }
  }
}

private struct AssistantMessageFooter: View {
  @EnvironmentObject private var appState: AppState
  var message: ChatMessage
  @State private var copied = false

  var body: some View {
    HStack(spacing: 12) {
      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
          copied = false
        }
      } label: {
        Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 8)
          .frame(height: 26)
          .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
      }
      .disabled(message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface(radius: Radius.sm, opacity: 0.5)

      Button {
        appState.regenerateResponse(messageId: message.id)
      } label: {
        Label("重新生成", systemImage: "arrow.clockwise")
          .labelStyle(.titleAndIcon)
          .padding(.horizontal, 8)
          .frame(height: 26)
          .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
      }
      .disabled(appState.isStreaming || message.status == .streaming)
      .buttonStyle(.plain)
      .suppressFocusRing()
      .hoverSurface(radius: Radius.sm, opacity: 0.5)

      Spacer(minLength: 8)

      if let metricText {
        MetricBadge(text: metricText, detail: metricHelp)
      }
    }
    .font(.system(size: 12, weight: .medium))
    .foregroundStyle(.secondary)
    .padding(.top, 2)
  }

  private var metricText: String? {
    if let usage = message.usage {
      let input = usage.inputTokens
      let output = usage.outputTokens
      let total = usage.totalTokens ?? [input, output].compactMap { $0 }.reduce(0, +)
      var parts: [String] = []
      if total > 0 {
        parts.append("Tokens: \(total)")
      }
      if let input {
        parts.append("↑\(input)")
      }
      if let output {
        parts.append("↓\(output)")
      }
      if !parts.isEmpty {
        return parts.joined(separator: " ")
      }
    }
    if let latency = message.firstTokenLatencyMS {
      return "首字时延 \(latency) ms"
    }
    return nil
  }

  private var metricHelp: String? {
    var parts: [String] = []
    if let latency = message.firstTokenLatencyMS {
      parts.append("首字时延 \(latency) ms")
    }
    if let speed = message.tokensPerSecond {
      parts.append("每秒 \(speed) tokens")
    }
    return parts.isEmpty ? nil : parts.joined(separator: " | ")
  }
}

private struct MetricBadge: View {
  var text: String
  var detail: String?
  @State private var isHovering = false

  var body: some View {
    Text(text)
      .foregroundStyle(Color.justMeta)
      .padding(.horizontal, 8)
      .frame(height: 26)
      .background(
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
          .fill(Color.justControlBackground.opacity(isHovering ? 0.75 : 0))
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
          .stroke(Color.justBorderSoft.opacity(isHovering ? 1 : 0), lineWidth: 1)
      )
      .overlay(alignment: .topTrailing) {
        if isHovering {
          Text(detail ?? text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(
              RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(.regularMaterial)
            )
            .overlay(
              RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
            )
            .raisedShadow()
            .offset(y: -36)
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomTrailing)))
            .zIndex(20)
        }
      }
      .onHover { isHovering = $0 }
      .animation(.easeOut(duration: 0.14), value: isHovering)
  }
}

private struct SearchResultsBlock: View {
  var citations: [Citation]
  @State private var isExpanded = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        withAnimation(.easeOut(duration: 0.16)) {
          isExpanded.toggle()
        }
      } label: {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.justMeta)
          Text("网络搜索")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
          Text("\(citations.count) 个搜索结果")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
          Spacer(minLength: 8)
          Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.justMeta)
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if isExpanded {
        Divider()
        VStack(alignment: .leading, spacing: 0) {
          ForEach(citations.indices, id: \.self) { index in
            SearchResultRow(index: index + 1, citation: citations[index])
            if index < citations.count - 1 {
              Divider()
                .padding(.leading, 40)
            }
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .fill(Color.justControlBackground.opacity(0.58))
    )
    .overlay(
      RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
        .stroke(Color.justBorderSoft, lineWidth: 1)
    )
  }
}

private struct SearchResultRow: View {
  var index: Int
  var citation: Citation

  private var domain: String {
    citation.url.host ?? citation.url.absoluteString
  }

  var body: some View {
    Link(destination: citation.url) {
      HStack(alignment: .top, spacing: 10) {
        Text("\(index)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
          .frame(width: 20, height: 20)
          .background(Circle().fill(Color.justWindowBackground.opacity(0.8)))

        VStack(alignment: .leading, spacing: 3) {
          Text(citation.title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .lineLimit(1)

          if !citation.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(citation.snippet)
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }

          Text(domain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.justAccent)
            .lineLimit(1)
        }

        Spacer(minLength: 8)
        Image(systemName: "arrow.up.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundStyle(Color.justMeta)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 9)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(citation.url.absoluteString)
  }
}

struct CitationChip: View {
  var citation: Citation

  private var domain: String {
    citation.url.host ?? citation.url.absoluteString
  }

  var body: some View {
    Link(destination: citation.url) {
      HStack(spacing: 5) {
        Image(systemName: "link")
          .font(.system(size: 10, weight: .semibold))
        Text(citation.title)
          .lineLimit(1)
        if !domain.isEmpty {
          Text(domain)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .font(.caption)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background(Capsule().fill(Color.justControlBackground))
      .overlay(Capsule().stroke(Color.justBorderSoft, lineWidth: 1))
      .hoverSurface(radius: Radius.pill, opacity: 0.4)
    }
  }
}

/// Simple wrapping layout for citation chips.
struct FlexWrap: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let width = proposal.width ?? .infinity
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > width && x > 0 {
        x = 0
        y += lineHeight + spacing
        lineHeight = 0
      }
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
    return CGSize(width: min(width, 10_000), height: y + lineHeight)
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var lineHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > bounds.maxX && x > bounds.minX {
        x = bounds.minX
        y += lineHeight + spacing
        lineHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }
  }
}

struct ThinkingBlock: View {
    var id: UUID
    var text: String
    var isStreaming: Bool
    var collapseWhenStreamingEnds: Bool
    @State private var isExpanded: Bool

    init(id: UUID, text: String, isStreaming: Bool, collapseWhenStreamingEnds: Bool = false) {
        self.id = id
        self.text = text
        self.isStreaming = isStreaming
        self.collapseWhenStreamingEnds = collapseWhenStreamingEnds
        _isExpanded = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 13, weight: .medium))
                    Text(isStreaming ? "思考中" : "思考")
                        .font(.system(size: 13, weight: .semibold))
                    if isStreaming {
                        MiniTypingIndicator()
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isExpanded {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Color.justControlBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .onChange(of: isStreaming) {
            guard collapseWhenStreamingEnds, !isStreaming else { return }
            isExpanded = false
        }
    }
}

private struct MiniTypingIndicator: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.18)) { context in
      let activeIndex = Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
      HStack(spacing: 4) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(index == activeIndex ? Color.secondary : Color.secondary.opacity(0.35))
            .frame(width: 4, height: 4)
        }
      }
    }
    .frame(width: 22, height: 10)
  }
}

private struct TypingIndicator: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 0.18)) { context in
      let activeIndex = Int(context.date.timeIntervalSinceReferenceDate * 4) % 3
      HStack(spacing: 7) {
        ForEach(0..<3, id: \.self) { index in
          Circle()
            .fill(index == activeIndex ? Color.justAccent : Color.secondary.opacity(0.35))
            .frame(width: 7, height: 7)
            .scaleEffect(index == activeIndex ? 1.05 : 0.92)
        }
      }
      .frame(height: 24, alignment: .leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityLabel("正在生成")
  }
}

private struct ReasoningEffortMenu: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    Menu {
      Section(endpointTitle) {
        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
          Button {
            appState.setSelectedAssistantReasoningEffort(effort)
          } label: {
            if effort == appState.selectedAssistant.reasoningEffort {
              Label(effort.displayName, systemImage: "checkmark")
            } else {
              Text(effort.displayName)
            }
          }
        }
      }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "brain.head.profile")
          .font(.system(size: 14, weight: .semibold))
        Text("思考等级")
          .font(.system(size: 12, weight: .semibold))
        Text(appState.selectedAssistant.reasoningEffort.displayName)
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(
            appState.selectedAssistant.reasoningEffort.apiValue == nil ? .secondary : Color.justAccent)
      }
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(Capsule().fill(Color.justControlBackground))
      .overlay(Capsule().stroke(Color.justBorderSoft, lineWidth: 1))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .suppressFocusRing()
    .hoverSurface(radius: Radius.pill, opacity: 0.45)
    .help(endpointHelp)
  }

  private var endpointTitle: String {
    switch appState.activeProvider.kind {
    case .openAIChatCompletions:
      "Reasoning Effort"
    case .openAIResponses:
      "Responses Reasoning"
    case .anthropicMessages:
      "Thinking Budget"
    }
  }

  private var endpointHelp: String {
    switch appState.activeProvider.kind {
    case .openAIChatCompletions:
      "默认不传思考参数；关闭会按兼容端点显式禁用"
    case .openAIResponses:
      "默认不传 reasoning；关闭使用 reasoning.effort = none"
    case .anthropicMessages:
      "默认不传 thinking；低/中/高使用 thinking budget"
    }
  }
}

private struct ComposerView: View {
  @EnvironmentObject private var appState: AppState
  @State private var focused = false
  @State private var focusToken = UUID()

  var body: some View {
    VStack(spacing: 10) {
      if let status = appState.statusMessage, !status.isEmpty {
        HStack(spacing: 8) {
          Image(systemName: "info.circle")
          Text(status)
            .lineLimit(2)
          Spacer()
          Button("关闭") {
            appState.clearStatusMessage()
          }
          .buttonStyle(.plain)
          .focusable(false)
          .hoverSurface(radius: Radius.sm, opacity: 0.45)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(.ultraThinMaterial)
        )
        .overlay(
          RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .padding(.horizontal, 36)
      }

      HStack(spacing: 8) {
        ComposerIconButton(icon: "paperclip") {
          pickAttachments()
        }
        .help("附件")
        ComposerIconButton(icon: "globe", isActive: appState.isWebSearchEnabled) {
          appState.isWebSearchEnabled.toggle()
        }
        .help("网络搜索")

        ReasoningEffortMenu()

        Spacer()

        if appState.isStreaming {
          Button {
            appState.stopStreaming()
          } label: {
            Image(systemName: "stop.circle.fill")
              .font(.system(size: 20))
              .foregroundStyle(Color.justDanger)
              .frame(width: 32, height: 32)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .hoverSurface(radius: Radius.sm)
        }
      }
      .font(.system(size: 17, weight: .medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 40)

      if !appState.composerAttachments.isEmpty {
        ScrollView(.horizontal) {
          HStack(spacing: 8) {
            ForEach(appState.composerAttachments) { attachment in
              attachmentThumbnail(attachment)
            }
          }
          .padding(.horizontal, 40)
        }
      }

      HStack(alignment: .bottom, spacing: 10) {
        ZStack(alignment: .topLeading) {
          if appState.composerText.isEmpty {
            Text("在这里输入消息，按 Enter 发送")
              .font(.system(size: 16))
              .foregroundStyle(.secondary.opacity(0.75))
              .padding(.horizontal, 18)
              .padding(.vertical, 14)
          }
          PasteAwareComposerTextView(
            text: $appState.composerText,
            focusToken: focusToken,
            onFocusChange: { focused = $0 },
            onSubmit: {
              appState.sendMessage()
              focusToken = UUID()
            },
            onPasteImages: { images in
              appState.composerAttachments.append(contentsOf: images)
            }
          )
          .frame(height: composerTextHeight)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
        }

        Button {
          appState.sendMessage()
          focusToken = UUID()
        } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
              Circle()
                .fill(
                  canSend
                    ? AnyShapeStyle(LinearGradient.justAccent)
                    : AnyShapeStyle(Color.secondary.opacity(0.3)))
            )
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .hoverSurface(radius: Radius.pill, opacity: canSend ? 0.35 : 0)
        .padding(.trailing, 10)
        .padding(.bottom, 9)
      }
      .background(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .fill(.regularMaterial)
      )
      .background(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .fill(Color.justInputBackground.opacity(0.4))
      )
      .overlay(
        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
          .stroke(
            focused ? Color.justAccent.opacity(0.5) : Color.justBorderSoft,
            lineWidth: focused ? 2 : 1)
      )
      .shadow(color: focused ? Color.justAccent.opacity(0.15) : .clear, radius: 10, x: 0, y: 0)
      .raisedShadow()
      .padding(.horizontal, 36)
      .padding(.bottom, 18)
    }
    .padding(.top, 10)
    .background(Color.justWindowBackground)
    .onPasteCommand(of: [.image, .png, .jpeg, .gif, .webP, .tiff, .fileURL, .url]) {
      providers in
      pasteImages(from: providers)
    }
    .onAppear {
      focusToken = UUID()
    }
  }

  private var canSend: Bool {
    (!appState.composerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || !appState.composerAttachments.isEmpty)
      && !appState.isStreaming
  }

  private var composerTextHeight: CGFloat {
    let lineCount = max(1, appState.composerText.components(separatedBy: .newlines).count)
    return min(CGFloat(lineCount) * 22 + 8, 96)
  }

  private var imageTypes: [(UTType, String)] {
    [
      (.png, "image/png"),
      (.jpeg, "image/jpeg"),
      (.gif, "image/gif"),
      (.webP, "image/webp"),
      (.tiff, "image/tiff"),
    ]
  }

  private func pickAttachments() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.png, .jpeg, .gif, .webP, .tiff]
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.begin { response in
      guard response == .OK else { return }
      for url in panel.urls {
        guard let data = try? Data(contentsOf: url) else { continue }
        let mimeType: String = {
          switch url.pathExtension.lowercased() {
          case "png": return "image/png"
          case "gif": return "image/gif"
          case "webp": return "image/webp"
          case "tiff", "tif": return "image/tiff"
          default: return "image/jpeg"
          }
        }()
        appState.composerAttachments.append(
          MessageImage(id: UUID(), data: data, mimeType: mimeType)
        )
      }
    }
  }

  private func pasteImages(from providers: [NSItemProvider]) {
    for provider in providers {
      if let match = imageTypes.first(where: {
        provider.hasItemConformingToTypeIdentifier($0.0.identifier)
      }) {
        provider.loadDataRepresentation(forTypeIdentifier: match.0.identifier) { data, _ in
          guard let data else { return }
          DispatchQueue.main.async {
            appState.composerAttachments.append(
              MessageImage(id: UUID(), data: data, mimeType: match.1)
            )
          }
        }
      } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
          guard let data,
            let text = String(data: data, encoding: .utf8),
            let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let image = MessageImage.fromFileURL(url)
          else { return }
          DispatchQueue.main.async {
            appState.composerAttachments.append(image)
          }
        }
      } else if provider.canLoadObject(ofClass: NSURL.self) {
        provider.loadObject(ofClass: NSURL.self) { object, _ in
          guard let url = object as? URL,
            let image = MessageImage.fromFileURL(url)
          else { return }
          DispatchQueue.main.async {
            appState.composerAttachments.append(image)
          }
        }
      } else if provider.canLoadObject(ofClass: NSImage.self) {
        provider.loadObject(ofClass: NSImage.self) { object, _ in
          guard let image = object as? NSImage,
            let data = image.tiffRepresentation
          else { return }
          DispatchQueue.main.async {
            appState.composerAttachments.append(
              MessageImage(id: UUID(), data: data, mimeType: "image/tiff")
            )
          }
        }
      }
    }
  }

  private func attachmentThumbnail(_ attachment: MessageImage) -> some View {
    ZStack(alignment: .topTrailing) {
      if let nsImage = NSImage(data: attachment.data) {
        Image(nsImage: nsImage)
          .resizable()
          .aspectRatio(contentMode: .fill)
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
      } else {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
          .fill(Color.justInputBackground)
          .frame(width: 56, height: 56)
          .overlay(Image(systemName: "photo"))
      }

      Button {
        appState.composerAttachments.removeAll { $0.id == attachment.id }
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 14))
          .foregroundStyle(.white, Color.black.opacity(0.5))
      }
      .buttonStyle(.plain)
      .hoverSurface(radius: Radius.pill, opacity: 0.45)
      .offset(x: 6, y: -6)
    }
  }
}

private struct PasteAwareComposerTextView: NSViewRepresentable {
  @Binding var text: String
  var focusToken: UUID
  var onFocusChange: (Bool) -> Void
  var onSubmit: () -> Void
  var onPasteImages: ([MessageImage]) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = NSScrollView()
    scrollView.drawsBackground = false
    scrollView.borderType = .noBorder
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true

    let textView = ComposerNSTextView()
    textView.delegate = context.coordinator
    textView.onSubmit = onSubmit
    textView.onPasteImages = onPasteImages
    textView.string = text
    textView.font = .systemFont(ofSize: 16)
    textView.textColor = .labelColor
    textView.drawsBackground = false
    textView.isRichText = false
    textView.importsGraphics = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.autoresizingMask = [.width]

    scrollView.documentView = textView
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? ComposerNSTextView else { return }
    textView.onSubmit = onSubmit
    textView.onPasteImages = onPasteImages
    if textView.string != text {
      textView.string = text
    }
    if context.coordinator.focusToken != focusToken {
      context.coordinator.focusToken = focusToken
      DispatchQueue.main.async {
        textView.window?.makeFirstResponder(textView)
      }
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: PasteAwareComposerTextView
    var focusToken: UUID?

    init(_ parent: PasteAwareComposerTextView) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
    }

    func textDidBeginEditing(_ notification: Notification) {
      parent.onFocusChange(true)
    }

    func textDidEndEditing(_ notification: Notification) {
      parent.onFocusChange(false)
    }
  }
}

private final class ComposerNSTextView: NSTextView {
  var onSubmit: () -> Void = {}
  var onPasteImages: ([MessageImage]) -> Void = { _ in }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    if flags.contains(.command),
      event.charactersIgnoringModifiers?.lowercased() == "v"
    {
      let images = pastedImages(from: .general)
      if !images.isEmpty {
        onPasteImages(images)
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }

  override func keyDown(with event: NSEvent) {
    let isReturn = event.keyCode == 36 || event.keyCode == 76
    let wantsNewline = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(
      .shift)
    if isReturn && !wantsNewline {
      onSubmit()
      return
    }
    super.keyDown(with: event)
  }

  override func paste(_ sender: Any?) {
    let images = pastedImages(from: .general)
    if !images.isEmpty {
      onPasteImages(images)
      return
    }
    super.paste(sender)
  }

  override func readSelection(from pasteboard: NSPasteboard) -> Bool {
    let images = pastedImages(from: pasteboard)
    if !images.isEmpty {
      onPasteImages(images)
      return true
    }
    return super.readSelection(from: pasteboard)
  }

  private func pastedImages(from pasteboard: NSPasteboard) -> [MessageImage] {
    let dataTypes: [(NSPasteboard.PasteboardType, String)] = [
      (.png, "image/png"),
      (NSPasteboard.PasteboardType("public.png"), "image/png"),
      (NSPasteboard.PasteboardType("public.jpeg"), "image/jpeg"),
      (NSPasteboard.PasteboardType("public.jpg"), "image/jpeg"),
      (NSPasteboard.PasteboardType("com.compuserve.gif"), "image/gif"),
      (NSPasteboard.PasteboardType("org.webmproject.webp"), "image/webp"),
      (.tiff, "image/tiff"),
      (NSPasteboard.PasteboardType("public.tiff"), "image/tiff"),
      (NSPasteboard.PasteboardType("public.tif"), "image/tiff"),
      (NSPasteboard.PasteboardType("NSTIFFPboardType"), "image/tiff"),
      (NSPasteboard.PasteboardType("NeXT TIFF v4.0 pasteboard type"), "image/tiff"),
      (NSPasteboard.PasteboardType("com.apple.tiff"), "image/tiff"),
    ]

    var images: [MessageImage] = []
    for item in pasteboard.pasteboardItems ?? [] {
      var appended = false
      for (type, mimeType) in dataTypes {
        if let data = item.data(forType: type), !data.isEmpty {
          images.append(MessageImage(id: UUID(), data: data, mimeType: mimeType))
          appended = true
          break
        }
      }
      if appended { continue }
      if let file = item.string(forType: .fileURL),
        let url = URL(string: file),
        let image = MessageImage.fromFileURL(url)
      {
        images.append(image)
      } else if let file = item.string(forType: .URL),
        let url = URL(string: file),
        let image = MessageImage.fromFileURL(url)
      {
        images.append(image)
      }
    }

    if images.isEmpty {
      for (type, mimeType) in dataTypes {
        guard let data = pasteboard.data(forType: type), !data.isEmpty else { continue }
        if mimeType == "image/tiff", let image = NSImage(data: data),
          let tiffData = image.tiffRepresentation
        {
          images.append(MessageImage(id: UUID(), data: tiffData, mimeType: mimeType))
          break
        }
        if NSImage(data: data) != nil {
          images.append(MessageImage(id: UUID(), data: data, mimeType: mimeType))
          break
        }
      }
    }

    if images.isEmpty,
      let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    {
      images.append(contentsOf: urls.compactMap(MessageImage.fromFileURL))
    }

    if images.isEmpty,
      let files = pasteboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType"))
        as? [String]
    {
      images.append(
        contentsOf: files.compactMap { MessageImage.fromFileURL(URL(fileURLWithPath: $0)) })
    }

    if images.isEmpty,
      let image = NSImage(pasteboard: pasteboard),
      let data = image.tiffRepresentation
    {
      images.append(MessageImage(id: UUID(), data: data, mimeType: "image/tiff"))
    }
    return images
  }

}

private extension MessageImage {
  static func fromFileURL(_ url: URL) -> MessageImage? {
    guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
    let ext = url.pathExtension.lowercased()
    let mimeType: String
    switch ext {
    case "png": mimeType = "image/png"
    case "jpg", "jpeg": mimeType = "image/jpeg"
    case "gif": mimeType = "image/gif"
    case "webp": mimeType = "image/webp"
    case "tiff", "tif": mimeType = "image/tiff"
    default: return nil
    }
    return MessageImage(id: UUID(), data: data, mimeType: mimeType)
  }
}

private struct ComposerIconButton: View {
  var icon: String
  var isActive: Bool = false
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(isActive ? Color.justAccent : .secondary)
        .frame(width: 32, height: 32)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .hoverSurface(radius: Radius.sm, opacity: 0.6)
  }
}

struct AssistantEditor: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          AssistantAvatar(name: appState.selectedAssistant.name)
            .frame(width: 44, height: 44)
          TextField("助手名称", text: assistantBinding(\.name))
            .textFieldStyle(.plain)
            .font(.system(size: 24, weight: .bold))
          Spacer()
          Button("保存") {
            appState.persistConfiguration()
          }
          .buttonStyle(.borderedProminent)
          .tint(Color.justAccent)
        }

        Card {
          VStack(alignment: .leading, spacing: 12) {
            editorTitle("模型", icon: "cube")
            Picker("模型服务", selection: providerBinding) {
              ForEach(appState.providers) { provider in
                Text(provider.name).tag(provider.id)
              }
            }
            Picker("模型", selection: assistantBinding(\.modelId)) {
              ForEach(appState.activeProvider.models, id: \.self) { model in
                Text(model).tag(model)
              }
            }
          }
        }

        Card {
          VStack(alignment: .leading, spacing: 10) {
            editorTitle("系统提示词", icon: "text.alignleft")
            TextEditor(text: assistantBinding(\.systemPrompt))
              .font(.system(size: 14))
              .frame(minHeight: 180)
              .scrollContentBackground(.hidden)
              .padding(8)
              .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                  .fill(Color.justInputBackground)
              )
              .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                  .stroke(Color.justBorderSoft, lineWidth: 1)
              )
          }
        }

        Card {
          VStack(alignment: .leading, spacing: 10) {
            editorTitle("首页提示词", icon: "sparkles")
            PromptTemplateEditor()
          }
        }

        Card {
          VStack(alignment: .leading, spacing: 12) {
            editorTitle("参数", icon: "slider")
            HStack {
              Text("Temperature")
              Slider(value: assistantBinding(\.temperature), in: 0...2)
                .tint(Color.justAccent)
              Text(
                appState.selectedAssistant.temperature.formatted(
                  .number.precision(.fractionLength(1)))
              )
              .foregroundStyle(.secondary)
            }
            Stepper(
              "Max tokens: \(appState.selectedAssistant.maxTokens)",
              value: assistantBinding(\.maxTokens), in: 256...32768, step: 256)
            VStack(alignment: .leading, spacing: 4) {
              Stepper(
                appState.selectedAssistant.contextMessageCount == 0
                  ? "上下文条数：不传历史"
                  : "上下文条数：\(appState.selectedAssistant.contextMessageCount)",
                value: assistantBinding(\.contextMessageCount),
                in: 0...100,
                step: 2
              )
              Text("仅将最近 N 条历史消息作为上下文发送；0 = 只发送当前消息。")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .padding(30)
      .frame(maxWidth: 920, alignment: .leading)
    }
    .background(Color.justWindowBackground)
  }

  private func editorTitle(_ title: String, icon: String) -> some View {
    Label(title, systemImage: icon)
      .font(.system(size: 15, weight: .bold))
  }

  private var providerBinding: Binding<UUID> {
    Binding(
      get: { appState.selectedAssistant.providerId ?? appState.selectedProviderId },
      set: { appState.bindSelectedAssistantToProvider($0) }
    )
  }

  private func assistantBinding<Value>(_ keyPath: WritableKeyPath<AssistantProfile, Value>)
    -> Binding<Value>
  {
    Binding(
      get: { appState.selectedAssistant[keyPath: keyPath] },
      set: { newValue in
        guard let index = appState.selectedAssistantIndex else { return }
        appState.assistants[index][keyPath: keyPath] = newValue
      }
    )
  }
}

private struct PromptTemplateEditor: View {
  @EnvironmentObject private var appState: AppState

  var body: some View {
    VStack(spacing: 10) {
      ForEach(templateIndices, id: \.self) { index in
        HStack(spacing: 10) {
          TextField("标题", text: templateBinding(index, \.title))
            .textFieldStyle(.roundedBorder)
            .frame(width: 150)
          TextField("提示词", text: templateBinding(index, \.prompt), axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...3)
          Button {
            removeTemplate(at: index)
          } label: {
            Image(systemName: "minus.circle")
              .foregroundStyle(Color.justDanger)
              .frame(width: 28, height: 28)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .hoverSurface(radius: Radius.pill, opacity: 0.45)
          .disabled(templateIndices.count <= 1)
        }
      }

      Button {
        addTemplate()
      } label: {
        Label("添加提示词", systemImage: "plus")
      }
      .buttonStyle(.bordered)
      .hoverSurface(radius: Radius.sm, opacity: 0.35)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var templateIndices: [Int] {
    guard let assistantIndex = appState.selectedAssistantIndex else { return [] }
    return Array(appState.assistants[assistantIndex].quickTemplates.indices)
  }

  private func templateBinding(_ index: Int, _ keyPath: WritableKeyPath<PromptTemplate, String>)
    -> Binding<String>
  {
    Binding(
      get: {
        guard let assistantIndex = appState.selectedAssistantIndex,
          appState.assistants[assistantIndex].quickTemplates.indices.contains(index)
        else { return "" }
        return appState.assistants[assistantIndex].quickTemplates[index][keyPath: keyPath]
      },
      set: { value in
        guard let assistantIndex = appState.selectedAssistantIndex,
          appState.assistants[assistantIndex].quickTemplates.indices.contains(index)
        else { return }
        appState.assistants[assistantIndex].quickTemplates[index][keyPath: keyPath] = value
      }
    )
  }

  private func addTemplate() {
    guard let assistantIndex = appState.selectedAssistantIndex else { return }
    appState.assistants[assistantIndex].quickTemplates.append(
      PromptTemplate(id: UUID(), title: "新提示词", prompt: ""))
  }

  private func removeTemplate(at index: Int) {
    guard let assistantIndex = appState.selectedAssistantIndex,
      appState.assistants[assistantIndex].quickTemplates.indices.contains(index)
    else { return }
    appState.assistants[assistantIndex].quickTemplates.remove(at: index)
  }
}

struct AssistantAvatar: View {
  var name: String

  private static let palette: [Color] = [
    .justAccent, .blue, .pink, .green, .orange, .purple,
  ]

  private var baseColor: Color {
    Self.palette[Self.stablePaletteIndex(for: name)]
  }

  private static func stablePaletteIndex(for value: String) -> Int {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1_099_511_628_211
    }
    return Int(hash % UInt64(palette.count))
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [baseColor, baseColor.opacity(0.75)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
      Circle()
        .stroke(Color.white.opacity(0.25), lineWidth: 1)
      Text(String(name.first ?? "助"))
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(.white)
    }
  }
}
