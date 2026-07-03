import XCTest
@testable import JustChat

@MainActor
final class SmoothStreamPlayerTests: XCTestCase {
    func testLongDeltaIsPacedAcrossFrames() {
        let player = SmoothStreamPlayer(initialText: "", automaticallyStartsPlayback: false)
        let fullText = String(repeating: "流", count: 120)

        player.update(accumulatedText: fullText, isStreaming: true)
        let consumed = player.advanceOneFrame()

        XCTAssertGreaterThan(consumed, 0)
        XCTAssertLessThan(player.displayedText.count, fullText.count)
        XCTAssertTrue(fullText.hasPrefix(player.displayedText))
    }

    func testFinishingStreamCatchesUpWithoutImmediateJump() {
        let player = SmoothStreamPlayer(initialText: "", automaticallyStartsPlayback: false)
        let fullText = String(repeating: "这是平滑吐字。", count: 12)

        player.update(accumulatedText: fullText, isStreaming: true)
        player.update(accumulatedText: fullText, isStreaming: false)

        let firstFrameCount = player.advanceOneFrame()
        XCTAssertGreaterThan(firstFrameCount, 0)
        XCTAssertLessThanOrEqual(firstFrameCount, 8)
        XCTAssertLessThan(player.displayedText.count, fullText.count)

        var frameCount = 1
        while player.displayedText != fullText && frameCount < 80 {
            player.advanceOneFrame()
            frameCount += 1
        }

        XCTAssertEqual(player.displayedText, fullText)
        XCTAssertLessThan(frameCount, 80)
    }
}
