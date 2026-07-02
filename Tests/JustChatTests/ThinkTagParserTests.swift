import XCTest
@testable import JustChat

final class ThinkTagParserTests: XCTestCase {
    func testSplitsThinkTagFromVisibleContent() {
        var parser = ThinkTagParser()

        let first = parser.append("<think>hidden</think>visible")
        let final = parser.finish()

        XCTAssertEqual(first.reasoning, "hidden")
        XCTAssertEqual(first.content, "visible")
        XCTAssertEqual(final.reasoning, "")
        XCTAssertEqual(final.content, "")
    }

    func testHandlesThinkTagsAcrossChunks() {
        var parser = ThinkTagParser()

        let first = parser.append("<thi")
        let second = parser.append("nk>hidden</thi")
        let third = parser.append("nk>visible")

        XCTAssertEqual(first.content, "")
        XCTAssertEqual(first.reasoning, "")
        XCTAssertEqual(second.content, "")
        XCTAssertEqual(second.reasoning, "hidden")
        XCTAssertEqual(third.content, "visible")
        XCTAssertEqual(third.reasoning, "")
    }

    func testFlushesUnclosedThinkTagAsReasoning() {
        var parser = ThinkTagParser()

        let parsed = parser.append("visible<think>hidden")
        let final = parser.finish()

        XCTAssertEqual(parsed.content, "visible")
        XCTAssertEqual(parsed.reasoning, "hidden")
        XCTAssertEqual(final.content, "")
        XCTAssertEqual(final.reasoning, "")
    }
}
