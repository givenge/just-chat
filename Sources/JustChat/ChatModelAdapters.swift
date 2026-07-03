import Foundation

struct SSEEvent: Equatable {
  var event: String?
  var data: String
}

protocol ChatModelAdapter: Sendable {
  var kind: ProviderKind { get }
  func makeRequest(_ request: ChatRequest, apiKey: String) throws -> URLRequest
  func parseEvent(_ event: SSEEvent) -> ChatStreamEvent?
  func parseResponseBody(_ data: Data) -> [ChatStreamEvent]
}

extension ChatModelAdapter {
  func parseResponseBody(_ data: Data) -> [ChatStreamEvent] {
    []
  }
}

enum ChatAdapterError: Error, LocalizedError {
  case invalidBaseURL
  case unsupportedProvider
  case missingResponseData
  case providerError(String)
  case unusableResponse(String)

  var errorDescription: String? {
    switch self {
    case .invalidBaseURL: "The provider base URL is invalid."
    case .unsupportedProvider: "The selected provider is not supported by this adapter."
    case .missingResponseData: "The provider response did not contain usable content."
    case .providerError(let message): "Provider returned an error: \(message)"
    case .unusableResponse(let preview):
      "The provider response did not contain usable content. Response: \(preview)"
    }
  }
}

struct OpenAIChatCompletionsAdapter: ChatModelAdapter {
  let kind: ProviderKind = .openAIChatCompletions

  func makeRequest(_ request: ChatRequest, apiKey: String) throws -> URLRequest {
    var url = request.provider.baseURL
    url.append(path: "chat/completions")

    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 240
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(request), options: [])
    return urlRequest
  }

  func parseEvent(_ event: SSEEvent) -> ChatStreamEvent? {
    guard event.data != "[DONE]" else { return .completed }
    guard let data = event.data.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      return nil
    }

    let parsedUsage = usage(
      from: json["usage"] as? [String: Any], inputKey: "prompt_tokens",
      outputKey: "completion_tokens")

    guard
      let choices = json["choices"] as? [[String: Any]],
      let choice = choices.first
    else {
      return parsedUsage.map(ChatStreamEvent.usage)
    }

    if let delta = choice["delta"] as? [String: Any] {
      if let content = streamTextValue(delta["content"]) {
        return .delta(content)
      }
      if let reasoning = streamTextValue(delta["reasoning_content"])
        ?? streamTextValue(delta["reasoning"])
      {
        return .reasoningDelta(reasoning)
      }
      if let text = streamTextValue(delta["text"]) {
        return .delta(text)
      }
    }

    if let message = choice["message"] as? [String: Any],
      let content = messageContent(message),
      !content.isEmpty
    {
      return .delta(content)
    }

    if let text = textValue(choice["text"]), !text.isEmpty {
      return .delta(text)
    }

    return parsedUsage.map(ChatStreamEvent.usage)
  }

  func parseResponseBody(_ data: Data) -> [ChatStreamEvent] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let choices = json["choices"] as? [[String: Any]],
      let choice = choices.first,
      let message = choice["message"] as? [String: Any]
    else {
      return []
    }

    var events: [ChatStreamEvent] = []
    if let reasoning = messageReasoningContent(message), !reasoning.isEmpty {
      events.append(.reasoningDelta(reasoning))
    }
    if let content = messageContent(message), !content.isEmpty {
      events.append(.delta(content))
    } else if let text = textValue(choice["text"]), !text.isEmpty {
      events.append(.delta(text))
    }
    if let usage = usage(
      from: json["usage"] as? [String: Any], inputKey: "prompt_tokens",
      outputKey: "completion_tokens")
    {
      events.append(.usage(usage))
    }
    appendGenericText(from: json, to: &events)
    if !events.isEmpty {
      events.append(.completed)
    }
    return events
  }

  private func body(_ request: ChatRequest) -> [String: Any] {
    var payload: [String: Any] = [
      "model": request.modelId,
      "stream": request.stream,
      "temperature": request.assistant.temperature,
      "max_tokens": request.assistant.maxTokens,
      "messages": chatMessages(for: request),
    ]

    if request.stream {
      payload["stream_options"] = ["include_usage": true]
    }

    applyChatCompletionsReasoningSettings(to: &payload, for: request)

    if request.webSearchMode == .tavily {
      payload["tools"] = [
        [
          "type": "function",
          "function": [
            "name": "web_search",
            "description":
              "Search the web for current, recent, or externally verifiable information. Call this only when the answer needs web lookup.",
            "parameters": [
              "type": "object",
              "properties": [
                "query": [
                  "type": "string",
                  "description": "A concise search query.",
                ]
              ],
              "required": ["query"],
            ],
          ],
        ]
      ]
      payload["tool_choice"] = "auto"
    }

    return payload
  }

  private func applyChatCompletionsReasoningSettings(
    to payload: inout [String: Any],
    for request: ChatRequest
  ) {
    if let effort = request.assistant.reasoningEffort.apiValue {
      payload["reasoning_effort"] = effort
      return
    }

    guard request.assistant.reasoningEffort == .off else { return }

    if isGroqQwen36Request(request) {
      payload["reasoning_effort"] = "none"
    } else if supportsIncludeReasoning(request.provider) {
      payload["include_reasoning"] = false
    }
  }

  private func isGroqQwen36Request(_ request: ChatRequest) -> Bool {
    let modelId = request.modelId.lowercased()
    return isGroqProvider(request.provider) && modelId.contains("qwen3.6")
  }

  private func supportsIncludeReasoning(_ provider: ModelProvider) -> Bool {
    providerIdentity(provider).contains { identity in
      identity.contains("groq")
        || identity.contains("openrouter")
        || identity.contains("friendli")
        || identity.contains("heroku")
        || identity.contains("watsonx")
        || identity.contains("ibm")
        || identity.contains("vllm")
    }
  }

  private func isGroqProvider(_ provider: ModelProvider) -> Bool {
    providerIdentity(provider).contains { $0.contains("groq") }
  }

  private func providerIdentity(_ provider: ModelProvider) -> [String] {
    [
      provider.name,
      provider.baseURL.host ?? "",
      provider.baseURL.absoluteString,
    ].map { $0.lowercased() }
  }

  private func chatMessages(for request: ChatRequest) -> [[String: Any]] {
    var messages: [[String: Any]] = []
    let systemPrompt = request.assistant.systemPrompt.trimmingCharacters(
      in: .whitespacesAndNewlines)
    if !systemPrompt.isEmpty {
      messages.append(["role": "system", "content": systemPrompt])
    }
    messages.append(contentsOf: request.messages.map { messageContent($0) })
    return messages
  }
}

private func messageContent(_ message: ChatMessage) -> [String: Any] {
  if message.attachments.isEmpty {
    return ["role": message.role.rawValue, "content": message.content]
  }
  var parts: [[String: Any]] = [["type": "text", "text": message.content]]
  for attachment in message.attachments {
    let base64 = attachment.data.base64EncodedString()
    parts.append([
      "type": "image_url",
      "image_url": ["url": "data:\(attachment.mimeType);base64,\(base64)"],
    ])
  }
  return ["role": message.role.rawValue, "content": parts]
}

private func responsesContent(_ message: ChatMessage) -> [[String: Any]] {
  var parts: [[String: Any]] = [["type": "input_text", "text": message.content]]
  for attachment in message.attachments {
    let base64 = attachment.data.base64EncodedString()
    parts.append([
      "type": "input_image",
      "image_url": "data:\(attachment.mimeType);base64,\(base64)",
    ])
  }
  return parts
}

private func anthropicContent(_ message: ChatMessage) -> Any {
  if message.attachments.isEmpty {
    return message.content
  }
  var parts: [[String: Any]] = [["type": "text", "text": message.content]]
  for attachment in message.attachments {
    let base64 = attachment.data.base64EncodedString()
    parts.append([
      "type": "image",
      "source": [
        "type": "base64",
        "media_type": attachment.mimeType,
        "data": base64,
      ],
    ])
  }
  return parts
}

private func systemInstructions(for request: ChatRequest) -> String? {
  let parts =
    [request.assistant.systemPrompt]
    + request.messages.filter { $0.role == .system }.map(\.content)
  let text =
    parts
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { !$0.isEmpty }
    .joined(separator: "\n\n")
  return text.isEmpty ? nil : text
}

struct OpenAIResponsesAdapter: ChatModelAdapter {
  let kind: ProviderKind = .openAIResponses

  func makeRequest(_ request: ChatRequest, apiKey: String) throws -> URLRequest {
    var url = request.provider.baseURL
    url.append(path: "responses")

    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 240
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(request), options: [])
    return urlRequest
  }

  func parseEvent(_ event: SSEEvent) -> ChatStreamEvent? {
    if event.event == "response.completed" {
      guard let data = event.data.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return .completed }
      let response = json["response"] as? [String: Any]
      if let usage = usage(
        from: (response?["usage"] as? [String: Any]) ?? (json["usage"] as? [String: Any]),
        inputKey: "input_tokens", outputKey: "output_tokens")
      {
        return .usage(usage)
      }
      return .completed
    }
    guard event.event == "response.output_text.delta",
      let data = event.data.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let delta = json["delta"] as? String
    else {
      return nil
    }
    return .delta(delta)
  }

  func parseResponseBody(_ data: Data) -> [ChatStreamEvent] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return []
    }

    var events: [ChatStreamEvent] = []
    if let outputText = json["output_text"] as? String, !outputText.isEmpty {
      events.append(.delta(outputText))
    } else if let output = json["output"] as? [[String: Any]] {
      let text = output.compactMap(outputItemText).joined()
      if !text.isEmpty {
        events.append(.delta(text))
      }
    }

    if let usage = usage(
      from: json["usage"] as? [String: Any], inputKey: "input_tokens", outputKey: "output_tokens")
    {
      events.append(.usage(usage))
    }
    appendGenericText(from: json, to: &events)
    if !events.isEmpty {
      events.append(.completed)
    }
    return events
  }

  private func body(_ request: ChatRequest) -> [String: Any] {
    var payload: [String: Any] = [
      "model": request.modelId,
      "stream": request.stream,
      "temperature": request.assistant.temperature,
      "max_output_tokens": request.assistant.maxTokens,
      "input": request.messages.filter { $0.role != .system }.map {
        [
          "role": $0.role.rawValue,
          "content": responsesContent($0),
        ]
      },
    ]

    if let instructions = systemInstructions(for: request) {
      payload["instructions"] = instructions
    }

    if let effort = request.assistant.reasoningEffort.responsesAPIValue {
      payload["reasoning"] = ["effort": effort]
    }

    if request.webSearchMode == .providerNative {
      payload["tools"] = [["type": "web_search"]]
    }

    return payload
  }
}

struct AnthropicMessagesAdapter: ChatModelAdapter {
  let kind: ProviderKind = .anthropicMessages

  func makeRequest(_ request: ChatRequest, apiKey: String) throws -> URLRequest {
    var url = request.provider.baseURL
    url.append(path: "messages")

    var urlRequest = URLRequest(url: url)
    urlRequest.timeoutInterval = 240
    urlRequest.httpMethod = "POST"
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body(request), options: [])
    return urlRequest
  }

  func parseEvent(_ event: SSEEvent) -> ChatStreamEvent? {
    if event.event == "message_stop" { return .completed }
    if event.event == "message_delta" || event.event == "message_start" {
      guard let data = event.data.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
      else { return nil }
      let message = json["message"] as? [String: Any]
      if let usage = usage(
        from: (message?["usage"] as? [String: Any]) ?? (json["usage"] as? [String: Any]),
        inputKey: "input_tokens", outputKey: "output_tokens")
      {
        return .usage(usage)
      }
    }
    guard event.event == "content_block_delta",
      let data = event.data.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let delta = json["delta"] as? [String: Any]
    else {
      return nil
    }
    if let text = delta["text"] as? String {
      return .delta(text)
    }
    if let thinking = delta["thinking"] as? String {
      return .reasoningDelta(thinking)
    }
    return nil
  }

  func parseResponseBody(_ data: Data) -> [ChatStreamEvent] {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let content = json["content"] as? [[String: Any]]
    else {
      return []
    }

    var events: [ChatStreamEvent] = []
    let text = content.compactMap(contentPartText).joined()
    if !text.isEmpty {
      events.append(.delta(text))
    }
    if let usage = usage(
      from: json["usage"] as? [String: Any], inputKey: "input_tokens", outputKey: "output_tokens")
    {
      events.append(.usage(usage))
    }
    appendGenericText(from: json, to: &events)
    if !events.isEmpty {
      events.append(.completed)
    }
    return events
  }

  private func body(_ request: ChatRequest) -> [String: Any] {
    let contentMessages = request.messages.filter { $0.role != .system }
    let thinkingBudget = request.assistant.reasoningEffort.anthropicBudgetTokens
    var payload: [String: Any] = [
      "model": request.modelId,
      "stream": true,
      "max_tokens": thinkingBudget.map { max(request.assistant.maxTokens, $0 + 1) }
        ?? request.assistant.maxTokens,
      "temperature": request.assistant.temperature,
      "system": systemInstructions(for: request) ?? "",
      "messages": contentMessages.map {
        ["role": $0.role.rawValue, "content": anthropicContent($0)]
      },
    ]

    if let budget = thinkingBudget {
      payload["thinking"] = ["type": "enabled", "budget_tokens": budget]
    }

    return payload
  }
}

extension ChatRequest {
  fileprivate var modelId: String {
    assistant.modelId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? provider.defaultModel
      : assistant.modelId
  }
}

func chatAdapter(for kind: ProviderKind) -> ChatModelAdapter {
  switch kind {
  case .openAIChatCompletions:
    OpenAIChatCompletionsAdapter()
  case .openAIResponses:
    OpenAIResponsesAdapter()
  case .anthropicMessages:
    AnthropicMessagesAdapter()
  }
}

private func usage(from payload: [String: Any]?, inputKey: String, outputKey: String) -> TokenUsage?
{
  guard let payload else { return nil }
  let usage = TokenUsage(
    inputTokens: intValue(payload[inputKey]),
    outputTokens: intValue(payload[outputKey]),
    totalTokens: intValue(payload["total_tokens"])
  )
  guard usage.inputTokens != nil || usage.outputTokens != nil || usage.totalTokens != nil else {
    return nil
  }
  return usage
}

private func intValue(_ value: Any?) -> Int? {
  if let value = value as? Int {
    return value
  }
  if let value = value as? Double {
    return Int(value)
  }
  if let value = value as? String {
    return Int(value)
  }
  return nil
}

private func messageContent(_ message: [String: Any]) -> String? {
  if let content = textValue(message["content"]) {
    return content
  }
  if let content = message["content"] as? [[String: Any]] {
    let text = content.compactMap(contentPartText).joined()
    return text.isEmpty ? nil : text
  }
  return nil
}

private func messageReasoningContent(_ message: [String: Any]) -> String? {
  textValue(message["reasoning_content"])
    ?? textValue(message["reasoning"])
}

private func outputItemText(_ item: [String: Any]) -> String? {
  if let text = textValue(item["text"]) {
    return text
  }
  if let content = item["content"] as? [[String: Any]] {
    let text = content.compactMap(contentPartText).joined()
    return text.isEmpty ? nil : text
  }
  return nil
}

private func contentPartText(_ item: [String: Any]) -> String? {
  textValue(item["text"])
    ?? textValue(item["content"])
    ?? textValue(item["output_text"])
}

private func appendGenericText(from json: [String: Any], to events: inout [ChatStreamEvent]) {
  guard
    !events.contains(where: { event in
      if case .delta = event { return true }
      return false
    })
  else {
    return
  }

  for key in ["text", "content", "message", "response", "output"] {
    if let text = textValue(json[key]), !text.isEmpty {
      events.append(.delta(text))
      return
    }
  }

  if let data = json["data"] as? [String: Any] {
    appendGenericText(from: data, to: &events)
  }
}

private func textValue(_ value: Any?) -> String? {
  if value is NSNull {
    return nil
  }
  if let value = value as? String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : value
  }
  return nil
}

private func streamTextValue(_ value: Any?) -> String? {
  guard let value = value as? String, !value.isEmpty else { return nil }
  return value
}
