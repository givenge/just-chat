import AppKit
import Combine
import Foundation

private struct ModelListResponse: Decodable {
  var data: [ModelItem]

  struct ModelItem: Decodable {
    var id: String
  }
}

private actor TextAccumulator {
  private var value = ""

  func append(_ text: String) {
    value += text
  }

  func text() -> String {
    value
  }
}

struct ThinkTagParser {
  private enum Mode {
    case content
    case reasoning
  }

  private var mode: Mode = .content
  private var pending = ""

  mutating func append(_ text: String) -> (content: String, reasoning: String) {
    pending += text
    var content = ""
    var reasoning = ""

    parseLoop: while !pending.isEmpty {
      switch mode {
      case .content:
        if let range = pending.range(of: "<think>", options: .caseInsensitive) {
          content += String(pending[..<range.lowerBound])
          pending.removeSubrange(..<range.upperBound)
          mode = .reasoning
        } else {
          let count = safeEmitCount(keepingPossiblePrefixOf: "<think>")
          guard count > 0 else { break parseLoop }
          content += String(pending.prefix(count))
          pending.removeFirst(count)
        }
      case .reasoning:
        if let range = pending.range(of: "</think>", options: .caseInsensitive) {
          reasoning += String(pending[..<range.lowerBound])
          pending.removeSubrange(..<range.upperBound)
          mode = .content
        } else {
          let count = safeEmitCount(keepingPossiblePrefixOf: "</think>")
          guard count > 0 else { break parseLoop }
          reasoning += String(pending.prefix(count))
          pending.removeFirst(count)
        }
      }
    }

    return (content, reasoning)
  }

  mutating func finish() -> (content: String, reasoning: String) {
    defer { pending = "" }
    switch mode {
    case .content:
      return (pending, "")
    case .reasoning:
      return ("", pending)
    }
  }

  private func safeEmitCount(keepingPossiblePrefixOf tag: String) -> Int {
    let lowercased = pending.lowercased()
    let maxKeep = min(max(tag.count - 1, 0), lowercased.count)
    guard maxKeep > 0 else { return pending.count }

    var keepCount = 0
    for length in stride(from: maxKeep, through: 1, by: -1) {
      if tag.hasPrefix(String(lowercased.suffix(length))) {
        keepCount = length
        break
      }
    }
    return pending.count - keepCount
  }
}

@MainActor
final class AppState: ObservableObject {
  @Published var rootSection: RootSection = .home
  @Published var homeSidebarTab: HomeSidebarTab = .assistants
  @Published var conversations: [Conversation]
  @Published var selectedConversationId: UUID?
  @Published var messages: [ChatMessage]
  @Published var assistants: [AssistantProfile]
  @Published var providers: [ModelProvider]
  @Published var selectedAssistantId: UUID
  @Published var selectedProviderId: UUID
  @Published var isWebSearchEnabled = false
  @Published var composerText = ""
  @Published var composerAttachments: [MessageImage] = []
  @Published var isStreaming = false
  @Published var statusMessage: String?
  @Published var selectedSettingsPane: SettingsPane = .providers
  @Published var searchSettings: SearchSettings = .default
  @Published var preferences: AppPreferences = .default
  @Published var assistantEditorPresented = false
  @Published var displayStreamingMessageIds: Set<UUID> = []
  @Published var hotKeyRegistrationResults = HotKeyRegistrationResults()

  let quickAssistantController = QuickAssistantController()
  let selectionAssistantController = SelectionAssistantController()
  let hotKeyCenter = GlobalHotKeyCenter()

  private var store: SQLiteStore?
  private var currentTask: Task<Void, Never>?
  private var responseStartTimes: [UUID: Date] = [:]
  private var statusClearTask: Task<Void, Never>?
  private var statusMessageVersion = 0
  private var hotKeysStarted = false
  private var thinkTagParsers: [UUID: ThinkTagParser] = [:]
  private var pendingContentDeltas: [UUID: String] = [:]
  private var pendingReasoningDeltas: [UUID: String] = [:]
  private var pendingStreamCharacterCounts: [UUID: Int] = [:]
  private var lastStreamFlushTimes: [UUID: Date] = [:]
  private var streamFlushTasks: [UUID: Task<Void, Never>] = [:]
  private var streamPersistTasks: [UUID: Task<Void, Never>] = [:]
  private var displayStreamingTasks: [UUID: Task<Void, Never>] = [:]

  init() {
    let fallbackProviders = Defaults.providers()
    let fallbackAssistants = Defaults.assistants(primaryProviderId: fallbackProviders[0].id)
    self.providers = fallbackProviders
    self.assistants = fallbackAssistants
    self.conversations = []
    self.selectedConversationId = nil
    self.selectedAssistantId = fallbackAssistants[0].id
    self.selectedProviderId = fallbackProviders[0].id
    self.messages = []

    do {
      let store = SQLiteStore(path: try Self.databasePath())
      try store.open()
      self.store = store
      try loadOrSeed(
        from: store, fallbackProviders: fallbackProviders, fallbackAssistants: fallbackAssistants)
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  var selectedAssistant: AssistantProfile {
    assistants.first(where: { $0.id == selectedAssistantId }) ?? assistants[0]
  }

  var selectedProvider: ModelProvider {
    providers.first(where: { $0.id == selectedProviderId }) ?? providers[0]
  }

  var activeProvider: ModelProvider {
    provider(for: selectedAssistant)
  }

  var selectedAssistantIndex: Int? {
    assistants.firstIndex(where: { $0.id == selectedAssistantId })
  }

  var selectedModelSupportsVision: Bool {
    activeProvider.visionModels.contains(selectedAssistant.modelId)
  }

  var defaultAssistantModelSelection: (provider: ModelProvider, modelId: String) {
    let fallbackProvider = selectedProvider
    return resolvedModelSelection(
      providerId: preferences.defaultAssistantProviderId,
      modelId: preferences.defaultAssistantModelId,
      fallbackProvider: fallbackProvider,
      fallbackModelId: fallbackProvider.defaultModel
    )
  }

  var quickModelSelection: (provider: ModelProvider, modelId: String) {
    resolvedModelSelection(
      providerId: preferences.quickModelProviderId,
      modelId: preferences.quickModelId,
      fallbackProvider: activeProvider,
      fallbackModelId: selectedAssistant.modelId
    )
  }

  var translationModelSelection: (provider: ModelProvider, modelId: String) {
    resolvedModelSelection(
      providerId: preferences.translationModelProviderId,
      modelId: preferences.translationModelId,
      fallbackProvider: activeProvider,
      fallbackModelId: selectedAssistant.modelId
    )
  }

  func setStatusMessage(_ message: String?, autoClear: Bool = false) {
    statusMessageVersion += 1
    let version = statusMessageVersion
    statusClearTask?.cancel()
    statusMessage = message
    guard autoClear, let message, !message.isEmpty else { return }
    statusClearTask = Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      await MainActor.run {
        guard let self, self.statusMessageVersion == version else { return }
        self.statusMessage = nil
      }
    }
  }

  func clearStatusMessage() {
    statusClearTask?.cancel()
    statusMessageVersion += 1
    statusMessage = nil
  }

  @discardableResult
  func startHotKeys() -> HotKeyRegistrationResults {
    hotKeysStarted = true
    let results = hotKeyCenter.registerHotKeys(
      preferences: preferences,
      quick: { [weak self] in
        self?.toggleQuickAssistant()
      },
      selection: { [weak self] in
        self?.toggleSelectionAssistant()
      }
    )
    hotKeyRegistrationResults = results
    return results
  }

  func selectAssistant(_ assistantId: UUID) {
    guard assistants.contains(where: { $0.id == assistantId }) else { return }
    selectedAssistantId = assistantId
    let assistant = selectedAssistant
    selectedProviderId = assistant.providerId ?? selectedProviderId
    ensureConversationForSelectedAssistant()
  }

  func createConversation() {
    do {
      let conversation = try store?.createConversation(
        title: selectedAssistant.name, assistantId: selectedAssistantId)
      reloadConversations(keepingSelection: conversation?.id)
      homeSidebarTab = .topics
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func renameConversation(id: UUID, title: String) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    do {
      try store?.updateConversationTitle(id: id, title: trimmed)
      reloadConversations(keepingSelection: id)
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func deleteConversation(id: UUID) {
    do {
      try store?.deleteConversation(id: id)
      if selectedConversationId == id { selectedConversationId = nil }
      conversations = try store?.listConversations() ?? conversations
      // Prefer another topic for the current assistant; otherwise start a fresh one.
      if let next = conversations.first(where: { $0.assistantId == selectedAssistantId }) {
        selectedConversationId = next.id
      } else {
        let conv = try store?.createConversation(
          title: selectedAssistant.name, assistantId: selectedAssistantId)
        conversations = try store?.listConversations() ?? conversations
        selectedConversationId = conv?.id
      }
      loadSelectedConversationMessages()
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func addAssistant() {
    let selection = defaultAssistantModelSelection
    let provider = selection.provider
    let assistant = AssistantProfile(
      id: UUID(),
      name: "新助手",
      systemPrompt: "你是一个清晰、直接、注重事实的桌面 AI 助手。",
      providerId: provider.id,
      modelId: selection.modelId,
      temperature: 0.7,
      maxTokens: 4096,
      isWebSearchEnabled: false,
      reasoningEffort: preferences.defaultAssistantReasoningEffort,
      quickTemplates: [
        PromptTemplate(id: UUID(), title: "翻译", prompt: "翻译为简体中文："),
        PromptTemplate(id: UUID(), title: "总结", prompt: "总结以下内容："),
      ]
    )
    assistants.append(assistant)
    persistConfiguration()
    selectAssistant(assistant.id)
    rootSection = .home
  }

  func deleteSelectedAssistant() {
    guard assistants.count > 1,
      let index = selectedAssistantIndex
    else { return }
    let removed = assistants.remove(at: index)
    if selectedAssistantId == removed.id {
      selectedAssistantId = assistants[max(0, index - 1)].id
    }
    persistConfiguration()
    selectAssistant(selectedAssistantId)
  }

  func clearTopicsForSelectedAssistant() {
    do {
      let topicsToDelete = conversations.filter { $0.assistantId == selectedAssistantId }
      for topic in topicsToDelete {
        try store?.deleteConversation(id: topic.id)
      }
      conversations = try store?.listConversations() ?? []
      let newConversation = try store?.createConversation(
        title: selectedAssistant.name, assistantId: selectedAssistantId)
      conversations = try store?.listConversations() ?? []
      selectedConversationId = newConversation?.id
      loadSelectedConversationMessages()
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func moveAssistant(from source: IndexSet, to destination: Int) {
    assistants.move(fromOffsets: source, toOffset: destination)
    persistConfiguration()
  }

  func addProvider(type: ProviderCatalogType, name: String) {
    let models = type.defaultModels
    let provider = ModelProvider(
      id: UUID(),
      providerType: type,
      kind: type.defaultKind,
      name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? type.displayName : name,
      baseURL: type.defaultBaseURL,
      models: models,
      defaultModel: models.first ?? ""
    )
    providers.append(provider)
    selectedProviderId = provider.id
    persistConfiguration()
  }

  func deleteSelectedProvider() {
    guard providers.count > 1,
      let index = providers.firstIndex(where: { $0.id == selectedProviderId })
    else { return }
    let removed = providers.remove(at: index)
    for assistantIndex in assistants.indices
    where assistants[assistantIndex].providerId == removed.id {
      assistants[assistantIndex].providerId = providers[0].id
      assistants[assistantIndex].modelId = providers[0].defaultModel
    }
    selectedProviderId = providers[max(0, index - 1)].id
    persistConfiguration()
  }

  func fetchAvailableModels(for providerId: UUID) async -> [String] {
    guard let index = providers.firstIndex(where: { $0.id == providerId }) else { return [] }
    let provider = providers[index]
    let apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !apiKey.isEmpty else {
      setStatusMessage("请先在设置中配置 API Key。")
      return []
    }
    do {
      let url = provider.baseURL.appendingPathComponent("models")
      var request = URLRequest(url: url)
      request.httpMethod = "GET"
      request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
      request.timeoutInterval = 15

      let (data, response) = try await URLSession.shared.data(for: request)
      guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode)
      else {
        throw URLError(.badServerResponse)
      }

      let models = try JSONDecoder().decode(ModelListResponse.self, from: data).data.map(\.id).sorted()
      setStatusMessage("已获取 \(models.count) 个可添加模型。", autoClear: true)
      return models
    } catch {
      setStatusMessage("获取模型列表失败：\(error.localizedDescription)")
      return []
    }
  }

  func bindSelectedAssistantToProvider(_ providerId: UUID) {
    guard let index = selectedAssistantIndex,
      let provider = providers.first(where: { $0.id == providerId })
    else { return }
    selectedProviderId = providerId
    assistants[index].providerId = providerId
    if !provider.models.contains(assistants[index].modelId) {
      assistants[index].modelId = provider.defaultModel
    }
  }

  /// Switches the selected assistant to a model from any provider (not just the
  /// current one), rebinding provider + model in one step.
  func setSelectedAssistantProviderAndModel(providerId: UUID, modelId: String) {
    guard let index = selectedAssistantIndex,
      let provider = providers.first(where: { $0.id == providerId }),
      provider.models.contains(modelId)
    else { return }
    assistants[index].providerId = providerId
    assistants[index].modelId = modelId
    selectedProviderId = providerId
    persistConfiguration()
  }

  func setSelectedAssistantReasoningEffort(_ effort: ReasoningEffort) {
    guard let index = selectedAssistantIndex else { return }
    assistants[index].reasoningEffort = effort
    persistConfiguration()
  }

  func sendMessage() {
    let typedText = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typedText.isEmpty || !composerAttachments.isEmpty else { return }
    let provider = activeProvider
    let assistant = selectedAssistant
    guard provider.visionModels.contains(assistant.modelId) || composerAttachments.isEmpty else {
      setStatusMessage("当前模型未启用视觉，请先在模型服务中为该模型开启视觉。")
      return
    }
    guard let conversationId = ensureConversationForSelectedAssistant() else { return }
    currentTask?.cancel()
    composerText = ""
    let attachments = composerAttachments
    composerAttachments = []
    let text = typedText.isEmpty ? "请分析这张图片。" : typedText

    let userMessage = ChatMessage(
      id: UUID(),
      conversationId: conversationId,
      role: .user,
      content: text,
      reasoningContent: "",
      citations: [],
      attachments: attachments,
      status: .success,
      usage: nil,
      createdAt: Date(),
      updatedAt: Date()
    )
    messages.append(userMessage)
    persistMessage(userMessage)

    isStreaming = true
    let responseId = UUID()
    let assistantMessage = ChatMessage(
      id: responseId,
      conversationId: conversationId,
      role: .assistant,
      content: "",
      reasoningContent: "",
      citations: [],
      attachments: [],
      status: .streaming,
      usage: nil,
      createdAt: Date(),
      updatedAt: Date()
    )
    messages.append(assistantMessage)
    persistMessage(assistantMessage)
    responseStartTimes[responseId] = Date()

    let requestMessages = messages.filter { message in
      message.id != responseId && message.status != .error && message.status != .stopped
    }
    let contextLimit = assistant.contextMessageCount
    let limitedMessages =
      contextLimit > 0
      ? Array(requestMessages.suffix(contextLimit)) : Array(requestMessages.suffix(1))
    let chatRequest = ChatRequest(
      provider: provider,
      assistant: assistant,
      messages: limitedMessages,
      webSearchMode: effectiveWebSearchMode(
        for: provider, assistant: assistant, messages: limitedMessages),
      searchResults: []
    )
    let service = ChatSessionService(searchSettings: searchSettings)

    currentTask = Task { [weak self] in
      let eventQueue = ChatStreamEventQueue()
      let consumerTask = self?.startStreamEventConsumer(queue: eventQueue, messageId: responseId)
      do {
        try await service.run(chatRequest) { event in
          eventQueue.append(event)
        }
        consumerTask?.cancel()
        let remainingEvents = eventQueue.drain()
        await MainActor.run {
          self?.apply(remainingEvents, to: responseId)
          self?.finishAssistantMessage(messageId: responseId)
        }
        await self?.generateConversationTitleIfNeeded(
          conversationId: conversationId,
          seedText: text,
          assistant: assistant,
          fallbackProvider: provider
        )
      } catch is CancellationError {
        consumerTask?.cancel()
        await MainActor.run {
          self?.markAssistantMessageStopped(messageId: responseId)
        }
      } catch {
        consumerTask?.cancel()
        await MainActor.run {
          self?.markAssistantMessageFailed(error.localizedDescription, messageId: responseId)
        }
      }
    }
  }

  func regenerateResponse(messageId: UUID) {
    guard !isStreaming,
      let messageIndex = messages.firstIndex(where: { $0.id == messageId && $0.role == .assistant })
    else { return }

    let provider = activeProvider
    let assistant = selectedAssistant
    let history = Array(messages[..<messageIndex]).filter { message in
      message.status != .error && message.status != .stopped
    }
    guard !history.isEmpty else { return }
    guard
      provider.visionModels.contains(assistant.modelId)
        || !history.contains(where: { !$0.attachments.isEmpty })
    else {
      setStatusMessage("当前模型未启用视觉，请先在模型服务中为该模型开启视觉。")
      return
    }

    currentTask?.cancel()
    messages[messageIndex].content = ""
    messages[messageIndex].reasoningContent = ""
    messages[messageIndex].citations = []
    messages[messageIndex].usage = nil
    messages[messageIndex].firstTokenLatencyMS = nil
    messages[messageIndex].tokensPerSecond = nil
    messages[messageIndex].status = .streaming
    messages[messageIndex].updatedAt = Date()
    persistMessageUpdate(messages[messageIndex])

    isStreaming = true
    responseStartTimes[messageId] = Date()
    let contextLimit = assistant.contextMessageCount
    let limitedMessages =
      contextLimit > 0 ? Array(history.suffix(contextLimit)) : Array(history.suffix(1))
    let chatRequest = ChatRequest(
      provider: provider,
      assistant: assistant,
      messages: limitedMessages,
      webSearchMode: effectiveWebSearchMode(
        for: provider, assistant: assistant, messages: limitedMessages),
      searchResults: []
    )
    let service = ChatSessionService(searchSettings: searchSettings)

    currentTask = Task { [weak self] in
      let eventQueue = ChatStreamEventQueue()
      let consumerTask = self?.startStreamEventConsumer(queue: eventQueue, messageId: messageId)
      do {
        try await service.run(chatRequest) { event in
          eventQueue.append(event)
        }
        consumerTask?.cancel()
        let remainingEvents = eventQueue.drain()
        await MainActor.run {
          self?.apply(remainingEvents, to: messageId)
          self?.finishAssistantMessage(messageId: messageId)
        }
      } catch is CancellationError {
        consumerTask?.cancel()
        await MainActor.run {
          self?.markAssistantMessageStopped(messageId: messageId)
        }
      } catch {
        consumerTask?.cancel()
        await MainActor.run {
          self?.markAssistantMessageFailed(error.localizedDescription, messageId: messageId)
        }
      }
    }
  }

  func stopStreaming() {
    currentTask?.cancel()
    currentTask = nil
    isStreaming = false
    if let message = messages.last(where: { $0.status == .streaming }) {
      markAssistantMessageStopped(messageId: message.id)
    }
  }

  func showQuickAssistant() {
    guard preferences.quickAssistantEnabled else { return }
    let quickSelection = quickModelSelection
    quickAssistantController.show(
      assistant: assistantForFloatingPanel(
        providerId: quickSelection.provider.id,
        modelId: quickSelection.modelId,
        reasoningEffort: preferences.quickReasoningEffort
      ),
      provider: quickSelection.provider,
      searchSettings: searchSettings,
      preferences: preferences
    )
  }

  func toggleQuickAssistant() {
    guard preferences.quickAssistantEnabled else { return }
    let quickSelection = quickModelSelection
    quickAssistantController.toggle(
      assistant: assistantForFloatingPanel(
        providerId: quickSelection.provider.id,
        modelId: quickSelection.modelId,
        reasoningEffort: preferences.quickReasoningEffort
      ),
      provider: quickSelection.provider,
      searchSettings: searchSettings,
      preferences: preferences
    )
  }

  func showSelectionAssistant() {
    guard preferences.selectionAssistantEnabled else { return }
    let selection = SelectedTextReader.readSelection()
    let translationSelection = translationModelSelection
    selectionAssistantController.show(
      selectedText: selection?.text ?? "",
      selectionBounds: selection?.bounds,
      assistant: selectedAssistant,
      provider: activeProvider,
      translationProvider: translationSelection.provider,
      translationModelId: translationSelection.modelId,
      translationReasoningEffort: preferences.translationReasoningEffort,
      searchSettings: searchSettings,
      preferences: preferences
    )
  }

  func toggleSelectionAssistant() {
    guard preferences.selectionAssistantEnabled else { return }
    let selection = SelectedTextReader.readSelection()
    let translationSelection = translationModelSelection
    selectionAssistantController.toggle(
      selectedText: selection?.text ?? "",
      selectionBounds: selection?.bounds,
      assistant: selectedAssistant,
      provider: activeProvider,
      translationProvider: translationSelection.provider,
      translationModelId: translationSelection.modelId,
      translationReasoningEffort: preferences.translationReasoningEffort,
      searchSettings: searchSettings,
      preferences: preferences
    )
  }

  func loadSelectedConversationMessages() {
    guard let selectedConversationId else {
      messages = []
      return
    }
    do {
      messages = try store?.listMessages(conversationId: selectedConversationId) ?? []
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func persistConfiguration() {
    do {
      try store?.saveProviders(providers)
      try store?.saveAssistants(assistants)
      try store?.saveSearchSettings(searchSettings)
      try store?.saveAppPreferences(preferences)
      if hotKeysStarted {
        startHotKeys()
      }
      quickAssistantController.updateAppearance(preferences: preferences)
      selectionAssistantController.updateAppearance(preferences: preferences)
      setStatusMessage("设置已保存。", autoClear: true)
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  func refreshFloatingPanelAppearance() {
    quickAssistantController.updateAppearance(preferences: preferences)
    selectionAssistantController.updateAppearance(preferences: preferences)
  }

  private func assistantForFloatingPanel(
    providerId: UUID,
    modelId: String,
    reasoningEffort: ReasoningEffort
  ) -> AssistantProfile {
    AssistantProfile(
      id: UUID(),
      name: "快捷助手",
      systemPrompt: "你是桌面快捷助手。只执行用户消息中给出的任务指令，不继承主面板助手的角色、语言偏好或输出格式。",
      providerId: providerId,
      modelId: modelId,
      temperature: 0.4,
      maxTokens: 4096,
      isWebSearchEnabled: false,
      reasoningEffort: reasoningEffort,
      quickTemplates: [],
      contextMessageCount: 0
    )
  }

  private func provider(for assistant: AssistantProfile) -> ModelProvider {
    if let providerId = assistant.providerId,
      let provider = providers.first(where: { $0.id == providerId })
    {
      return provider
    }
    return selectedProvider
  }

  @discardableResult
  private func ensureConversationForSelectedAssistant() -> UUID? {
    // Keep the currently selected topic if it belongs to this assistant.
    if let selectedConversationId,
      let current = conversations.first(where: {
        $0.id == selectedConversationId && $0.assistantId == selectedAssistantId
      })
    {
      loadSelectedConversationMessages()
      return current.id
    }
    if let conversation = conversations.first(where: { $0.assistantId == selectedAssistantId }) {
      selectedConversationId = conversation.id
      loadSelectedConversationMessages()
      return conversation.id
    }

    do {
      let conversation = try store?.createConversation(
        title: selectedAssistant.name, assistantId: selectedAssistantId)
      reloadConversations(keepingSelection: conversation?.id)
      return conversation?.id
    } catch {
      setStatusMessage(error.localizedDescription)
      return nil
    }
  }

  private func appendAssistantDelta(_ delta: String, messageId: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    recordFirstTokenIfNeeded(messageIndex: index, messageId: messageId)
    var parser = thinkTagParsers[messageId] ?? ThinkTagParser()
    let parsed = parser.append(delta)
    thinkTagParsers[messageId] = parser
    enqueueStreamDelta(content: parsed.content, reasoning: parsed.reasoning, messageId: messageId)
  }

  private func appendAssistantReasoningDelta(_ delta: String, messageId: UUID) {
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    recordFirstTokenIfNeeded(messageIndex: index, messageId: messageId)
    enqueueStreamDelta(content: "", reasoning: delta, messageId: messageId)
  }

  private func enqueueStreamDelta(content: String, reasoning: String, messageId: UUID) {
    if !content.isEmpty {
      pendingContentDeltas[messageId, default: ""] += content
    }
    if !reasoning.isEmpty {
      pendingReasoningDeltas[messageId, default: ""] += reasoning
    }
    guard !content.isEmpty || !reasoning.isEmpty else { return }

    markDisplayStreaming(messageId: messageId)
    pendingStreamCharacterCounts[messageId, default: 0] += content.count + reasoning.count
    let now = Date()
    if lastStreamFlushTimes[messageId] == nil
      || now.timeIntervalSince(lastStreamFlushTimes[messageId] ?? now) >= 0.016
      || (pendingStreamCharacterCounts[messageId] ?? 0) >= 240
    {
      flushStreamBuffers(messageId: messageId, flushDate: now)
    } else {
      scheduleStreamFlush(messageId: messageId)
    }
  }

  private func scheduleStreamFlush(messageId: UUID) {
    guard streamFlushTasks[messageId] == nil else { return }
    streamFlushTasks[messageId] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(16))
      await MainActor.run {
        self?.flushStreamBuffers(messageId: messageId)
      }
    }
  }

  private func flushStreamBuffers(
    messageId: UUID,
    flushDate: Date = Date(),
    finishingThinkTag: Bool = false,
    persistImmediately: Bool = false
  ) {
    streamFlushTasks[messageId]?.cancel()
    streamFlushTasks[messageId] = nil

    if finishingThinkTag, var parser = thinkTagParsers.removeValue(forKey: messageId) {
      let final = parser.finish()
      if !final.content.isEmpty {
        pendingContentDeltas[messageId, default: ""] += final.content
      }
      if !final.reasoning.isEmpty {
        pendingReasoningDeltas[messageId, default: ""] += final.reasoning
      }
    }

    let content = pendingContentDeltas.removeValue(forKey: messageId) ?? ""
    let reasoning = pendingReasoningDeltas.removeValue(forKey: messageId) ?? ""
    pendingStreamCharacterCounts[messageId] = 0
    guard !content.isEmpty || !reasoning.isEmpty else {
      if persistImmediately {
        persistStreamMessageImmediately(messageId: messageId)
      }
      return
    }

    guard let index = messages.firstIndex(where: { $0.id == messageId }) else {
      cleanupStreamState(messageId: messageId)
      return
    }

    messages[index].content += content
    messages[index].reasoningContent += reasoning
    messages[index].updatedAt = Date()
    lastStreamFlushTimes[messageId] = flushDate
    if persistImmediately {
      persistStreamMessageImmediately(messageId: messageId)
    } else {
      scheduleStreamPersist(messageId: messageId)
    }
  }

  private func scheduleStreamPersist(messageId: UUID) {
    guard streamPersistTasks[messageId] == nil else { return }
    streamPersistTasks[messageId] = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(300))
      await MainActor.run {
        self?.persistStreamMessage(messageId: messageId)
      }
    }
  }

  private func persistStreamMessage(messageId: UUID) {
    streamPersistTasks[messageId] = nil
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    persistMessageUpdate(messages[index])
  }

  private func persistStreamMessageImmediately(messageId: UUID) {
    streamPersistTasks[messageId]?.cancel()
    streamPersistTasks[messageId] = nil
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    persistMessageUpdate(messages[index])
  }

  private func cleanupStreamState(messageId: UUID) {
    streamFlushTasks[messageId]?.cancel()
    streamFlushTasks[messageId] = nil
    streamPersistTasks[messageId]?.cancel()
    streamPersistTasks[messageId] = nil
    pendingContentDeltas.removeValue(forKey: messageId)
    pendingReasoningDeltas.removeValue(forKey: messageId)
    pendingStreamCharacterCounts.removeValue(forKey: messageId)
    lastStreamFlushTimes.removeValue(forKey: messageId)
    thinkTagParsers.removeValue(forKey: messageId)
  }

  private func markDisplayStreaming(messageId: UUID) {
    displayStreamingTasks[messageId]?.cancel()
    displayStreamingTasks[messageId] = nil
    displayStreamingMessageIds.insert(messageId)
  }

  private func stopDisplayStreaming(messageId: UUID) {
    displayStreamingTasks[messageId]?.cancel()
    displayStreamingTasks[messageId] = nil
    displayStreamingMessageIds.remove(messageId)
  }

  private func apply(_ event: ChatStreamEvent, to messageId: UUID) {
    switch event {
    case .delta(let text):
      appendAssistantDelta(text, messageId: messageId)
    case .reasoningDelta(let text):
      appendAssistantReasoningDelta(text, messageId: messageId)
    case .citation(let citation):
      flushStreamBuffers(messageId: messageId)
      guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
      messages[index].citations.append(citation)
      messages[index].updatedAt = Date()
      persistMessageUpdate(messages[index])
    case .usage(let usage):
      flushStreamBuffers(messageId: messageId)
      guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
      messages[index].usage = usage
      messages[index].updatedAt = Date()
      persistMessageUpdate(messages[index])
    case .completed:
      finishAssistantMessage(messageId: messageId)
    }
  }

  private func apply(_ events: [ChatStreamEvent], to messageId: UUID) {
    for event in events {
      apply(event, to: messageId)
    }
  }

  private func startStreamEventConsumer(queue: ChatStreamEventQueue, messageId: UUID) -> Task<
    Void, Never
  > {
    Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(16))
        let events = queue.drain()
        guard !events.isEmpty else { continue }
        await MainActor.run {
          self?.apply(events, to: messageId)
        }
      }
    }
  }

  private func finishAssistantMessage(messageId: UUID) {
    flushStreamBuffers(messageId: messageId, finishingThinkTag: true, persistImmediately: true)
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    finalizeResponseMetrics(messageIndex: index, messageId: messageId)
    messages[index].status = .success
    messages[index].updatedAt = Date()
    persistMessageUpdate(messages[index])
    stopDisplayStreaming(messageId: messageId)
    cleanupStreamState(messageId: messageId)
    isStreaming = false
    currentTask = nil
    reloadConversations(keepingSelection: selectedConversationId)
  }

  private func markAssistantMessageStopped(messageId: UUID) {
    flushStreamBuffers(messageId: messageId, finishingThinkTag: true, persistImmediately: true)
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    responseStartTimes.removeValue(forKey: messageId)
    messages[index].status = .stopped
    messages[index].updatedAt = Date()
    persistMessageUpdate(messages[index])
    cleanupStreamState(messageId: messageId)
    stopDisplayStreaming(messageId: messageId)
    isStreaming = false
    currentTask = nil
  }

  private func markAssistantMessageFailed(_ error: String, messageId: UUID) {
    flushStreamBuffers(messageId: messageId, finishingThinkTag: true, persistImmediately: true)
    guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
    responseStartTimes.removeValue(forKey: messageId)
    messages[index].content = error
    messages[index].status = .error
    messages[index].updatedAt = Date()
    persistMessageUpdate(messages[index])
    cleanupStreamState(messageId: messageId)
    stopDisplayStreaming(messageId: messageId)
    setStatusMessage(error)
    isStreaming = false
    currentTask = nil
  }

  private func recordFirstTokenIfNeeded(messageIndex: Int, messageId: UUID) {
    guard messages[messageIndex].firstTokenLatencyMS == nil,
      let start = responseStartTimes[messageId]
    else { return }
    messages[messageIndex].firstTokenLatencyMS = max(0, Int(Date().timeIntervalSince(start) * 1000))
  }

  private func finalizeResponseMetrics(messageIndex: Int, messageId: UUID) {
    guard let start = responseStartTimes.removeValue(forKey: messageId),
      let outputTokens = messages[messageIndex].usage?.outputTokens,
      outputTokens > 0
    else { return }
    let elapsed = Date().timeIntervalSince(start)
    guard elapsed > 0 else { return }
    messages[messageIndex].tokensPerSecond = max(1, Int((Double(outputTokens) / elapsed).rounded()))
  }

  private func generateConversationTitleIfNeeded(
    conversationId: UUID,
    seedText: String,
    assistant: AssistantProfile,
    fallbackProvider: ModelProvider
  ) async {
    let trimmedSeed = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedSeed.isEmpty,
      let conversation = conversations.first(where: { $0.id == conversationId })
    else { return }

    let currentTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard currentTitle == assistant.name || currentTitle == "新话题" else { return }

    let quickSelection = resolvedQuickModelSelection(
      fallbackProvider: fallbackProvider, fallbackModelId: assistant.modelId)
    var titleAssistant = assistant
    titleAssistant.name = "话题命名"
    titleAssistant.systemPrompt = "你只负责为对话生成简短话题标题。只输出标题本身。"
    titleAssistant.providerId = quickSelection.provider.id
    titleAssistant.modelId = quickSelection.modelId
    titleAssistant.reasoningEffort = preferences.quickReasoningEffort
    titleAssistant.maxTokens = 80
    titleAssistant.isWebSearchEnabled = false

    let prompt = """
      请为下面这条用户消息生成一个简短话题标题。
      要求：中文优先，最多 12 个字，不要引号，不要句号，不要换行，只输出标题。

      \(trimmedSeed)
      """
    let message = ChatMessage(
      id: UUID(),
      conversationId: conversationId,
      role: .user,
      content: prompt,
      reasoningContent: "",
      citations: [],
      attachments: [],
      status: .success,
      usage: nil,
      createdAt: Date(),
      updatedAt: Date()
    )
    let request = ChatRequest(
      provider: quickSelection.provider,
      assistant: titleAssistant,
      messages: [message],
      webSearchMode: .disabled,
      searchResults: []
    )

    let accumulator = TextAccumulator()
    do {
      try await ChatSessionService(searchSettings: searchSettings).run(request) { event in
        if case .delta(let text) = event {
          await accumulator.append(text)
        }
      }
      let generated = await accumulator.text()
      let generatedTitle = normalizedConversationTitle(generated)
      let title =
        usableGeneratedTitle(generatedTitle, assistantName: assistant.name)
        ? generatedTitle
        : fallbackConversationTitle(from: trimmedSeed)
      guard !title.isEmpty else { return }
      try store?.updateConversationTitle(id: conversationId, title: title)
      reloadConversations(keepingSelection: selectedConversationId)
    } catch {
      let title = fallbackConversationTitle(from: trimmedSeed)
      guard !title.isEmpty else { return }
      try? store?.updateConversationTitle(id: conversationId, title: title)
      reloadConversations(keepingSelection: selectedConversationId)
    }
  }

  private func resolvedQuickModelSelection(fallbackProvider: ModelProvider, fallbackModelId: String)
    -> (provider: ModelProvider, modelId: String)
  {
    resolvedModelSelection(
      providerId: preferences.quickModelProviderId,
      modelId: preferences.quickModelId,
      fallbackProvider: fallbackProvider,
      fallbackModelId: fallbackModelId
    )
  }

  private func resolvedModelSelection(
    providerId: UUID?,
    modelId: String,
    fallbackProvider: ModelProvider,
    fallbackModelId: String
  ) -> (provider: ModelProvider, modelId: String) {
    if let providerId,
      let provider = providers.first(where: { $0.id == providerId }),
      provider.models.contains(modelId)
    {
      return (provider, modelId)
    }
    let fallbackModel =
      fallbackProvider.models.contains(fallbackModelId)
      ? fallbackModelId
      : fallbackProvider.defaultModel
    return (fallbackProvider, fallbackModel)
  }

  private func normalizedConversationTitle(_ rawTitle: String) -> String {
    let stripped =
      rawTitle
      .components(separatedBy: .newlines)
      .first ?? rawTitle
    let trimmed =
      stripped
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`。，."))
    return String(trimmed.prefix(24))
  }

  private func usableGeneratedTitle(_ title: String, assistantName: String) -> Bool {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    return trimmed != assistantName && trimmed != "默认助手" && trimmed != "新话题"
  }

  private func fallbackConversationTitle(from seedText: String) -> String {
    let normalized =
      seedText
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’`。，."))
    guard !normalized.isEmpty else { return "" }
    return String(normalized.prefix(18))
  }

  private func effectiveWebSearchMode(
    for provider: ModelProvider, assistant: AssistantProfile, messages: [ChatMessage]
  ) -> WebSearchMode {
    guard isWebSearchEnabled else { return .disabled }
    if messages.last(where: { $0.role == .user })?.attachments.isEmpty == false {
      return .disabled
    }
    if provider.kind == .openAIResponses && searchSettings.useOpenAIResponsesNativeSearch {
      return .providerNative
    }
    return .tavily
  }

  private func persistMessage(_ message: ChatMessage) {
    do {
      try store?.appendMessage(message)
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  private func persistMessageUpdate(_ message: ChatMessage) {
    do {
      try store?.updateMessage(message)
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  private func reloadConversations(keepingSelection preferredId: UUID? = nil) {
    do {
      conversations = try store?.listConversations() ?? conversations
      if let preferredId, conversations.contains(where: { $0.id == preferredId }) {
        selectedConversationId = preferredId
      } else if let selectedConversationId,
        conversations.contains(where: { $0.id == selectedConversationId })
      {
        self.selectedConversationId = selectedConversationId
      } else {
        selectedConversationId = conversations.first?.id
      }
      loadSelectedConversationMessages()
    } catch {
      setStatusMessage(error.localizedDescription)
    }
  }

  private func loadOrSeed(
    from store: SQLiteStore,
    fallbackProviders: [ModelProvider],
    fallbackAssistants: [AssistantProfile]
  ) throws {
    providers = try store.listProviders()
    if providers.isEmpty {
      providers = fallbackProviders
      try store.saveProviders(providers)
    } else if normalizeLegacyProviderNames() {
      try store.saveProviders(providers)
    }

    assistants = try store.listAssistants()
    if assistants.isEmpty {
      assistants = fallbackAssistants
      try store.saveAssistants(assistants)
    } else {
      let existingNames = Set(assistants.map(\.name))
      let missingStarterAssistants = fallbackAssistants.filter { !existingNames.contains($0.name) }
      if !missingStarterAssistants.isEmpty {
        assistants.append(contentsOf: missingStarterAssistants)
        try store.saveAssistants(assistants)
      }
    }

    searchSettings = (try store.loadSearchSettings()) ?? .default
    try store.saveSearchSettings(searchSettings)
    preferences = (try store.loadAppPreferences()) ?? .default
    try store.saveAppPreferences(preferences)

    selectedAssistantId = assistants[0].id
    selectedProviderId = assistants[0].providerId ?? providers[0].id

    conversations = try store.listConversations()
    if conversations.isEmpty {
      let conversation = try store.createConversation(
        title: assistants[0].name, assistantId: selectedAssistantId)
      conversations = [conversation]
    }
    selectedConversationId =
      conversations.first(where: { $0.assistantId == selectedAssistantId })?.id
      ?? conversations[0].id
    loadSelectedConversationMessages()
  }

  private static func databasePath() throws -> String {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let directory = base.appending(path: "JustChat", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "just-chat.sqlite").path
  }

  private func normalizeLegacyProviderNames() -> Bool {
    var didChange = false
    for index in providers.indices {
      if providers[index].name == providers[index].kind.displayName {
        providers[index].name = providers[index].providerType.displayName
        didChange = true
      }
      let normalizedType = normalizedProviderType(for: providers[index])
      if providers[index].providerType != normalizedType {
        providers[index].providerType = normalizedType
        didChange = true
      }
    }
    return didChange
  }

  private func normalizedProviderType(for provider: ModelProvider) -> ProviderCatalogType {
    let name = provider.name.lowercased()
    let baseURL = provider.baseURL.absoluteString.lowercased()

    if name.contains("newapi") || name.contains("new api") {
      return .newAPI
    }
    if name.contains("anthropic") || provider.kind == .anthropicMessages {
      return .anthropic
    }
    if name.contains("response") || provider.kind == .openAIResponses {
      return .openAIResponse
    }
    if name.contains("gemini") || baseURL.contains("generativelanguage.googleapis.com") {
      return .gemini
    }
    if name.contains("azure") || baseURL.contains(".openai.azure.com") {
      return .azureOpenAI
    }
    if name.contains("ollama") || baseURL.contains("localhost:11434") {
      return .ollama
    }
    if name.contains("cherryin") || name.contains("cherry in") {
      return .cherryIN
    }
    return provider.providerType
  }
}
