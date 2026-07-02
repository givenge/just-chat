import Foundation

final class ChatStreamEventQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ChatStreamEvent] = []

    func append(_ event: ChatStreamEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func drain() -> [ChatStreamEvent] {
        lock.lock()
        defer { lock.unlock() }

        guard !events.isEmpty else { return [] }
        let drained = events
        events.removeAll(keepingCapacity: true)
        return Self.coalesced(drained)
    }

    private static func coalesced(_ events: [ChatStreamEvent]) -> [ChatStreamEvent] {
        var merged: [ChatStreamEvent] = []
        for event in events {
            switch event {
            case .delta(let text):
                if case .delta(let existing)? = merged.last {
                    merged[merged.count - 1] = .delta(existing + text)
                } else {
                    merged.append(event)
                }
            case .reasoningDelta(let text):
                if case .reasoningDelta(let existing)? = merged.last {
                    merged[merged.count - 1] = .reasoningDelta(existing + text)
                } else {
                    merged.append(event)
                }
            default:
                merged.append(event)
            }
        }
        return merged
    }
}
