import Foundation

enum ModelListFetcher {
    struct ModelListResponse: Codable {
        let data: [ModelItem]
        struct ModelItem: Codable {
            let id: String
        }
    }

    /// Fetches the available model list from a provider's `/models` endpoint.
    /// Uses the OpenAI-compatible format: `{"data": [{"id": "model-name"}, ...]}`.
    static func fetchModels(baseURL: URL, apiKey: String) async throws -> [String] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoder = JSONDecoder()
        let modelList = try decoder.decode(ModelListResponse.self, from: data)
        return modelList.data.map(\.id).sorted()
    }
}