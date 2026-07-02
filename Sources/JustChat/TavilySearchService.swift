import Foundation

struct TavilySearchService: Sendable {
    var endpoint: URL = URL(string: "https://api.tavily.com/search")!
    var session: URLSession = .shared

    func search(query: String, maxResults: Int, apiKey: String) async throws -> [SearchResult] {
        let request = try makeRequest(query: query, maxResults: maxResults, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw TavilySearchError.httpStatus(http.statusCode, String(data: data, encoding: .utf8))
        }
        return try parseResponse(data)
    }

    func makeRequest(query: String, maxResults: Int, apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 20
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "query": query,
                "max_results": maxResults
            ],
            options: []
        )
        return request
    }

    func parseResponse(_ data: Data) throws -> [SearchResult] {
        let payload = try JSONDecoder().decode(TavilyResponse.self, from: data)
        return payload.results.compactMap { item in
            guard let url = URL(string: item.url) else { return nil }
            return SearchResult(
                id: UUID(),
                title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                content: item.content.trimmingCharacters(in: .whitespacesAndNewlines),
                url: url,
                provider: "tavily"
            )
        }
    }
}

enum TavilySearchError: Error, LocalizedError {
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .httpStatus(let status, let body):
            if let body, !body.isEmpty {
                return "Tavily search failed with HTTP \(status): \(body)"
            }
            return "Tavily search failed with HTTP \(status)."
        }
    }
}

private struct TavilyResponse: Decodable {
    var results: [TavilyResult]
}

private struct TavilyResult: Decodable {
    var title: String
    var content: String
    var url: String
}
