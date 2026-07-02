import XCTest

@testable import JustChat

final class SQLiteStoreTests: XCTestCase {
  func testCreatesConversationAndMessages() throws {
    let path = NSTemporaryDirectory().appending("just-chat-\(UUID().uuidString).sqlite")
    let store = SQLiteStore(path: path)
    try store.open()

    let conversation = try store.createConversation(title: "Test")
    let message = ChatMessage(
      id: UUID(),
      conversationId: conversation.id,
      role: .user,
      content: "Hello",
      reasoningContent: "Thinking",
      citations: [],
      attachments: [],
      status: .success,
      usage: nil,
      firstTokenLatencyMS: 602,
      tokensPerSecond: 511,
      createdAt: Date(),
      updatedAt: Date()
    )
    try store.appendMessage(message)

    XCTAssertEqual(try store.listConversations().map(\.title), ["Test"])
    XCTAssertEqual(
      try store.listMessages(conversationId: conversation.id).map(\.content), ["Hello"])
    XCTAssertEqual(
      try store.listMessages(conversationId: conversation.id).map(\.reasoningContent), ["Thinking"])
    XCTAssertEqual(
      try store.listMessages(conversationId: conversation.id).first?.firstTokenLatencyMS, 602)
    XCTAssertEqual(
      try store.listMessages(conversationId: conversation.id).first?.tokensPerSecond, 511)
  }

  func testPersistsProvidersAssistantsAndSearchSettings() throws {
    let path = NSTemporaryDirectory().appending("just-chat-\(UUID().uuidString).sqlite")
    let store = SQLiteStore(path: path)
    try store.open()

    var provider = Defaults.providers()[0]
    provider.visionModels = ["gpt-5.4"]
    let assistant = Defaults.assistants(primaryProviderId: provider.id)[0]
    let search = SearchSettings(
      tavilyAPIKeyName: "tavily-test", tavilyAPIKey: "tvly-test", tavilyMaxResults: 3,
      useOpenAIResponsesNativeSearch: false)
    var preferences = AppPreferences.default
    preferences.selectionCompactMode = true

    try store.saveProviders([provider])
    try store.saveAssistants([assistant])
    try store.saveSearchSettings(search)
    try store.saveAppPreferences(preferences)

    XCTAssertEqual(try store.listProviders(), [provider])
    XCTAssertEqual(try store.listAssistants(), [assistant])
    XCTAssertEqual(try store.loadSearchSettings(), search)
    XCTAssertEqual(try store.loadAppPreferences(), preferences)
  }

  func testAppPreferencesDecodesLegacyPayloadWithNewDefaults() throws {
    let data = Data("{}".utf8)

    let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)

    XCTAssertEqual(preferences.appearanceMode, .system)
    XCTAssertEqual(preferences.homeSidebarWidth, 300)
    XCTAssertEqual(preferences.chatFontSize, 15)
    XCTAssertNil(preferences.defaultAssistantProviderId)
    XCTAssertEqual(preferences.defaultAssistantModelId, "")
    XCTAssertNil(preferences.quickModelProviderId)
    XCTAssertEqual(preferences.quickModelId, "")
    XCTAssertNil(preferences.translationModelProviderId)
    XCTAssertEqual(preferences.translationModelId, "")
    XCTAssertEqual(preferences.quickAssistantHotKey, "Command+Shift+Space")
    XCTAssertEqual(preferences.selectionAssistantHotKey, "Command+Shift+E")
  }

  func testRenamesAndDeletesConversations() throws {
    let path = NSTemporaryDirectory().appending("just-chat-\(UUID().uuidString).sqlite")
    let store = SQLiteStore(path: path)
    try store.open()

    let conversation = try store.createConversation(title: "Original")
    try store.updateConversationTitle(id: conversation.id, title: "Renamed")
    XCTAssertEqual(try store.listConversations().first?.title, "Renamed")

    let message = ChatMessage(
      id: UUID(), conversationId: conversation.id, role: .user,
      content: "hi", reasoningContent: "", citations: [], attachments: [], status: .success,
      usage: nil, createdAt: Date(), updatedAt: Date()
    )
    try store.appendMessage(message)
    try store.deleteConversation(id: conversation.id)

    XCTAssertTrue(try store.listConversations().isEmpty)
    XCTAssertTrue(try store.listMessages(conversationId: conversation.id).isEmpty)
  }

  func testPersistsAssistantContextMessageCount() throws {
    let path = NSTemporaryDirectory().appending("just-chat-\(UUID().uuidString).sqlite")
    let store = SQLiteStore(path: path)
    try store.open()

    var assistant = Defaults.assistants(primaryProviderId: Defaults.providers()[0].id)[0]
    assistant.contextMessageCount = 8
    assistant.reasoningEffort = .medium
    try store.saveAssistants([assistant])

    let loaded = try store.listAssistants()
    XCTAssertEqual(loaded.first?.contextMessageCount, 8)
    XCTAssertEqual(loaded.first?.reasoningEffort, .medium)
  }
  func testAssistantProfileDecodesLegacyPayloadWithReasoningAutomatic() throws {
    let id = UUID()
    let data = Data(
      #"""
      {
        "id": "\#(id.uuidString)",
        "name": "Legacy",
        "systemPrompt": "Be clear.",
        "providerId": null,
        "modelId": "model",
        "temperature": 0.7,
        "maxTokens": 4096,
        "isWebSearchEnabled": true,
        "isVisionEnabled": false,
        "quickTemplates": [],
        "contextMessageCount": 20
      }
      """#.utf8
    )

    let assistant = try JSONDecoder().decode(AssistantProfile.self, from: data)

    XCTAssertEqual(assistant.reasoningEffort, .automatic)
  }

}
