import Foundation

private struct OpenAIToolCall {
    var id = ""
    var name = ""
    var arguments = ""

    var query: String? {
        guard name == "web_search",
              let data = arguments.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String
        else { return nil }
        return query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ChatSessionService: Sendable {
    var tavily = TavilySearchService()
    var session: URLSession = .shared
    var searchSettings: SearchSettings = .default

    func run(_ request: ChatRequest, onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void) async throws {
        if request.webSearchMode == .tavily, request.provider.kind == .openAIChatCompletions {
            try await runOpenAICompatibleWebSearchTool(request, onEvent: onEvent)
            return
        }

        var executableRequest = request
        if executableRequest.webSearchMode == .providerNative {
            executableRequest = withCurrentTimeContext(executableRequest, now: Date())
        }
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
        let now = Date()
        var toolRequest = withCurrentTimeContext(request, now: now)
        toolRequest.searchResults = []

        let apiKey = try readAPIKey(for: toolRequest.provider)
        let adapter = chatAdapter(for: toolRequest.provider.kind)
        let toolURLRequest = try adapter.makeRequest(toolRequest, apiKey: apiKey)
        let toolCalls = try await runOpenAITavilyToolStream(
            toolURLRequest,
            adapter: adapter
        )

        let queries = toolCalls.compactMap(\.query).filter { !$0.isEmpty }
        guard !queries.isEmpty else {
            await onEvent(.completed)
            return
        }

        let results = try await runTavilySearches(queries: queries)
        for result in results {
            await onEvent(.citation(Citation(
                id: UUID(),
                title: result.title,
                url: result.url,
                snippet: result.content
            )))
        }

        var finalRequest = request
        finalRequest.webSearchMode = .disabled
        finalRequest.searchResults = results
        finalRequest = injectSearchContextIfNeeded(finalRequest)
        finalRequest = withCurrentTimeContext(finalRequest, now: now)
        try await runStreamingRequest(finalRequest, onEvent: onEvent)
    }

    private func runOpenAITavilyToolStream(
        _ urlRequest: URLRequest,
        adapter: ChatModelAdapter
    ) async throws -> [OpenAIToolCall] {
        let (bytes, response) = try await session.bytes(for: urlRequest)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: try await collectData(from: bytes), encoding: .utf8) ?? ""
            throw ChatSessionError.httpStatus(http.statusCode, body)
        }

        var eventName: String?
        var dataLines: [String] = []
        var toolCalls: [Int: OpenAIToolCall] = [:]

        func flushEvent() async -> Bool {
            guard !dataLines.isEmpty else {
                eventName = nil
                return false
            }

            let event = SSEEvent(event: eventName, data: dataLines.joined(separator: "\n"))
            eventName = nil
            dataLines = []

            collectToolCalls(from: event, into: &toolCalls)
            guard let chatEvent = adapter.parseEvent(event) else {
                return false
            }
            if case .completed = chatEvent { return true }
            return false
        }

        func processLine(_ line: String) async -> Bool {
            if line.isEmpty {
                return await flushEvent()
            }
            if line.hasPrefix(":") {
                return false
            }
            if line.hasPrefix("event:") {
                if await flushEvent() { return true }
                eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                return false
            }
            if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
            return false
        }

        var lineData = Data()
        for try await byte in bytes {
            if byte == 10 {
                var line = String(data: lineData, encoding: .utf8) ?? ""
                if line.last == "\r" {
                    line.removeLast()
                }
                lineData.removeAll(keepingCapacity: true)
                if await processLine(line) { break }
            } else {
                lineData.append(byte)
            }
        }

        if !lineData.isEmpty {
            var line = String(data: lineData, encoding: .utf8) ?? ""
            if line.last == "\r" {
                line.removeLast()
            }
            _ = await processLine(line)
        }
        _ = await flushEvent()
        return toolCalls.keys.sorted().compactMap { toolCalls[$0] }
    }

    private func collectToolCalls(from event: SSEEvent, into toolCalls: inout [Int: OpenAIToolCall]) {
        guard event.data != "[DONE]",
              let data = event.data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let chunks = delta["tool_calls"] as? [[String: Any]]
        else { return }

        for chunk in chunks {
            let index = toolCallIndex(chunk["index"]) ?? 0
            var call = toolCalls[index] ?? OpenAIToolCall()
            if let id = chunk["id"] as? String {
                call.id = id
            }
            if let function = chunk["function"] as? [String: Any] {
                if let name = function["name"] as? String {
                    call.name = name
                }
                if let arguments = function["arguments"] as? String {
                    call.arguments += arguments
                }
            }
            toolCalls[index] = call
        }
    }

    private func toolCallIndex(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        return nil
    }

    private func runStreamingRequest(
        _ request: ChatRequest,
        onEvent: @escaping @Sendable (ChatStreamEvent) async -> Void
    ) async throws {
        var executableRequest = request
        let apiKey = try readAPIKey(for: executableRequest.provider)
        let adapter = chatAdapter(for: executableRequest.provider.kind)
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

        func processLine(_ line: String) async -> Bool {
            rawResponse.append(line)
            rawResponse.append("\n")

            if line.isEmpty {
                return await flushEvent()
            }

            if line.hasPrefix(":") {
                return false
            }

            if line.hasPrefix("event:") {
                if await flushEvent() { return true }
                eventName = String(line.dropFirst("event:".count)).trimmingCharacters(in: .whitespaces)
                return false
            }

            if line.hasPrefix("data:") {
                dataLines.append(String(line.dropFirst("data:".count)).trimmingCharacters(in: .whitespaces))
            }
            return false
        }

        var lineData = Data()
        for try await byte in bytes {
            if byte == 10 {
                var line = String(data: lineData, encoding: .utf8) ?? ""
                if line.last == "\r" {
                    line.removeLast()
                }
                lineData.removeAll(keepingCapacity: true)
                if await processLine(line) { return }
            } else {
                lineData.append(byte)
            }
        }

        if !lineData.isEmpty {
            var line = String(data: lineData, encoding: .utf8) ?? ""
            if line.last == "\r" {
                line.removeLast()
            }
            if await processLine(line) { return }
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

    private func withCurrentTimeContext(_ request: ChatRequest, now: Date) -> ChatRequest {
        var request = request
        let timeMessage = ChatMessage(
            id: UUID(),
            conversationId: request.messages.last?.conversationId ?? UUID(),
            role: .system,
            content: currentTimeContext(now: now),
            reasoningContent: "",
            citations: [],
            attachments: [],
            status: .success,
            usage: nil,
            createdAt: now,
            updatedAt: now
        )
        request.messages.insert(timeMessage, at: 0)
        return request
    }

    private func currentTimeContext(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        let timeZone = TimeZone.current.identifier
        return """
        Current date and time: \(formatter.string(from: now)).
        Time zone: \(timeZone).
        Use this as "today" and "now" when deciding whether to search, writing web search queries, and judging freshness of search results.
        """
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
