import XCTest
import Markdown
@testable import JustChat

final class MarkdownViewTests: XCTestCase {
    func testSyntaxHighlighterPreservesSourceText() {
        let code = "func greet(_ name: String) { print(\"hi\") }"
        let highlighted = SyntaxHighlighter.highlight(code: code, language: "swift")
        let reconstructed = String(highlighted.characters)
        XCTAssertTrue(reconstructed.contains("func"))
        XCTAssertTrue(reconstructed.contains("greet"))
        XCTAssertTrue(reconstructed.contains("\"hi\""))
    }

    func testSyntaxHighlighterHandlesUnknownLanguageWithoutCrashing() {
        let highlighted = SyntaxHighlighter.highlight(code: "x = 1 # comment", language: nil)
        XCTAssertEqual(String(highlighted.characters), "x = 1 # comment")
    }

    func testAttributedStringParsesChineseStrongEmphasisInParagraphMarkdown() throws {
        let sample = "- **极端场景（Edge Cases）验证**：为确保该问题得到彻底解决。\n  **跨年、闰年、季度末及年末** 等特殊时间节点。"
        let document = Document(parsing: sample)
        let list = try XCTUnwrap(Array(document.children).first as? UnorderedList)
        let item = try XCTUnwrap(Array(list.children).first as? ListItem)
        let paragraphs = item.children.compactMap { $0 as? Paragraph }
        let mergedMarkdown = paragraphs.map { $0.format() }.joined(separator: "\n")

        let rendered = try AttributedString(markdown: mergedMarkdown)
        let text = String(rendered.characters)

        XCTAssertTrue(text.contains("极端场景（Edge Cases）验证"))
        XCTAssertTrue(text.contains("跨年、闰年、季度末及年末"))
        XCTAssertFalse(text.contains("**"))
    }

    func testNormalizesHeadingWithoutSpaceAfterHashes() throws {
        let normalized = MarkdownText.normalizedMarkdown("###🔔 生活建议")
        let document = Document(parsing: normalized)
        let heading = try XCTUnwrap(Array(document.children).first as? Heading)

        XCTAssertEqual(heading.level, 3)
        XCTAssertTrue(heading.plainText.contains("🔔 生活建议"))
    }

    func testDoesNotNormalizeHeadingMarkersInsideCodeFence() {
        let sample = "```markdown\n###标题\n```"
        let normalized = MarkdownText.normalizedMarkdown(sample)

        XCTAssertEqual(normalized, sample)
    }
}
