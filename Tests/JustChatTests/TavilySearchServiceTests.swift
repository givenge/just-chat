import XCTest
@testable import JustChat

final class TavilySearchServiceTests: XCTestCase {
    func testParsesSearchResults() throws {
        let data = Data(
            """
            {
              "results": [
                {
                  "title": " Tavily ",
                  "content": " Search API ",
                  "url": "https://docs.tavily.com"
                }
              ]
            }
            """.utf8
        )

        let results = try TavilySearchService().parseResponse(data)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Tavily")
        XCTAssertEqual(results[0].content, "Search API")
    }
}
