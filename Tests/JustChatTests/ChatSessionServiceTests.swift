import Foundation
import XCTest

@testable import JustChat

final class ChatSessionServiceTests: XCTestCase {
  func testStreamsNamelessMultilineDataEventAsOneSSEEvent() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.responseData = Data([
      #"data: {"choices":[{"delta":"#,
      #"data: {"content":"hello"},"finish_reason":null}]}"#,
      "",
      "data: [DONE]",
      "",
    ].joined(separator: "\n").utf8)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let service = ChatSessionService(session: URLSession(configuration: configuration))
    let accumulator = EventAccumulator()

    try await service.run(testRequest()) { event in
      await accumulator.append(event)
    }

    let events = await accumulator.events
    XCTAssertEqual(events, [.delta("hello"), .completed])
  }

  func testTavilyToolProbeDoesNotEmitModelAnswerWithoutToolCall() async throws {
    MockURLProtocol.reset()
    MockURLProtocol.responseData = Data([
      #"data: {"choices":[{"delta":{"content":"hello"},"finish_reason":null}]}"#,
      "",
      "data: [DONE]",
      "",
    ].joined(separator: "\n").utf8)

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let service = ChatSessionService(session: URLSession(configuration: configuration))
    let accumulator = EventAccumulator()

    try await service.run(testRequest(webSearchMode: .tavily)) { event in
      await accumulator.append(event)
    }

    let events = await accumulator.events
    XCTAssertEqual(events, [.completed])
    XCTAssertEqual(MockURLProtocol.requestBodies.count, 1)
    let body = try XCTUnwrap(MockURLProtocol.requestBodies.first)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
    let timeMessage = try XCTUnwrap(messages.first)
    XCTAssertEqual(timeMessage["role"] as? String, "system")
    let content = try XCTUnwrap(timeMessage["content"] as? String)
    XCTAssertTrue(content.contains("Current date and time:"))
    XCTAssertTrue(content.contains("Use this as \"today\" and \"now\""))
  }
}

private actor EventAccumulator {
  var events: [ChatStreamEvent] = []

  func append(_ event: ChatStreamEvent) {
    events.append(event)
  }
}

private final class MockURLProtocol: URLProtocol {
  nonisolated(unsafe) static var responseData = Data()
  nonisolated(unsafe) static var requestBodies: [Data] = []

  nonisolated static func reset() {
    responseData = Data()
    requestBodies = []
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    Self.requestBodies.append(Self.bodyData(from: request))
    client?.urlProtocol(
      self,
      didReceive: HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: ["Content-Type": "text/event-stream"]
      )!,
      cacheStoragePolicy: .notAllowed
    )
    client?.urlProtocol(self, didLoad: Self.responseData)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}

  private static func bodyData(from request: URLRequest) -> Data {
    if let body = request.httpBody {
      return body
    }
    guard let stream = request.httpBodyStream else {
      return Data()
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 {
        break
      }
      data.append(buffer, count: count)
    }
    return data
  }
}

private func testRequest(webSearchMode: WebSearchMode = .disabled) -> ChatRequest {
  let provider = ModelProvider(
    id: UUID(),
    providerType: .openAI,
    kind: .openAIChatCompletions,
    name: "OpenAI",
    baseURL: URL(string: "https://example.com/v1")!,
    apiKey: "secret",
    models: ["model"],
    defaultModel: "model"
  )
  let assistant = AssistantProfile(
    id: UUID(),
    name: "Assistant",
    systemPrompt: "",
    providerId: provider.id,
    modelId: "model",
    temperature: 0.4,
    maxTokens: 128,
    isWebSearchEnabled: false,
    quickTemplates: []
  )
  let message = ChatMessage(
    id: UUID(),
    conversationId: UUID(),
    role: .user,
    content: "Hi",
    reasoningContent: "",
    citations: [],
    attachments: [],
    status: .success,
    usage: nil,
    createdAt: Date(),
    updatedAt: Date()
  )

  return ChatRequest(
    provider: provider,
    assistant: assistant,
    messages: [message],
    webSearchMode: webSearchMode,
    searchResults: []
  )
}
