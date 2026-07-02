import Foundation

enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
  case openAIChatCompletions
  case openAIResponses
  case anthropicMessages

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .openAIChatCompletions: "OpenAI Chat Completions"
    case .openAIResponses: "OpenAI Responses"
    case .anthropicMessages: "Anthropic Messages"
    }
  }
}

enum ProviderCatalogType: String, Codable, CaseIterable, Identifiable, Sendable {
  case openAI
  case openAIResponse
  case gemini
  case anthropic
  case azureOpenAI
  case newAPI
  case cherryIN
  case ollama

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .openAI: "OpenAI"
    case .openAIResponse: "OpenAI-Response"
    case .gemini: "Gemini"
    case .anthropic: "Anthropic"
    case .azureOpenAI: "Azure OpenAI"
    case .newAPI: "New API"
    case .cherryIN: "CherryIN"
    case .ollama: "Ollama"
    }
  }

  var defaultKind: ProviderKind {
    switch self {
    case .openAIResponse:
      .openAIResponses
    case .anthropic:
      .anthropicMessages
    case .openAI, .gemini, .azureOpenAI, .newAPI, .cherryIN, .ollama:
      .openAIChatCompletions
    }
  }

  var defaultBaseURL: URL {
    switch self {
    case .openAI, .openAIResponse:
      URL(string: "https://api.openai.com/v1")!
    case .anthropic:
      URL(string: "https://api.anthropic.com/v1")!
    case .gemini:
      URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
    case .azureOpenAI:
      URL(string: "https://resource.openai.azure.com/openai/deployments/deployment")!
    case .newAPI:
      URL(string: "https://newapi.example.com/v1")!
    case .cherryIN:
      URL(string: "https://api.cherry-ai.com/v1")!
    case .ollama:
      URL(string: "http://localhost:11434/v1")!
    }
  }

  var defaultModels: [String] {
    switch self {
    case .openAI:
      ["gpt-5.4-mini", "gpt-5.3"]
    case .openAIResponse:
      ["gpt-5.4", "gpt-5.4-mini", "gpt-5.3"]
    case .anthropic:
      ["claude-sonnet-4-5", "claude-opus-4-5"]
    case .gemini:
      ["gemini-2.5-pro", "gemini-2.5-flash"]
    case .azureOpenAI:
      ["gpt-5.4-mini"]
    case .newAPI:
      ["gpt-5.4", "gpt-5.4-mini"]
    case .cherryIN:
      ["cherry-chat"]
    case .ollama:
      ["llama3.1", "qwen2.5"]
    }
  }

  var defaultAPIKeyName: String {
    switch self {
    case .openAI, .openAIResponse: "openai-primary"
    case .anthropic: "anthropic-primary"
    case .gemini: "gemini-primary"
    case .azureOpenAI: "azure-openai-primary"
    case .newAPI: "newapi-primary"
    case .cherryIN: "cherryin-primary"
    case .ollama: "ollama-local"
    }
  }
}

enum ChatRole: String, Codable, CaseIterable, Sendable {
  case system
  case user
  case assistant
}

enum MessageStatus: String, Codable, Sendable {
  case pending
  case streaming
  case success
  case error
  case stopped
}

struct Conversation: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var assistantId: UUID?
  var createdAt: Date
  var updatedAt: Date
}

struct TokenUsage: Codable, Hashable, Sendable {
  var inputTokens: Int?
  var outputTokens: Int?
  var totalTokens: Int?
}

struct Citation: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var url: URL
  var snippet: String
  var source: String
}

struct MessageImage: Codable, Hashable, Sendable, Identifiable {
  var id: UUID
  var data: Data
  var mimeType: String
}

struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var conversationId: UUID
  var role: ChatRole
  var content: String
  var reasoningContent: String
  var citations: [Citation]
  var attachments: [MessageImage]
  var status: MessageStatus
  var usage: TokenUsage?
  var firstTokenLatencyMS: Int? = nil
  var tokensPerSecond: Int? = nil
  var createdAt: Date
  var updatedAt: Date
}

enum ReasoningEffort: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
  case automatic
  case off
  case low
  case medium
  case high

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .automatic: "默认"
    case .off: "关闭"
    case .low: "低"
    case .medium: "中"
    case .high: "高"
    }
  }

  var apiValue: String? {
    switch self {
    case .automatic, .off: nil
    case .low: "low"
    case .medium: "medium"
    case .high: "high"
    }
  }

  var responsesAPIValue: String? {
    switch self {
    case .automatic: nil
    case .off: "none"
    case .low: "low"
    case .medium: "medium"
    case .high: "high"
    }
  }

  var anthropicBudgetTokens: Int? {
    switch self {
    case .automatic, .off: nil
    case .low: 1024
    case .medium: 4096
    case .high: 8192
    }
  }
}

struct AssistantProfile: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var name: String
  var systemPrompt: String
  var providerId: UUID?
  var modelId: String
  var temperature: Double
  var maxTokens: Int
  var isWebSearchEnabled: Bool
  var isVisionEnabled: Bool
  var reasoningEffort: ReasoningEffort
  var quickTemplates: [PromptTemplate]
  /// How many of the most recent messages to send as context (0 = send all).
  var contextMessageCount: Int = 20

  init(
    id: UUID,
    name: String,
    systemPrompt: String,
    providerId: UUID?,
    modelId: String,
    temperature: Double,
    maxTokens: Int,
    isWebSearchEnabled: Bool,
    isVisionEnabled: Bool,
    reasoningEffort: ReasoningEffort = .automatic,
    quickTemplates: [PromptTemplate],
    contextMessageCount: Int = 20
  ) {
    self.id = id
    self.name = name
    self.systemPrompt = systemPrompt
    self.providerId = providerId
    self.modelId = modelId
    self.temperature = temperature
    self.maxTokens = maxTokens
    self.isWebSearchEnabled = isWebSearchEnabled
    self.isVisionEnabled = isVisionEnabled
    self.reasoningEffort = reasoningEffort
    self.quickTemplates = quickTemplates
    self.contextMessageCount = contextMessageCount
  }

  private enum CodingKeys: String, CodingKey {
    case id
    case name
    case systemPrompt
    case providerId
    case modelId
    case temperature
    case maxTokens
    case isWebSearchEnabled
    case isVisionEnabled
    case reasoningEffort
    case quickTemplates
    case contextMessageCount
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    systemPrompt = try container.decode(String.self, forKey: .systemPrompt)
    providerId = try container.decodeIfPresent(UUID.self, forKey: .providerId)
    modelId = try container.decode(String.self, forKey: .modelId)
    temperature = try container.decode(Double.self, forKey: .temperature)
    maxTokens = try container.decode(Int.self, forKey: .maxTokens)
    isWebSearchEnabled = try container.decode(Bool.self, forKey: .isWebSearchEnabled)
    isVisionEnabled = try container.decodeIfPresent(Bool.self, forKey: .isVisionEnabled) ?? false
    reasoningEffort =
      try container.decodeIfPresent(ReasoningEffort.self, forKey: .reasoningEffort) ?? .automatic
    quickTemplates = try container.decode([PromptTemplate].self, forKey: .quickTemplates)
    contextMessageCount =
      try container.decodeIfPresent(Int.self, forKey: .contextMessageCount) ?? 20
  }
}

struct PromptTemplate: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var prompt: String
}

struct ModelProvider: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var providerType: ProviderCatalogType
  var kind: ProviderKind
  var name: String
  var baseURL: URL
  var apiKeyName: String
  var apiKey: String = ""
  var models: [String]
  var visionModels: Set<String> = []
  var defaultModel: String
  var isEnabled: Bool
}

struct SearchSettings: Codable, Hashable, Sendable {
  var tavilyAPIKeyName: String
  var tavilyAPIKey: String
  var tavilyMaxResults: Int
  var useOpenAIResponsesNativeSearch: Bool

  static let `default` = SearchSettings()

  init(
    tavilyAPIKeyName: String = "tavily-primary",
    tavilyAPIKey: String = "",
    tavilyMaxResults: Int = 6,
    useOpenAIResponsesNativeSearch: Bool = true
  ) {
    self.tavilyAPIKeyName = tavilyAPIKeyName
    self.tavilyAPIKey = tavilyAPIKey
    self.tavilyMaxResults = tavilyMaxResults
    self.useOpenAIResponsesNativeSearch = useOpenAIResponsesNativeSearch
  }

  private enum CodingKeys: String, CodingKey {
    case tavilyAPIKeyName
    case tavilyAPIKey
    case tavilyMaxResults
    case useOpenAIResponsesNativeSearch
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    tavilyAPIKeyName =
      try container.decodeIfPresent(String.self, forKey: .tavilyAPIKeyName) ?? "tavily-primary"
    tavilyAPIKey = try container.decodeIfPresent(String.self, forKey: .tavilyAPIKey) ?? ""
    tavilyMaxResults = try container.decodeIfPresent(Int.self, forKey: .tavilyMaxResults) ?? 6
    useOpenAIResponsesNativeSearch =
      try container.decodeIfPresent(Bool.self, forKey: .useOpenAIResponsesNativeSearch) ?? true
  }
}

struct SearchResult: Identifiable, Codable, Hashable, Sendable {
  var id: UUID
  var title: String
  var content: String
  var url: URL
  var provider: String
}

struct ChatRequest: Hashable, Sendable {
  var provider: ModelProvider
  var assistant: AssistantProfile
  var messages: [ChatMessage]
  var webSearchMode: WebSearchMode
  var searchResults: [SearchResult]
  var stream: Bool = true
}

enum WebSearchMode: String, Codable, Hashable, Sendable {
  case disabled
  case tavily
  case providerNative
}

enum ChatStreamEvent: Equatable, Sendable {
  case delta(String)
  case reasoningDelta(String)
  case citation(Citation)
  case usage(TokenUsage)
  case completed
}

enum RootSection: String, CaseIterable, Identifiable, Sendable {
  case home = "首页"
  case settings = "设置"

  var id: String { rawValue }
}

enum HomeSidebarTab: String, CaseIterable, Identifiable, Sendable {
  case assistants = "助手"
  case topics = "话题"

  var id: String { rawValue }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case system = "自动"
  case light = "白天"
  case dark = "黑夜"

  var id: String { rawValue }
}

struct AppPreferences: Codable, Hashable, Sendable {
  var appearanceMode: AppearanceMode
  var homeSidebarWidth: Double
  var chatFontSize: Double
  var defaultAssistantProviderId: UUID?
  var defaultAssistantModelId: String
  var quickModelProviderId: UUID?
  var quickModelId: String
  var translationModelProviderId: UUID?
  var translationModelId: String
  var quickAssistantEnabled: Bool
  var quickAssistantHotKey: String
  var quickAssistantReadsClipboard: Bool
  var selectionAssistantEnabled: Bool
  var selectionAssistantHotKey: String
  var selectionTriggerMode: SelectionTriggerMode
  var selectionCompactMode: Bool
  var selectionFollowToolbar: Bool
  var selectionAutoClose: Bool
  var selectionAutoPin: Bool
  var selectionWindowOpacity: Double

  init(
    appearanceMode: AppearanceMode = .system,
    homeSidebarWidth: Double = 300,
    chatFontSize: Double = 15,
    defaultAssistantProviderId: UUID? = nil,
    defaultAssistantModelId: String = "",
    quickModelProviderId: UUID? = nil,
    quickModelId: String = "",
    translationModelProviderId: UUID? = nil,
    translationModelId: String = "",
    quickAssistantEnabled: Bool = true,
    quickAssistantHotKey: String = "Command+Shift+Space",
    quickAssistantReadsClipboard: Bool = true,
    selectionAssistantEnabled: Bool = true,
    selectionAssistantHotKey: String = "Command+Shift+E",
    selectionTriggerMode: SelectionTriggerMode = .shortcut,
    selectionCompactMode: Bool = false,
    selectionFollowToolbar: Bool = true,
    selectionAutoClose: Bool = true,
    selectionAutoPin: Bool = false,
    selectionWindowOpacity: Double = 1.0
  ) {
    self.appearanceMode = appearanceMode
    self.homeSidebarWidth = homeSidebarWidth
    self.chatFontSize = chatFontSize
    self.defaultAssistantProviderId = defaultAssistantProviderId
    self.defaultAssistantModelId = defaultAssistantModelId
    self.quickModelProviderId = quickModelProviderId
    self.quickModelId = quickModelId
    self.translationModelProviderId = translationModelProviderId
    self.translationModelId = translationModelId
    self.quickAssistantEnabled = quickAssistantEnabled
    self.quickAssistantHotKey = quickAssistantHotKey
    self.quickAssistantReadsClipboard = quickAssistantReadsClipboard
    self.selectionAssistantEnabled = selectionAssistantEnabled
    self.selectionAssistantHotKey = selectionAssistantHotKey
    self.selectionTriggerMode = selectionTriggerMode
    self.selectionCompactMode = selectionCompactMode
    self.selectionFollowToolbar = selectionFollowToolbar
    self.selectionAutoClose = selectionAutoClose
    self.selectionAutoPin = selectionAutoPin
    self.selectionWindowOpacity = selectionWindowOpacity
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      appearanceMode: try container.decodeIfPresent(AppearanceMode.self, forKey: .appearanceMode)
        ?? .system,
      homeSidebarWidth: try container.decodeIfPresent(Double.self, forKey: .homeSidebarWidth)
        ?? 300,
      chatFontSize: try container.decodeIfPresent(Double.self, forKey: .chatFontSize) ?? 15,
      defaultAssistantProviderId: try container.decodeIfPresent(
        UUID.self, forKey: .defaultAssistantProviderId),
      defaultAssistantModelId: try container.decodeIfPresent(
        String.self, forKey: .defaultAssistantModelId) ?? "",
      quickModelProviderId: try container.decodeIfPresent(UUID.self, forKey: .quickModelProviderId),
      quickModelId: try container.decodeIfPresent(String.self, forKey: .quickModelId) ?? "",
      translationModelProviderId: try container.decodeIfPresent(
        UUID.self, forKey: .translationModelProviderId),
      translationModelId: try container.decodeIfPresent(String.self, forKey: .translationModelId)
        ?? "",
      quickAssistantEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .quickAssistantEnabled) ?? true,
      quickAssistantHotKey: try container.decodeIfPresent(
        String.self, forKey: .quickAssistantHotKey) ?? "Command+Shift+Space",
      quickAssistantReadsClipboard: try container.decodeIfPresent(
        Bool.self, forKey: .quickAssistantReadsClipboard) ?? true,
      selectionAssistantEnabled: try container.decodeIfPresent(
        Bool.self, forKey: .selectionAssistantEnabled) ?? true,
      selectionAssistantHotKey: try container.decodeIfPresent(
        String.self, forKey: .selectionAssistantHotKey) ?? "Command+Shift+E",
      selectionTriggerMode: try container.decodeIfPresent(
        SelectionTriggerMode.self, forKey: .selectionTriggerMode) ?? .shortcut,
      selectionCompactMode: try container.decodeIfPresent(Bool.self, forKey: .selectionCompactMode)
        ?? false,
      selectionFollowToolbar: try container.decodeIfPresent(
        Bool.self, forKey: .selectionFollowToolbar) ?? true,
      selectionAutoClose: try container.decodeIfPresent(Bool.self, forKey: .selectionAutoClose)
        ?? true,
      selectionAutoPin: try container.decodeIfPresent(Bool.self, forKey: .selectionAutoPin)
        ?? false,
      selectionWindowOpacity: try container.decodeIfPresent(
        Double.self, forKey: .selectionWindowOpacity) ?? 1.0
    )
  }

  static let `default` = AppPreferences(
    appearanceMode: .system,
    homeSidebarWidth: 300,
    chatFontSize: 15,
    defaultAssistantProviderId: nil,
    defaultAssistantModelId: "",
    quickModelProviderId: nil,
    quickModelId: "",
    translationModelProviderId: nil,
    translationModelId: "",
    quickAssistantEnabled: true,
    quickAssistantHotKey: "Command+Shift+Space",
    quickAssistantReadsClipboard: true,
    selectionAssistantEnabled: true,
    selectionAssistantHotKey: "Command+Shift+E",
    selectionTriggerMode: .shortcut,
    selectionCompactMode: false,
    selectionFollowToolbar: true,
    selectionAutoClose: true,
    selectionAutoPin: false,
    selectionWindowOpacity: 1.0
  )
}

enum SelectionTriggerMode: String, Codable, CaseIterable, Identifiable, Sendable {
  case selected = "划词"
  case shortcut = "快捷键"

  var id: String { rawValue }
}

enum SettingsPane: String, CaseIterable, Identifiable, Sendable {
  case providers = "模型服务"
  case defaultModel = "默认模型"
  case general = "常规设置"
  case display = "显示设置"
  case data = "数据设置"
  case search = "网络搜索"
  case quickAssistant = "快捷助手"
  case selectionAssistant = "划词助手"
  case hotKeys = "快捷键"
  case about = "关于我们"

  var id: String { rawValue }
}
