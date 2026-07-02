import Foundation

struct ChatSessionService: Sendable {
    var adapterFactory = ChatAdapterFactory()
    var tavily = TavilySearchService()
    var session: URLSession = .shared
    var searchSettings: SearchSettings = .default

    func run(_ request: ChatRequest, onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void) async throws {
        if request.webSearchMode == .tavily, request.provider.kind == .openAIChatCompletions {
            try await runOpenAICompatibleWebSearchTool(request, onEvent: onEvent)
            return
        }

        var executableRequest = request
        if request.webSearchMode == .tavily {
            executableRequest.webSearchMode = .disabled
        }
        executableRequest = injectSearchContextIfNeeded(executableRequest)
        try await runStreamingRequest(executableRequest, onEvent: onEvent)
    }

    private func runOpenAICompatibleWebSearchTool(
        _ request: ChatRequest,
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async throws {
        var decisionRequest = request
        decisionRequest.stream = false
        decisionRequest.searchResults = []

        let apiKey = try readAPIKey(for: decisionRequest.provider)
        let adapter = adapterFactory.adapter(for: decisionRequest.provider.kind)
        let decisionURLRequest = try adapter.makeRequest(decisionRequest, apiKey: apiKey)
        let (data, response) = try await session.data(for: decisionURLRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ChatSessionError.httpStatus(http.statusCode, body)
        }

        let queries = webSearchQueries(from: data)
        guard !queries.isEmpty else {
            let events = adapter.parseResponseBody(data)
            guard !events.isEmpty else {
                if let providerError = providerErrorMessage(from: data) {
                    throw ChatAdapterError.providerError(providerError)
                }
                throw ChatAdapterError.unusableResponse(responsePreview(String(data: data, encoding: .utf8) ?? ""))
            }
            for event in events {
                await onEvent(event)
                if case .completed = event { return }
            }
            await onEvent(.completed)
            return
        }

        for event in adapter.parseResponseBody(data) {
            if case .reasoningDelta = event {
                await onEvent(event)
            }
        }

        let results = try await runTavilySearches(queries: queries)
        for result in results {
            await onEvent(.citation(Citation(
                id: UUID(),
                title: result.title,
                url: result.url,
                snippet: result.content,
                source: result.provider
            )))
        }

        var finalRequest = request
        finalRequest.webSearchMode = .disabled
        finalRequest.searchResults = results
        finalRequest = injectSearchContextIfNeeded(finalRequest)
        try await runStreamingRequest(finalRequest, onEvent: onEvent)
    }

    private func runStreamingRequest(
        _ request: ChatRequest,
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async throws {
        var executableRequest = request
        let apiKey = try readAPIKey(for: executableRequest.provider)
        let adapter = adapterFactory.adapter(for: executableRequest.provider.kind)
        let urlRequest = try adapter.makeRequest(executableRequest, apiKey: apiKey)
        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch let error as URLError where error.code == .timedOut && executableRequest.webSearchMode == .providerNative {
            executableRequest.webSearchMode = .disabled
            let retryRequest = try adapter.makeRequest(executableRequest, apiKey: apiKey)
            (bytes, response) = try await session.bytes(for: retryRequest)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: try await collectData(from: bytes), encoding: .utf8) ?? ""
            throw ChatSessionError.httpStatus(http.statusCode, body)
        }

        var rawResponse = ""
        var emittedEvent = false
        var eventName: String?
        var dataLines: [String] = []

        func flushEvent() async -> Bool {
            guard !dataLines.isEmpty else {
                eventName = nil
                return false
            }

            let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
            eventName = nil
            dataLines = []

            guard let chatEvent = adapter.parseEvent(event) else {
                return false
            }

            emittedEvent = true
            await onEvent(chatEvent)
            if case .completed = chatEvent {
                return true
            }
            return false
        }

        for try await line in bytes.lines {
            rawResponse.append(line)
            rawResponse.append("\n")

            if line.isEmpty {
                if await flushEvent() { return }
                continue
            }

            if line.hasPrefix(":") {
                continue
            }

            if line.hasPrefix("event:") {
                if await flushEvent() { return }
                eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
                if eventName == nil, await flushEvent() {
                    return
                }
            }
        }

        if await flushEvent() { return }

        if emittedEvent {
            await onEvent(.completed)
            return
        }

        let rawData = Data(rawResponse.utf8)
        let bodyEvents = adapter.parseResponseBody(rawData)
        guard !bodyEvents.isEmpty else {
            if let providerError = providerErrorMessage(from: rawData) {
                throw ChatAdapterError.providerError(providerError)
            }
            throw ChatAdapterError.unusableResponse(responsePreview(rawResponse))
        }

        for event in bodyEvents {
            await onEvent(event)
            if case .completed = event {
                return
            }
        }
        await onEvent(.completed)
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func providerErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"]
        else {
            return nil
        }

        if let text = error as? String {
            return text
        }

        if let object = error as? [String: Any] {
            return (object["message"] as? String)
                ?? (object["type"] as? String)
                ?? "\(object)"
        }

        return "\(error)"
    }

    private func responsePreview(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > 600 else { return compact }
        return "\(compact.prefix(600))..."
    }

    private func readAPIKey(for provider: ModelProvider) throws -> String {
        let apiKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ChatSessionError.missingAPIKey(provider.name)
        }
        return apiKey
    }

    private func runTavilySearches(queries: [String]) async throws -> [SearchResult] {
        let apiKey = searchSettings.tavilyAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw ChatSessionError.missingAPIKey("Tavily")
        }
        var seenURLs = Set<URL>()
        var merged: [SearchResult] = []
        for query in queries.prefix(3) {
            let results = try await tavily.search(query: query, maxResults: searchSettings.tavilyMaxResults, apiKey: apiKey)
            for result in results where seenURLs.insert(result.url).inserted {
                merged.append(result)
            }
        }
        return merged
    }

    private func injectSearchContextIfNeeded(_ request: ChatRequest) -> ChatRequest {
        guard !request.searchResults.isEmpty else {
            return request
        }

        var request = request
        let context = request.searchResults.enumerated().map { index, result in
            "[\(index + 1)] \(result.title)\nURL: \(result.url.absoluteString)\n\(result.content)"
        }.joined(separator: "\n\n")

        let searchContextMessage = ChatMessage(
            id: UUID(),
            conversationId: request.messages.last?.conversationId ?? UUID(),
            role: .system,
            content: "Use these Tavily web search results as current context. Cite sources by title or URL when relevant.\n\n\(context)",
            reasoningContent: "",
            citations: [],
            attachments: [],
            status: .success,
            usage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        request.messages.insert(searchContextMessage, at: 0)
        return request
    }

    private func webSearchQueries(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]]
        else { return [] }

        return choices.flatMap { choice -> [String] in
            guard let message = choice["message"] as? [String: Any],
                  let calls = message["tool_calls"] as? [[String: Any]]
            else { return [] }
            return calls.compactMap { call in
                guard let function = call["function"] as? [String: Any],
                      function["name"] as? String == "web_search",
                      let arguments = function["arguments"] as? String,
                      let data = arguments.data(using: .utf8),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let query = payload["query"] as? String
                else { return nil }
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }
}

enum ChatSessionError: Error, LocalizedError {
    case missingAPIKey(String)
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let name):
            "请先在设置中填写 \(name) 的 API Key。"
        case .httpStatus(let status, let body):
            body.isEmpty ? "Model request failed with HTTP \(status)." : "Model request failed with HTTP \(status): \(body)"
        }
    }
}
