import XCTest
@testable import JustChat

final class SSEParserTests: XCTestCase {
    func testParsesEventAndDataBlocks() {
        let input = """
        event: response.output_text.delta
        data: {"delta":"Hello"}

        data: [DONE]

        """

        let events = SSEParser().parse(input)

        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].event, "response.output_text.delta")
        XCTAssertEqual(events[0].data, #"{"delta":"Hello"}"#)
        XCTAssertEqual(events[1].data, "[DONE]")
    }
}
