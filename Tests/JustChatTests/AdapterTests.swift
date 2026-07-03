import XCTest

@testable import JustChat

final class AdapterTests: XCTestCase {
  func testOpenAIChatCompletionsUsesWebSearchToolWhenTavilyEnabled() throws {
    let provider = ModelProvider(
      id: UUID(),
      providerType: .newAPI,
      kind: .openAIChatCompletions,
      name: "NewAPI",
      baseURL: URL(string: "https://newapi.example.com/v1")!,
      models: ["mimo-v2.5"],
      defaultModel: "mimo-v2.5"
    )
    let assistant = AssistantProfile(
      id: UUID(),
      name: "Assistant",
      systemPrompt: "Be clear.",
      providerId: provider.id,
      modelId: "mimo-v2.5",
      temperature: 0.4,
      maxTokens: 1024,
      isWebSearchEnabled: true,
      quickTemplates: []
    )
    let message = ChatMessage(
      id: UUID(),
      conversationId: UUID(),
      role: .user,
      content: "今天有什么新闻",
      reasoningContent: "",
      citations: [],
      attachments: [],
      status: .success,
      usage: nil,
      createdAt: Date(),
      updatedAt: Date()
    )

    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: provider,
        assistant: assistant,
        messages: [message],
        webSearchMode: .tavily,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let body = try XCTUnwrap(request.httpBody)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let tools = try XCTUnwrap(json["tools"] as? [[String: Any]])
    let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
    XCTAssertEqual(messages.first?["role"] as? String, "system")
    XCTAssertEqual(messages.first?["content"] as? String, "Be clear.")
    XCTAssertEqual(json["tool_choice"] as? String, "auto")
    XCTAssertEqual(json["stream"] as? Bool, false)
    XCTAssertEqual(function["name"] as? String, "web_search")
  }

  func testOpenAIResponsesRequestIncludesWebSearchToolWhenEnabled() throws {
    let provider = ModelProvider(
      id: UUID(),
      providerType: .openAIResponse,
      kind: .openAIResponses,
      name: "OpenAI",
      baseURL: URL(string: "https://api.openai.com/v1")!,
      models: ["gpt-5.4"],
      defaultModel: "gpt-5.4"
    )
    let assistant = AssistantProfile(
      id: UUID(),
      name: "Assistant",
      systemPrompt: "Be clear.",
      providerId: provider.id,
      modelId: "gpt-5.4",
      temperature: 0.4,
      maxTokens: 1024,
      isWebSearchEnabled: true,
      quickTemplates: []
    )
    let message = ChatMessage(
      id: UUID(),
      conversationId: UUID(),
      role: .user,
      content: "Search this",
      reasoningContent: "",
      citations: [],
      attachments: [],
      status: .success,
      usage: nil,
      createdAt: Date(),
      updatedAt: Date()
    )

    let request = try OpenAIResponsesAdapter().makeRequest(
      ChatRequest(
        provider: provider, assistant: assistant, messages: [message],
        webSearchMode: .providerNative, searchResults: []),
      apiKey: "secret"
    )

    XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
    let body = try XCTUnwrap(request.httpBody)
    let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    let tools = json?["tools"] as? [[String: Any]]
    XCTAssertEqual(json?["instructions"] as? String, "Be clear.")
    XCTAssertEqual(tools?.first?["type"] as? String, "web_search")
  }

  func testAnthropicAdapterParsesContentBlockDelta() {
    let event = SSEEvent(
      event: "content_block_delta",
      data: #"{"delta":{"type":"text_delta","text":"hello"}}"#
    )

    XCTAssertEqual(AnthropicMessagesAdapter().parseEvent(event), .delta("hello"))
  }

  func testOpenAIChatCompletionsParsesDoneAsCompleted() {
    let event = SSEEvent(
      event: nil,
      data: "[DONE]"
    )

    XCTAssertEqual(OpenAIChatCompletionsAdapter().parseEvent(event), .completed)
  }

  func testOpenAIChatCompletionsDoesNotStopBeforeUsageChunk() {
    let adapter = OpenAIChatCompletionsAdapter()
    let finishEvent = SSEEvent(
      event: nil,
      data: #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#
    )
    let usageEvent = SSEEvent(
      event: nil,
      data: #"{"choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}"#
    )

    XCTAssertNil(adapter.parseEvent(finishEvent))
    XCTAssertEqual(
      adapter.parseEvent(usageEvent),
      .usage(TokenUsage(inputTokens: 3, outputTokens: 2, totalTokens: 5)))
  }

  func testOpenAIChatCompletionsSeparatesReasoningAndContentDelta() {
    let adapter = OpenAIChatCompletionsAdapter()
    let reasoningEvent = SSEEvent(
      event: nil,
      data:
        #"{"choices":[{"delta":{"content":null,"reasoning_content":"hidden reasoning"},"finish_reason":null}]}"#
    )
    let contentEvent = SSEEvent(
      event: nil,
      data:
        #"{"choices":[{"delta":{"content":"你好","reasoning_content":null},"finish_reason":null}]}"#
    )

    XCTAssertEqual(adapter.parseEvent(reasoningEvent), .reasoningDelta("hidden reasoning"))
    XCTAssertEqual(adapter.parseEvent(contentEvent), .delta("你好"))
  }

  func testOpenAIChatCompletionsParsesNonStreamingBody() throws {
    let data = Data(
      #"""
      {
        "choices": [
          { "message": { "role": "assistant", "content": "hello", "reasoning_content": "hidden reasoning" }, "finish_reason": "stop" }
        ],
        "usage": { "prompt_tokens": 3, "completion_tokens": 2, "total_tokens": 5 }
      }
      """#.utf8
    )

    XCTAssertEqual(
      OpenAIChatCompletionsAdapter().parseResponseBody(data),
      [
        .reasoningDelta("hidden reasoning"),
        .delta("hello"),
        .usage(TokenUsage(inputTokens: 3, outputTokens: 2, totalTokens: 5)),
        .completed,
      ]
    )
  }

  func testOpenAIResponsesParsesNonStreamingOutputText() {
    let data = Data(
      #"""
      {
        "output_text": "hello",
        "usage": { "input_tokens": 4, "output_tokens": 2, "total_tokens": 6 }
      }
      """#.utf8
    )

    XCTAssertEqual(
      OpenAIResponsesAdapter().parseResponseBody(data),
      [
        .delta("hello"),
        .usage(TokenUsage(inputTokens: 4, outputTokens: 2, totalTokens: 6)),
        .completed,
      ]
    )
  }
  func testOpenAIChatCompletionsMapsReasoningEffort() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .openAIChatCompletions),
        assistant: testAssistant(reasoningEffort: .high),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertEqual(json["reasoning_effort"] as? String, "high")
  }

  func testOpenAIChatCompletionsOmitsReasoningWhenOff() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .openAIChatCompletions),
        assistant: testAssistant(reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["reasoning_effort"])
  }

  func testGroqGPTOSSExcludesReasoningWhenOff() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "Groq",
          baseURL: URL(string: "https://api.groq.com/openai/v1")!
        ),
        assistant: testAssistant(modelId: "openai/gpt-oss-120b", reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertEqual(json["include_reasoning"] as? Bool, false)
    XCTAssertNil(json["reasoning_effort"])
  }

  func testGroqGPTOSSOmitsReasoningSettingsWhenAutomatic() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "Groq",
          baseURL: URL(string: "https://api.groq.com/openai/v1")!
        ),
        assistant: testAssistant(modelId: "openai/gpt-oss-120b", reasoningEffort: .automatic),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["include_reasoning"])
    XCTAssertNil(json["reasoning_effort"])
  }

  func testOpenRouterExcludesReasoningWhenOff() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "OpenRouter",
          baseURL: URL(string: "https://openrouter.ai/api/v1")!
        ),
        assistant: testAssistant(modelId: "deepseek/deepseek-r1", reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertEqual(json["include_reasoning"] as? Bool, false)
    XCTAssertNil(json["reasoning_effort"])
  }

  func testOpenRouterOmitsReasoningSettingsWhenAutomatic() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "OpenRouter",
          baseURL: URL(string: "https://openrouter.ai/api/v1")!
        ),
        assistant: testAssistant(modelId: "deepseek/deepseek-r1", reasoningEffort: .automatic),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["include_reasoning"])
    XCTAssertNil(json["reasoning_effort"])
  }

  func testFriendliExcludesReasoningWhenOff() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "Friendli",
          baseURL: URL(string: "https://api.friendli.ai/serverless/v1")!
        ),
        assistant: testAssistant(modelId: "zai-org/GLM-5.2", reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertEqual(json["include_reasoning"] as? Bool, false)
    XCTAssertNil(json["reasoning_effort"])
  }

  func testGroqQwen36DisablesReasoningEffortWhenOff() throws {
    let request = try OpenAIChatCompletionsAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(
          kind: .openAIChatCompletions,
          name: "Groq",
          baseURL: URL(string: "https://api.groq.com/openai/v1")!
        ),
        assistant: testAssistant(modelId: "qwen/qwen3.6-27b", reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: [],
        stream: false
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertEqual(json["reasoning_effort"] as? String, "none")
    XCTAssertNil(json["include_reasoning"])
  }

  func testOpenAIResponsesMapsReasoningEffort() throws {
    let request = try OpenAIResponsesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .openAIResponses),
        assistant: testAssistant(reasoningEffort: .medium),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])
    XCTAssertEqual(reasoning["effort"] as? String, "medium")
  }

  func testOpenAIResponsesDisablesReasoningWhenOff() throws {
    let request = try OpenAIResponsesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .openAIResponses),
        assistant: testAssistant(reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    let reasoning = try XCTUnwrap(json["reasoning"] as? [String: Any])
    XCTAssertEqual(reasoning["effort"] as? String, "none")
  }

  func testOpenAIResponsesOmitsReasoningWhenAutomatic() throws {
    let request = try OpenAIResponsesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .openAIResponses),
        assistant: testAssistant(reasoningEffort: .automatic),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["reasoning"])
  }

  func testAnthropicMapsReasoningEffortToThinkingBudget() throws {
    let request = try AnthropicMessagesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .anthropicMessages),
        assistant: testAssistant(maxTokens: 1024, reasoningEffort: .high),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    let thinking = try XCTUnwrap(json["thinking"] as? [String: Any])
    XCTAssertEqual(thinking["type"] as? String, "enabled")
    XCTAssertEqual(thinking["budget_tokens"] as? Int, 8192)
    XCTAssertEqual(json["max_tokens"] as? Int, 8193)
  }

  func testAnthropicOmitsThinkingBudgetWhenOff() throws {
    let request = try AnthropicMessagesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .anthropicMessages),
        assistant: testAssistant(maxTokens: 2048, reasoningEffort: .off),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["thinking"])
    XCTAssertEqual(json["max_tokens"] as? Int, 2048)
  }

  func testAnthropicOmitsThinkingBudgetWhenAutomatic() throws {
    let request = try AnthropicMessagesAdapter().makeRequest(
      ChatRequest(
        provider: testProvider(kind: .anthropicMessages),
        assistant: testAssistant(maxTokens: 2048, reasoningEffort: .automatic),
        messages: [testMessage()],
        webSearchMode: .disabled,
        searchResults: []
      ),
      apiKey: "secret"
    )

    let json = try requestJSON(request)
    XCTAssertNil(json["thinking"])
    XCTAssertEqual(json["max_tokens"] as? Int, 2048)
  }

  func testAnthropicParsesThinkingDeltaAsReasoning() {
    let event = SSEEvent(
      event: "content_block_delta",
      data: #"{"delta":{"type":"thinking_delta","thinking":"hidden"}}"#
    )

    XCTAssertEqual(AnthropicMessagesAdapter().parseEvent(event), .reasoningDelta("hidden"))
  }

}

private func testProvider(
  kind: ProviderKind,
  name: String = "Provider",
  baseURL: URL? = nil
) -> ModelProvider {
  ModelProvider(
    id: UUID(),
    providerType: kind == .anthropicMessages
      ? .anthropic : (kind == .openAIResponses ? .openAIResponse : .newAPI),
    kind: kind,
    name: name,
    baseURL: baseURL
      ?? URL(
        string: kind == .anthropicMessages
          ? "https://api.anthropic.com/v1" : "https://api.openai.com/v1")!,
    models: ["model"],
    defaultModel: "model"
  )
}

private func testAssistant(
  maxTokens: Int = 4096,
  modelId: String = "model",
  reasoningEffort: ReasoningEffort = .automatic
)
  -> AssistantProfile
{
  AssistantProfile(
    id: UUID(),
    name: "Assistant",
    systemPrompt: "Be clear.",
    providerId: nil,
    modelId: modelId,
    temperature: 0.4,
    maxTokens: maxTokens,
    isWebSearchEnabled: true,
    reasoningEffort: reasoningEffort,
    quickTemplates: []
  )
}

private func testMessage() -> ChatMessage {
  ChatMessage(
    id: UUID(),
    conversationId: UUID(),
    role: .user,
    content: "Hello",
    reasoningContent: "",
    citations: [],
    attachments: [],
    status: .success,
    usage: nil,
    createdAt: Date(),
    updatedAt: Date()
  )
}

private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
  let body = try XCTUnwrap(request.httpBody)
  return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}
