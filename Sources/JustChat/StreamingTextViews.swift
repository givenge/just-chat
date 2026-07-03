import Combine
import SwiftUI

@MainActor
final class SmoothStreamPlayer: ObservableObject {
    @Published private(set) var displayedText: String

    private var pendingText = ""
    private var playbackTask: Task<Void, Never>?
    private var lastAccumulatedText: String
    private var streamDone = true
    private var pauseFramesRemaining = 0
    private let frameIntervalMilliseconds: Int
    private let automaticallyStartsPlayback: Bool

    init(
        initialText: String,
        frameIntervalMilliseconds: Int = 16,
        automaticallyStartsPlayback: Bool = true
    ) {
        displayedText = initialText
        lastAccumulatedText = initialText
        self.frameIntervalMilliseconds = frameIntervalMilliseconds
        self.automaticallyStartsPlayback = automaticallyStartsPlayback
    }

    deinit {
        playbackTask?.cancel()
    }

    func update(accumulatedText: String, isStreaming: Bool) {
        streamDone = !isStreaming

        if accumulatedText.hasPrefix(lastAccumulatedText) {
            let delta = String(accumulatedText.dropFirst(lastAccumulatedText.count))
            lastAccumulatedText = accumulatedText
            enqueue(delta)
        } else {
            reset(to: accumulatedText, isStreaming: isStreaming)
        }

        if streamDone && pendingText.isEmpty {
            displayedText = accumulatedText
            stopPlayback()
            return
        }

        ensurePlayback()
    }

    private func reset(to text: String, isStreaming: Bool) {
        pendingText.removeAll(keepingCapacity: true)
        pauseFramesRemaining = 0
        lastAccumulatedText = text
        displayedText = text
        streamDone = !isStreaming
    }

    private func enqueue(_ delta: String) {
        guard !delta.isEmpty else { return }
        pendingText += delta
    }

    private func ensurePlayback() {
        guard automaticallyStartsPlayback else { return }
        guard playbackTask == nil else { return }
        playbackTask = Task { [weak self] in
            await self?.playbackLoop()
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        pauseFramesRemaining = 0
    }

    private func playbackLoop() async {
        while !Task.isCancelled {
            if pendingText.isEmpty {
                if streamDone { break }
                try? await Task.sleep(for: .milliseconds(frameIntervalMilliseconds))
                continue
            }

            if shouldPauseFrame() {
                pauseFramesRemaining -= 1
            } else {
                advanceOneFrame()
            }
            try? await Task.sleep(for: .milliseconds(frameIntervalMilliseconds))
        }
        if streamDone {
            displayedText = lastAccumulatedText
        }
        playbackTask = nil
    }

    @discardableResult
    func advanceOneFrame() -> Int {
        guard !pendingText.isEmpty else { return 0 }

        let chunkSize = nextChunkSize()
        let endIndex = pendingText.index(
            pendingText.startIndex,
            offsetBy: chunkSize,
            limitedBy: pendingText.endIndex
        ) ?? pendingText.endIndex
        let chunk = String(pendingText[..<endIndex])
        pendingText.removeSubrange(..<endIndex)
        displayedText += chunk

        pauseFramesRemaining = streamDone ? 0 : pauseFrames(after: chunk)
        return chunk.count
    }

    private func shouldPauseFrame() -> Bool {
        pauseFramesRemaining > 0 && !streamDone && pendingText.count < 80
    }

    private func nextChunkSize() -> Int {
        let pendingCount = pendingText.count
        guard pendingCount > 0 else { return 0 }

        if streamDone {
            return min(pendingCount, max(4, min(32, pendingCount / 6)))
        }

        switch pendingCount {
        case 1...16:
            return 1
        case 17...48:
            return 2
        case 49...120:
            return 4
        case 121...240:
            return 8
        default:
            return min(24, max(12, pendingCount / 24))
        }
    }

    private func pauseFrames(after chunk: String) -> Int {
        guard let lastScalar = chunk.unicodeScalars.last else { return 0 }
        if CharacterSet.newlines.contains(lastScalar) {
            return 2
        }
        if CharacterSet(charactersIn: ".!?。！？…").contains(lastScalar) {
            return 2
        }
        if CharacterSet(charactersIn: ",，、;；:：").contains(lastScalar), pendingText.count < 80 {
            return 1
        }
        return 0
    }
}

struct SmoothStreamingMarkdownView: View {
    let content: String
    let isStreaming: Bool
    var fontSize: CGFloat = 15
    var frameIntervalMilliseconds: Int = 33

    @StateObject private var player: SmoothStreamPlayer

    init(
        content: String,
        isStreaming: Bool,
        fontSize: CGFloat = 15,
        frameIntervalMilliseconds: Int = 33
    ) {
        self.content = content
        self.isStreaming = isStreaming
        self.fontSize = fontSize
        self.frameIntervalMilliseconds = frameIntervalMilliseconds
        _player = StateObject(wrappedValue: SmoothStreamPlayer(
            initialText: content,
            frameIntervalMilliseconds: frameIntervalMilliseconds
        ))
    }

    var body: some View {
        MarkdownText(content: player.displayedText, fontSize: fontSize)
            .onAppear {
                player.update(accumulatedText: content, isStreaming: isStreaming)
            }
            .onChange(of: content) {
                player.update(accumulatedText: content, isStreaming: isStreaming)
            }
            .onChange(of: isStreaming) {
                player.update(accumulatedText: content, isStreaming: isStreaming)
            }
    }
}

struct SmoothStreamingTextView: View {
    let text: String
    let isStreaming: Bool
    var fontSize: CGFloat = 13
    var foregroundStyle: AnyShapeStyle = AnyShapeStyle(.secondary)
    var lineSpacing: CGFloat = 4
    var topPadding: CGFloat = 8

    @StateObject private var player: SmoothStreamPlayer

    init(
        text: String,
        isStreaming: Bool,
        fontSize: CGFloat = 13,
        foregroundStyle: AnyShapeStyle = AnyShapeStyle(.secondary),
        lineSpacing: CGFloat = 4,
        topPadding: CGFloat = 8
    ) {
        self.text = text
        self.isStreaming = isStreaming
        self.fontSize = fontSize
        self.foregroundStyle = foregroundStyle
        self.lineSpacing = lineSpacing
        self.topPadding = topPadding
        _player = StateObject(wrappedValue: SmoothStreamPlayer(initialText: text, frameIntervalMilliseconds: 16))
    }

    var body: some View {
        Text(player.displayedText)
            .font(.system(size: fontSize))
            .foregroundStyle(foregroundStyle)
            .lineSpacing(lineSpacing)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .onAppear {
                player.update(accumulatedText: text, isStreaming: isStreaming)
            }
            .onChange(of: text) {
                player.update(accumulatedText: text, isStreaming: isStreaming)
            }
            .onChange(of: isStreaming) {
                player.update(accumulatedText: text, isStreaming: isStreaming)
            }
    }
}
