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

    func testLargeStreamingBurstCatchesUpAtHighTokenRate() {
        let player = SmoothStreamPlayer(initialText: "", automaticallyStartsPlayback: false)
        let fullText = String(repeating: "token ", count: 1_000)

        player.update(accumulatedText: fullText, isStreaming: true)

        var frameCount = 0
        while player.displayedText != fullText && frameCount < 12 {
            player.advanceOneFrame()
            frameCount += 1
        }

        XCTAssertEqual(player.displayedText, fullText)
        XCTAssertLessThanOrEqual(frameCount, 12)
    }

    func testLargeStreamingBurstCapsLiveBacklog() {
        let player = SmoothStreamPlayer(initialText: "", automaticallyStartsPlayback: false)
        let fullText = String(repeating: "a", count: 1_000)

        player.update(accumulatedText: fullText, isStreaming: true)
        player.advanceOneFrame()

        XCTAssertGreaterThanOrEqual(player.displayedText.count, 600)
    }

    func testFinishingStreamShowsFullTextImmediately() {
        let player = SmoothStreamPlayer(initialText: "", automaticallyStartsPlayback: false)
        let fullText = String(repeating: "这是平滑吐字。", count: 12)

        player.update(accumulatedText: fullText, isStreaming: true)
        player.update(accumulatedText: fullText, isStreaming: false)

        XCTAssertEqual(player.displayedText, fullText)
    }
}
