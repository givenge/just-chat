import AppKit
import SwiftUI

private final class FloatingPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let onEscape {
            onEscape()
            return
        }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
            return
        }
        super.cancelOperation(sender)
    }
}

private final class WindowDragRegionView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
final class QuickAssistantController: NSObject, NSWindowDelegate {
    private var panel: FloatingPanel?
    private var lastFrame: NSRect?
    private var isPinned = false

    func toggle(
        assistant: AssistantProfile,
        provider: ModelProvider,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        if panel?.isVisible == true {
            closePanel()
        } else {
            show(
                assistant: assistant,
                provider: provider,
                searchSettings: searchSettings,
                preferences: preferences
            )
        }
    }

    func show(
        assistant: AssistantProfile,
        provider: ModelProvider,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        let isNewPanel = panel == nil
        let panel = panel ?? makePanel(title: "快捷助手", size: NSSize(width: 620, height: 500))
        let frameToRestore = lastFrame
        panel.setContentSize(NSSize(width: 620, height: 500))
        panel.delegate = self
        panel.onEscape = { [weak self] in
            self?.closePanel()
        }
        applyPinState(panel)
        applyPanelAppearance(panel, preferences: preferences)
        panel.contentView = NSHostingView(rootView: QuickAssistantPanel(
            assistant: assistant,
            provider: provider,
            searchSettings: searchSettings,
            preferences: preferences,
            initialPinned: isPinned,
            onPinChanged: { [weak self] pinned in self?.setPinned(pinned) },
            onClose: { [weak self] in self?.closePanel() }
        ))
        if let frameToRestore {
            panel.setFrame(frameToRestore, display: false)
        }
        showPanel(panel, centered: isNewPanel && lastFrame == nil)
        applyPinState(panel)
        self.panel = panel
    }

    func updateAppearance(preferences: AppPreferences) {
        if let panel {
            applyPanelAppearance(panel, preferences: preferences)
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned else { return }
        closePanel()
    }

    private func closePanel() {
        if let panel {
            lastFrame = panel.frame
            panel.delegate = nil
            panel.onEscape = nil
            panel.close()
            panel.contentView = nil
            self.panel = nil
        }
    }

    private func setPinned(_ pinned: Bool) {
        isPinned = pinned
        if let panel {
            applyPinState(panel)
            if pinned {
                panel.orderFrontRegardless()
            }
        }
    }

    private func applyPinState(_ panel: NSPanel) {
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = !isPinned
        panel.level = isPinned ? .statusBar : .floating
        panel.collectionBehavior = isPinned
            ? [.canJoinAllSpaces, .fullScreenAuxiliary]
            : [.moveToActiveSpace, .fullScreenAuxiliary]
    }
}

@MainActor
final class SelectionAssistantController {
    private var toolbarPanel: NSPanel?
    private var actionPanel: NSPanel?

    func toggle(
        selectedText: String,
        selectionBounds: CGRect?,
        assistant: AssistantProfile,
        provider: ModelProvider,
        translationProvider: ModelProvider,
        translationModelId: String,
        translationReasoningEffort: ReasoningEffort,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        if toolbarPanel?.isVisible == true || actionPanel?.isVisible == true {
            toolbarPanel?.close()
            actionPanel?.close()
        } else {
            show(
                selectedText: selectedText,
                selectionBounds: selectionBounds,
                assistant: assistant,
                provider: provider,
                translationProvider: translationProvider,
                translationModelId: translationModelId,
                translationReasoningEffort: translationReasoningEffort,
                searchSettings: searchSettings,
                preferences: preferences
            )
        }
    }

    func show(
        selectedText: String,
        selectionBounds: CGRect?,
        assistant: AssistantProfile,
        provider: ModelProvider,
        translationProvider: ModelProvider,
        translationModelId: String,
        translationReasoningEffort: ReasoningEffort,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        if let toolbarPanel, toolbarPanel.isVisible {
            showPanel(toolbarPanel)
            return
        }
        let text = selectedText
        let panel = makePanel(title: "划词助手", size: NSSize(width: preferences.selectionCompactMode ? 300 : 500, height: 58))
        panel.becomesKeyOnlyIfNeeded = true
        panel.onEscape = { [weak panel] in
            panel?.close()
        }
        applyPanelAppearance(panel, preferences: preferences)
        let hostingView = NSHostingView(rootView: SelectionToolbarPanel(
            selectedText: text,
            compact: preferences.selectionCompactMode,
            onAction: { [weak self] action in
                self?.handle(
                    action,
                    selectedText: text,
                    assistant: assistant,
                    provider: provider,
                    translationProvider: translationProvider,
                    translationModelId: translationModelId,
                    translationReasoningEffort: translationReasoningEffort,
                    searchSettings: searchSettings,
                    preferences: preferences
                )
            },
            onClose: { [weak self] in self?.toolbarPanel?.close() }
        ))
        panel.contentView = hostingView
        let fittingSize = hostingView.fittingSize
        if fittingSize.width > 0 {
            panel.setContentSize(NSSize(width: fittingSize.width, height: 58))
        }
        if let selectionBounds {
            showPanel(panel, centered: false, nearAXRect: selectionBounds)
        } else {
            showPanel(
                panel,
                centered: false,
                nearAXRect: mouseAnchorRect(),
                anchorCoordinateSpace: .appKit
            )
        }
        toolbarPanel = panel
    }

    private func handle(
        _ action: SelectionToolbarAction,
        selectedText: String,
        assistant: AssistantProfile,
        provider: ModelProvider,
        translationProvider: ModelProvider,
        translationModelId: String,
        translationReasoningEffort: ReasoningEffort,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        switch action {
        case .copy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(selectedText, forType: .string)
            if preferences.selectionAutoClose {
                toolbarPanel?.close()
            }
        case .search:
            let query = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty,
                  let url = URL(string: "https://www.google.com/search?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)")
            else { return }
            NSWorkspace.shared.open(url)
            if preferences.selectionAutoClose {
                toolbarPanel?.close()
            }
        case .translate, .explain, .summarize, .ask:
            showActionPanel(
                action: action,
                selectedText: selectedText,
                assistant: assistant,
                provider: provider,
                translationProvider: translationProvider,
                translationModelId: translationModelId,
                translationReasoningEffort: translationReasoningEffort,
                searchSettings: searchSettings,
                preferences: preferences
            )
            if preferences.selectionAutoClose {
                toolbarPanel?.close()
            }
        }
    }

    private func showActionPanel(
        action: SelectionToolbarAction,
        selectedText: String,
        assistant: AssistantProfile,
        provider: ModelProvider,
        translationProvider: ModelProvider,
        translationModelId: String,
        translationReasoningEffort: ReasoningEffort,
        searchSettings: SearchSettings,
        preferences: AppPreferences
    ) {
        if let actionPanel, actionPanel.isVisible {
            actionPanel.close()
        }
        var actionAssistant = assistant
        var actionProvider = provider
        if action == .translate {
            actionProvider = translationProvider
            actionAssistant.providerId = translationProvider.id
            actionAssistant.modelId = translationModelId
            actionAssistant.reasoningEffort = translationReasoningEffort
            actionAssistant.isWebSearchEnabled = false
        }

        let panel = makePanel(title: action.title, size: NSSize(width: 720, height: 480))
        panel.level = preferences.selectionAutoPin ? .floating : .normal
        panel.alphaValue = preferences.selectionWindowOpacity
        panel.onEscape = { [weak panel] in
            panel?.close()
        }
        applyPanelAppearance(panel, preferences: preferences)
        panel.contentView = NSHostingView(rootView: SelectionActionPanel(
            action: action,
            selectedText: selectedText,
            assistant: actionAssistant,
            provider: actionProvider,
            searchSettings: searchSettings,
            onClose: { [weak self] in self?.actionPanel?.close() }
        ))
        showPanel(panel)
        actionPanel = panel
    }

    func updateAppearance(preferences: AppPreferences) {
        if let toolbarPanel {
            applyPanelAppearance(toolbarPanel, preferences: preferences)
        }
        if let actionPanel {
            applyPanelAppearance(actionPanel, preferences: preferences)
        }
    }
}

@MainActor
private func makePanel(title: String, size: NSSize) -> FloatingPanel {
    let panel = FloatingPanel(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    panel.title = title
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
    panel.isReleasedWhenClosed = false
    panel.becomesKeyOnlyIfNeeded = false
    // Non-opaque window so hosted `.ultraThinMaterial` frosts the desktop behind it.
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovableByWindowBackground = false
    return panel
}

private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragRegionView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
private func applyPanelAppearance(_ panel: NSPanel, preferences: AppPreferences) {
    switch preferences.appearanceMode {
    case .system:
        panel.appearance = nil
    case .light:
        panel.appearance = NSAppearance(named: .aqua)
    case .dark:
        panel.appearance = NSAppearance(named: .darkAqua)
    }
}

@MainActor
private func showPanel(
    _ panel: NSPanel,
    centered: Bool = true,
    nearAXRect: CGRect? = nil,
    anchorCoordinateSpace: PanelAnchorCoordinateSpace = .accessibility
) {
    if let nearAXRect {
        position(panel, nearAXRect: nearAXRect, coordinateSpace: anchorCoordinateSpace)
    } else if centered {
        panel.center()
    }
    panel.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor
private func position(
    _ panel: NSPanel,
    nearAXRect rect: CGRect,
    coordinateSpace: PanelAnchorCoordinateSpace = .accessibility
) {
    let converted = coordinateSpace == .appKit ? rect : bestAppKitRect(forSelectionRect: rect)
    let screen = NSScreen.screens.first { screen in
        screen.frame.intersects(converted)
            || screen.frame.contains(CGPoint(x: converted.midX, y: converted.midY))
    } ?? NSScreen.main
    guard let visibleFrame = screen?.visibleFrame else {
        panel.center()
        return
    }

    var origin = CGPoint(
        x: converted.midX - panel.frame.width / 2,
        y: converted.minY - panel.frame.height - 10
    )
    if origin.y < visibleFrame.minY {
        origin.y = converted.maxY + 10
    }
    origin.x = min(max(origin.x, visibleFrame.minX + 8), visibleFrame.maxX - panel.frame.width - 8)
    origin.y = min(max(origin.y, visibleFrame.minY + 8), visibleFrame.maxY - panel.frame.height - 8)
    panel.setFrameOrigin(origin)
}

private enum PanelAnchorCoordinateSpace {
    case accessibility
    case appKit
}

private func mouseAnchorRect() -> CGRect {
    let location = NSEvent.mouseLocation
    return CGRect(x: location.x, y: location.y, width: 1, height: 1)
}

private func bestAppKitRect(forSelectionRect rect: CGRect) -> CGRect {
    let screenUnion = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
    let flipped = CGRect(
        x: rect.minX,
        y: screenUnion.maxY - rect.maxY,
        width: rect.width,
        height: rect.height
    )
    let candidates = [rect, flipped].filter { candidate in
        NSScreen.screens.contains { screen in
            screen.visibleFrame.intersects(candidate)
                || screen.visibleFrame.contains(CGPoint(x: candidate.midX, y: candidate.midY))
        }
    }
    let usableCandidates = candidates.isEmpty ? [rect, flipped] : candidates
    let mouseLocation = NSEvent.mouseLocation
    return usableCandidates.min { lhs, rhs in
        distanceSquared(from: lhs, to: mouseLocation) < distanceSquared(from: rhs, to: mouseLocation)
    } ?? flipped
}

private func distanceSquared(from rect: CGRect, to point: CGPoint) -> CGFloat {
    let dx: CGFloat
    if point.x < rect.minX {
        dx = rect.minX - point.x
    } else if point.x > rect.maxX {
        dx = point.x - rect.maxX
    } else {
        dx = 0
    }

    let dy: CGFloat
    if point.y < rect.minY {
        dy = rect.minY - point.y
    } else if point.y > rect.maxY {
        dy = point.y - rect.maxY
    } else {
        dy = 0
    }

    return dx * dx + dy * dy
}

private enum QuickAssistantFeature: CaseIterable {
    case answer
    case translate
    case summarize
    case explain

    var icon: String {
        switch self {
        case .answer: "message"
        case .translate: "character.book.closed"
        case .summarize: "doc.text"
        case .explain: "lightbulb"
        }
    }

    var title: String {
        switch self {
        case .answer: "回答此问题"
        case .translate: "文本翻译"
        case .summarize: "内容总结"
        case .explain: "解释说明"
        }
    }

    var prefix: String {
        switch self {
        case .answer:
            "请直接回答下面的问题。若信息不足，请说明必要假设，并给出清晰、可执行的回答。"
        case .translate:
            "请自动识别下面文本的语言并翻译：如果原文是中文，译成自然英文；否则译成准确流畅的简体中文。保留专有名词、代码、链接和 Markdown 结构，只输出译文。"
        case .summarize:
            "请将下面内容总结为 3-5 条简洁要点，保留关键事实、数字、结论和行动项。"
        case .explain:
            "请解释下面内容的含义、背景和关键概念，指出它为什么重要，并保持语言简洁清楚。"
        }
    }
}

private struct QuickAssistantPanel: View {
    var assistant: AssistantProfile
    var provider: ModelProvider
    var searchSettings: SearchSettings
    var preferences: AppPreferences
    var initialPinned: Bool
    var onPinChanged: (Bool) -> Void
    var onClose: () -> Void

    @State private var prompt = ""
    @State private var result = ""
    @State private var reasoning = ""
    @State private var citations: [Citation] = []
    @State private var isRunning = false
    @State private var isDisplayStreaming = false
    @State private var isPinned = false
    @State private var selectedFeatureIndex = 0
    @State private var activeFeature: QuickAssistantFeature?
    @State private var submittedPrompt = ""
    @State private var responseId = UUID()
    @State private var runTask: Task<Void, Never>?
    @State private var displayStreamingTask: Task<Void, Never>?
    @State private var focusToken = UUID()
    @State private var isInputFocused = false
    @State private var thinkTagParser = ThinkTagParser()

    init(
        assistant: AssistantProfile,
        provider: ModelProvider,
        searchSettings: SearchSettings,
        preferences: AppPreferences,
        initialPinned: Bool,
        onPinChanged: @escaping (Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.assistant = assistant
        self.provider = provider
        self.searchSettings = searchSettings
        self.preferences = preferences
        self.initialPinned = initialPinned
        self.onPinChanged = onPinChanged
        self.onClose = onClose
        _isPinned = State(initialValue: initialPinned)
    }

    private var hasInputText: Bool {
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var selectedFeature: QuickAssistantFeature {
        let index = min(max(selectedFeatureIndex, 0), QuickAssistantFeature.allCases.count - 1)
        return QuickAssistantFeature.allCases[index]
    }

    private var quickActionColumnCount: Int { 2 }

    var body: some View {
        VStack(spacing: 0) {
            // Styled header with drag region.
            HStack(spacing: 10) {
                AssistantAvatar(name: assistant.name)
                    .frame(width: 24, height: 24)

                Text(assistant.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Spacer()

                // Pin button.
                Button {
                    let next = !isPinned
                    isPinned = next
                    onPinChanged(next)
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isPinned ? Color.justAccent : .secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.sm)
                .help(isPinned ? "取消置顶" : "置顶窗口")

                // Close button.
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.sm)
                .help("关闭 (ESC)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(WindowDragRegion())

            Divider()

            // Input area.
            HStack(spacing: 10) {
                QuickAssistantInputField(
                    text: $prompt,
                    placeholder: "询问 获取帮助...",
                    focusToken: focusToken,
                    onSubmit: runSelectedFeature,
                    onMoveLeft: { handleMoveCommand(.left) },
                    onMoveRight: { handleMoveCommand(.right) },
                    onMoveUp: { handleMoveCommand(.up) },
                    onMoveDown: { handleMoveCommand(.down) },
                    onEscape: handleEscape,
                    onFocusChange: { isInputFocused = $0 }
                )
                .frame(height: 36)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.justControlBackground.opacity(0.8))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(isInputFocused ? Color.justAccent.opacity(0.5) : Color.justBorderSoft, lineWidth: isInputFocused ? 2 : 1)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }

            Divider()

            // Content area.
            if activeFeature == nil {
                quickActionsHome
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                QuickAssistantResultView(
                    responseId: responseId,
                    prompt: submittedPrompt,
                    reasoning: reasoning,
                    result: result,
                    citations: citations,
                    isRunning: isRunning,
                    isDisplayStreaming: isDisplayStreaming,
                    onBack: returnToHome,
                    onCopy: copyResult
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: activeFeature == nil)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .raisedShadow()
        .onMoveCommand(perform: handleMoveCommand)
        .onExitCommand(perform: handleEscape)
        .onAppear {
            focusToken = UUID()
        }
        .onDisappear {
            runTask?.cancel()
        }
    }

    // MARK: - Quick Actions Home

    private var quickActionsHome: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(QuickAssistantFeature.allCases.enumerated()), id: \.offset) { index, feature in
                    QuickActionCard(
                        icon: feature.icon,
                        title: feature.title,
                        isEnabled: hasInputText && !isRunning,
                        isSelected: index == selectedFeatureIndex
                    ) {
                        selectedFeatureIndex = index
                        run(feature)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Actions

    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        guard activeFeature == nil else { return }
        let totalCount = QuickAssistantFeature.allCases.count
        guard totalCount > 0 else { return }

        var row = selectedFeatureIndex / quickActionColumnCount
        var column = selectedFeatureIndex % quickActionColumnCount

        switch direction {
        case .left:
            if column > 0 {
                column -= 1
            }
        case .right:
            let nextIndex = row * quickActionColumnCount + column + 1
            if column + 1 < quickActionColumnCount, nextIndex < totalCount {
                column += 1
            }
        case .up:
            if row > 0 {
                row -= 1
            }
        case .down:
            let nextIndex = (row + 1) * quickActionColumnCount + column
            if nextIndex < totalCount {
                row += 1
            }
        default:
            return
        }

        selectedFeatureIndex = min(row * quickActionColumnCount + column, totalCount - 1)
    }

    private func handleEscape() {
        if activeFeature != nil {
            returnToHome()
        } else {
            onClose()
        }
    }

    private func runSelectedFeature() {
        run(selectedFeature)
    }

    private func run(_ feature: QuickAssistantFeature) {
        guard !isRunning else { return }
        let sourceText = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sourceText.isEmpty else {
            focusToken = UUID()
            return
        }
        submittedPrompt = sourceText
        activeFeature = feature
        let text = "\(feature.prefix)\n\n\(sourceText)"
        responseId = UUID()
        result = ""
        reasoning = ""
        citations = []
        thinkTagParser = ThinkTagParser()
        stopDisplayStreaming()
        isRunning = true
        runTask?.cancel()
        runTask = Task {
            do {
                try await runPrompt(text)
            } catch {
                await MainActor.run {
                    result = error.localizedDescription
                    isRunning = false
                    stopDisplayStreaming()
                }
            }
        }
    }

    private func returnToHome() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        result = ""
        reasoning = ""
        citations = []
        thinkTagParser = ThinkTagParser()
        stopDisplayStreaming()
        activeFeature = nil
        focusToken = UUID()
    }

    private func copyResult() {
        guard !result.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    private func runPrompt(_ text: String) async throws {
        let conversationId = UUID()
        let message = ChatMessage(
            id: UUID(),
            conversationId: conversationId,
            role: .user,
            content: text,
            reasoningContent: "",
            citations: [],
            attachments: [],
            status: .success,
            usage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let request = ChatRequest(
            provider: provider,
            assistant: assistant,
            messages: [message],
            webSearchMode: .disabled,
            searchResults: []
        )
        let service = ChatSessionService(searchSettings: searchSettings)
        let eventQueue = ChatStreamEventQueue()
        let consumerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let events = eventQueue.drain()
                guard !events.isEmpty else { continue }
                apply(events)
            }
        }
        defer { consumerTask.cancel() }

        try await service.run(request) { event in
            eventQueue.append(event)
        }
        apply(eventQueue.drain())
        await MainActor.run {
            isRunning = false
            runTask = nil
        }
    }

    @MainActor
    private func apply(_ events: [ChatStreamEvent]) {
        for event in events {
            apply(event)
        }
    }

    @MainActor
    private func apply(_ event: ChatStreamEvent) {
        switch event {
        case .delta(let text):
            let parsed = thinkTagParser.append(text)
            result += parsed.content
            reasoning += parsed.reasoning
            if !parsed.content.isEmpty || !parsed.reasoning.isEmpty {
                markDisplayStreaming()
            }
        case .reasoningDelta(let text):
            reasoning += text
            if !text.isEmpty {
                markDisplayStreaming()
            }
        case .citation(let citation):
            citations.append(citation)
        case .usage:
            break
        case .completed:
            let parsed = thinkTagParser.finish()
            result += parsed.content
            reasoning += parsed.reasoning
            if !parsed.content.isEmpty || !parsed.reasoning.isEmpty {
                markDisplayStreaming()
            }
            isRunning = false
            scheduleDisplayStreamingEnd()
        }
    }

    private func markDisplayStreaming() {
        displayStreamingTask?.cancel()
        displayStreamingTask = nil
        isDisplayStreaming = true
    }

    private func scheduleDisplayStreamingEnd() {
        guard isDisplayStreaming else { return }
        displayStreamingTask?.cancel()
        let milliseconds = min(12_000, max(1_200, (result.count + reasoning.count) * 2))
        displayStreamingTask = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            await MainActor.run {
                stopDisplayStreaming()
            }
        }
    }

    private func stopDisplayStreaming() {
        displayStreamingTask?.cancel()
        displayStreamingTask = nil
        isDisplayStreaming = false
    }
}

private final class QuickAssistantTextField: NSTextField {
    var onSubmit: () -> Void = {}
    var onMoveLeft: () -> Void = {}
    var onMoveRight: () -> Void = {}
    var onMoveUp: () -> Void = {}
    var onMoveDown: () -> Void = {}
    var onEscape: () -> Void = {}

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onSubmit()
        case 123:
            onMoveLeft()
        case 124:
            onMoveRight()
        case 126:
            onMoveUp()
        case 125:
            onMoveDown()
        case 53:
            onEscape()
        default:
            super.keyDown(with: event)
        }
    }
}

private struct QuickAssistantInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var focusToken: UUID
    var onSubmit: () -> Void
    var onMoveLeft: () -> Void
    var onMoveRight: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onEscape: () -> Void
    var onFocusChange: (Bool) -> Void

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: QuickAssistantInputField
        var lastFocusToken: UUID?

        init(parent: QuickAssistantInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.moveLeft(_:)):
                parent.onMoveLeft()
                return true
            case #selector(NSResponder.moveRight(_:)):
                parent.onMoveRight()
                return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp()
                return true
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown()
                return true
            case #selector(NSResponder.insertNewline(_:)),
                 #selector(NSResponder.insertLineBreak(_:)),
                 #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape()
                return true
            default:
                return false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> QuickAssistantTextField {
        let field = QuickAssistantTextField()
        field.delegate = context.coordinator
        field.stringValue = text
        field.placeholderString = placeholder
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16, weight: .semibold)
        field.textColor = .labelColor
        field.lineBreakMode = .byTruncatingTail
        field.maximumNumberOfLines = 1
        field.cell?.usesSingleLineMode = true
        field.onSubmit = onSubmit
        field.onMoveLeft = onMoveLeft
        field.onMoveRight = onMoveRight
        field.onMoveUp = onMoveUp
        field.onMoveDown = onMoveDown
        field.onEscape = onEscape
        return field
    }

    func updateNSView(_ nsView: QuickAssistantTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = placeholder
        nsView.onSubmit = onSubmit
        nsView.onMoveLeft = onMoveLeft
        nsView.onMoveRight = onMoveRight
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onEscape = onEscape

        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

private struct QuickActionCard: View {
    var icon: String
    var title: String
    var isEnabled: Bool = true
    var isSelected: Bool = false
    var action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 10) {
                // Icon.
                ZStack {
                    Circle()
                        .fill(isEnabled ? Color.justAccent.opacity(0.12) : Color.secondary.opacity(0.08))
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isEnabled ? Color.justAccent : .secondary.opacity(0.6))
                        .symbolRenderingMode(.hierarchical)
                }

                // Title.
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .secondary)
                    .lineLimit(1)

            }
            .padding(.vertical, 14)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(isSelected ? Color.justControlBackground : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(isSelected ? Color.justAccent.opacity(0.35) : Color.justBorderSoft, lineWidth: isSelected ? 1.5 : 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .hoverSurface(radius: Radius.md, opacity: isEnabled ? 0.6 : 0)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

private struct QuickAssistantResultView: View {
    var responseId: UUID
    var prompt: String
    var reasoning: String
    var result: String
    var citations: [Citation]
    var isRunning: Bool
    var isDisplayStreaming: Bool
    var onBack: () -> Void
    var onCopy: () -> Void

    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        // User prompt bubble.
                        HStack {
                            Spacer()
                            Text(prompt)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                        .fill(Color.justAccent.opacity(0.12))
                                )
                        }

                        if !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            ThinkingBlock(
                                id: responseId,
                                text: reasoning,
                                isStreaming: isDisplayStreaming && result.isEmpty
                            )
                        }

                        // Result.
                        if isRunning && result.isEmpty && reasoning.isEmpty {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 14, height: 14)
                                Text("正在生成...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                            }
                        } else if result.isEmpty {
                            Text("结果会显示在这里。")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        } else {
                            SmoothStreamingMarkdownView(
                                content: result,
                                isStreaming: isRunning || isDisplayStreaming,
                                frameIntervalMilliseconds: 16
                            )
                        }

                        // Citations.
                        if !citations.isEmpty {
                            FlexWrap(spacing: 6) {
                                ForEach(citations) { citation in
                                    CitationChip(citation: citation)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        // Auto-scroll anchor.
                        Color.clear
                            .frame(height: 0)
                            .id("bottom")
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: result) {
                    if !result.isEmpty {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onChange(of: reasoning) {
                    if !reasoning.isEmpty {
                        withAnimation {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            }

            Divider()
                .padding(.top, 8)

            // Footer actions.
            HStack(spacing: 10) {
                Button {
                    onBack()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 14))
                        Text("返回")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(
                        Capsule()
                            .stroke(Color.justBorderSoft, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.pill, opacity: 0.45)

                if !result.isEmpty {
                    Button {
                        onCopy()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            copied = false
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14))
                            Text(copied ? "已复制" : "复制结果")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(copied ? Color.justSuccess : .secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(
                            Capsule()
                                .stroke(copied ? Color.justSuccess.opacity(0.4) : Color.justBorderSoft, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .hoverSurface(radius: Radius.pill, opacity: 0.45)
                }

                Spacer()
            }
            .padding(.top, 10)
        }
    }
}

private enum SelectionToolbarAction {
    case ask
    case translate
    case explain
    case summarize
    case search
    case copy

    var title: String {
        switch self {
        case .ask: "问问"
        case .translate: "翻译"
        case .explain: "解释"
        case .summarize: "总结"
        case .search: "搜索"
        case .copy: "复制"
        }
    }

    var icon: String {
        switch self {
        case .ask: "message"
        case .translate: "character.book.closed"
        case .explain: "questionmark.app"
        case .summarize: "list.bullet.rectangle"
        case .search: "magnifyingglass"
        case .copy: "doc.on.doc"
        }
    }

    var prompt: String {
        switch self {
        case .ask:
            "请基于下面选中文本回答用户的问题。若用户没有提出具体问题，请概括这段文本的核心含义。"
        case .translate:
            "请自动识别下面文本的语言并翻译：如果原文是中文，译成自然英文；否则译成准确流畅的简体中文。保留术语、代码、链接和 Markdown 结构，只输出译文。"
        case .explain:
            "请解释下面选中文本的含义、背景和关键概念，指出它为什么重要，并保持语言简洁清楚。"
        case .summarize:
            "请将下面选中文本总结为 3-5 条简洁要点，保留关键事实、数字、结论和行动项。"
        case .search, .copy:
            ""
        }
    }
}

private struct SelectionToolbarPanel: View {
    var selectedText: String
    var compact: Bool
    var onAction: (SelectionToolbarAction) -> Void
    var onClose: () -> Void

    /// Toolbar actions grouped for visual separation with dividers.
    private var textActions: [SelectionToolbarAction] { [.translate, .explain, .summarize] }
    private var utilityActions: [SelectionToolbarAction] { [.search, .copy] }

    var body: some View {
        HStack(spacing: 0) {
            // Brand indicator.
            Circle()
                .fill(LinearGradient.justAccent)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                )
                .shadow(color: Color.justAccent.opacity(0.25), radius: 6, x: 0, y: 2)
                .padding(.leading, 14)
                .padding(.trailing, compact ? 8 : 12)

            // Text actions group.
            HStack(spacing: compact ? 2 : 4) {
                ForEach(textActions, id: \.title) { action in
                    toolbarButton(action)
                }
            }

            // Divider.
            Rectangle()
                .fill(Color.justBorderSoft)
                .frame(width: 1, height: 22)
                .padding(.horizontal, compact ? 6 : 8)

            // Utility actions group.
            HStack(spacing: compact ? 2 : 4) {
                ForEach(utilityActions, id: \.title) { action in
                    toolbarButton(action)
                }
            }

            // Trailing padding to balance the leading brand indicator.
            Color.clear
                .frame(width: compact ? 6 : 10)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .raisedShadow()
        .onExitCommand { onClose() }
    }

    @ViewBuilder
    private func toolbarButton(_ action: SelectionToolbarAction) -> some View {
        Button {
            onAction(action)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: action.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if !compact {
                    Text(action.title)
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, compact ? 10 : 13)
            .frame(height: 44)
            .contentShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .hoverSurface(radius: Radius.sm, opacity: 0.55)
        .help(compact ? action.title : "")
    }
}

private struct SelectionActionPanel: View {
    var action: SelectionToolbarAction
    var selectedText: String
    var assistant: AssistantProfile
    var provider: ModelProvider
    var searchSettings: SearchSettings
    var onClose: () -> Void

    @State private var result = ""
    @State private var reasoning = ""
    @State private var citations: [Citation] = []
    @State private var isRunning = false
    @State private var isDisplayStreaming = false
    @State private var question = ""
    @State private var responseId = UUID()
    @State private var thinkTagParser = ThinkTagParser()
    @State private var displayStreamingTask: Task<Void, Never>?
    @FocusState private var focused: Bool

    private var hasContent: Bool {
        !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag-region header.
            HStack(spacing: 10) {
                // Action badge.
                HStack(spacing: 6) {
                    Image(systemName: action.icon)
                        .font(.system(size: 13, weight: .semibold))
                    Text(action.title)
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(LinearGradient.justAccent)
                )

                Spacer()

                // Model badge.
                Text(provider.defaultModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        Capsule()
                            .fill(Color.justControlBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.justBorderSoft, lineWidth: 1)
                    )

                // Close button.
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverSurface(radius: Radius.sm)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .background(WindowDragRegion())

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                // Selected text display.
                HStack(alignment: .top, spacing: 10) {
                    Rectangle()
                        .fill(Color.justAccent.opacity(0.5))
                        .frame(width: 3)
                        .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "text.viewfinder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.justAccent)
                            Text("已选中文本")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.justAccent)
                        }

                        Text(hasContent ? selectedText : "未检测到选中文本，请在任意应用中选中文字后重试。")
                            .font(.system(size: 14))
                            .foregroundStyle(hasContent ? .primary : .secondary)
                            .textSelection(.enabled)
                            .lineLimit(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Color.justControlBackground.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .stroke(Color.justBorderSoft, lineWidth: 1)
                )

                // Ask mode: question text field.
                if action == .ask {
                    HStack(spacing: 8) {
                        Image(systemName: "questionmark.bubble")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                        TextField("追问这段文本...", text: $question, axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .lineLimit(1...4)
                            .focused($focused)
                            .onSubmit {
                                run()
                            }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Color.justInputBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .stroke(focused ? Color.justAccent.opacity(0.4) : Color.justBorderSoft, lineWidth: focused ? 2 : 1)
                    )
                }

                // Action buttons.
                HStack(spacing: 10) {
                    // Run button.
                    Button {
                        run()
                    } label: {
                        HStack(spacing: 6) {
                            if isRunning {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: action == .ask ? "arrow.up.circle.fill" : "play.fill")
                                    .font(.system(size: 14))
                            }
                            Text(isRunning ? "生成中..." : action.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .fill(isRunning || !hasContent
                                      ? AnyShapeStyle(LinearGradient(colors: [Color.secondary.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                      : AnyShapeStyle(LinearGradient.justAccent))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRunning || !hasContent)
                    .focusable(false)

                    // Copy button.
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 13))
                            Text("复制结果")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .opacity(result.isEmpty ? 0.4 : 1.0)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(
                            Capsule()
                                .stroke(Color.justBorderSoft, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(result.isEmpty)
                    .focusable(false)

                    Spacer()
                }

                // Result area.
                SelectionResultView(
                    responseId: responseId,
                    reasoning: reasoning,
                    result: result,
                    citations: citations,
                    isRunning: isRunning,
                    isDisplayStreaming: isDisplayStreaming
                )
            }
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .raisedShadow()
        .onExitCommand { onClose() }
        .onAppear {
            if action != .ask {
                run()
            } else {
                focused = true
            }
        }
    }

    private func run() {
        guard !isRunning else { return }
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let prompt: String
        if action == .ask {
            let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.isEmpty {
                prompt = "\(action.prompt)\n\n选中文本：\n\(text)"
            } else {
                prompt = "\(action.prompt)\n\n用户问题：\n\(q)\n\n选中文本：\n\(text)"
            }
        } else {
            prompt = "\(action.prompt)\n\n选中文本：\n\(text)"
        }

        responseId = UUID()
        result = ""
        reasoning = ""
        citations = []
        thinkTagParser = ThinkTagParser()
        stopDisplayStreaming()
        isRunning = true
        Task {
            do {
                try await runPrompt(prompt)
            } catch {
                await MainActor.run {
                    result = error.localizedDescription
                    isRunning = false
                    stopDisplayStreaming()
                }
            }
        }
    }

    private func runPrompt(_ text: String) async throws {
        let conversationId = UUID()
        let message = ChatMessage(
            id: UUID(),
            conversationId: conversationId,
            role: .user,
            content: text,
            reasoningContent: "",
            citations: [],
            attachments: [],
            status: .success,
            usage: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
        let request = ChatRequest(
            provider: provider,
            assistant: assistant,
            messages: [message],
            webSearchMode: .disabled,
            searchResults: []
        )
        let service = ChatSessionService(searchSettings: searchSettings)
        let eventQueue = ChatStreamEventQueue()
        let consumerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                let events = eventQueue.drain()
                guard !events.isEmpty else { continue }
                apply(events)
            }
        }
        defer { consumerTask.cancel() }

        try await service.run(request) { event in
            eventQueue.append(event)
        }
        apply(eventQueue.drain())
        await MainActor.run {
            isRunning = false
        }
    }

    @MainActor
    private func apply(_ events: [ChatStreamEvent]) {
        for event in events {
            apply(event)
        }
    }

    @MainActor
    private func apply(_ event: ChatStreamEvent) {
        switch event {
        case .delta(let text):
            let parsed = thinkTagParser.append(text)
            result += parsed.content
            reasoning += parsed.reasoning
            if !parsed.content.isEmpty || !parsed.reasoning.isEmpty {
                markDisplayStreaming()
            }
        case .reasoningDelta(let text):
            reasoning += text
            if !text.isEmpty {
                markDisplayStreaming()
            }
        case .citation(let citation):
            citations.append(citation)
        case .usage:
            break
        case .completed:
            let parsed = thinkTagParser.finish()
            result += parsed.content
            reasoning += parsed.reasoning
            if !parsed.content.isEmpty || !parsed.reasoning.isEmpty {
                markDisplayStreaming()
            }
            isRunning = false
            scheduleDisplayStreamingEnd()
        }
    }

    private func markDisplayStreaming() {
        displayStreamingTask?.cancel()
        displayStreamingTask = nil
        isDisplayStreaming = true
    }

    private func scheduleDisplayStreamingEnd() {
        guard isDisplayStreaming else { return }
        displayStreamingTask?.cancel()
        let milliseconds = min(12_000, max(1_200, (result.count + reasoning.count) * 2))
        displayStreamingTask = Task {
            try? await Task.sleep(for: .milliseconds(milliseconds))
            await MainActor.run {
                stopDisplayStreaming()
            }
        }
    }

    private func stopDisplayStreaming() {
        displayStreamingTask?.cancel()
        displayStreamingTask = nil
        isDisplayStreaming = false
    }
}

/// Auto-scrolling result view for the selection action panel.
private struct SelectionResultView: View {
    var responseId: UUID
    var reasoning: String
    var result: String
    var citations: [Citation]
    var isRunning: Bool
    var isDisplayStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ThinkingBlock(
                            id: responseId,
                            text: reasoning,
                            isStreaming: isDisplayStreaming && result.isEmpty
                        )
                    }

                    if isRunning && result.isEmpty && reasoning.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                            Text("正在生成...")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                        }
                    } else if result.isEmpty {
                        Text("结果会显示在这里。")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    } else {
                        SmoothStreamingMarkdownView(
                            content: result,
                            isStreaming: isRunning || isDisplayStreaming,
                            frameIntervalMilliseconds: 16
                        )
                    }

                    if !citations.isEmpty {
                        FlexWrap(spacing: 6) {
                            ForEach(citations) { citation in
                                CitationChip(citation: citation)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Invisible anchor for auto-scroll.
                    Color.clear
                        .frame(height: 0)
                        .id("bottom")
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Color.justControlBackground.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .stroke(Color.justBorderSoft, lineWidth: 1)
            )
            .cardShadow()
            .onChange(of: result) {
                if !result.isEmpty {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .onChange(of: reasoning) {
                if !reasoning.isEmpty {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }
}

private struct ResultBlock: View {
    var result: String
    var citations: [Citation]
    var isRunning: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if isRunning && result.isEmpty {
                    Text("正在生成...")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else if result.isEmpty {
                    Text("结果会显示在这里。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                } else {
                    SmoothStreamingMarkdownView(
                        content: result,
                        isStreaming: isRunning,
                        frameIntervalMilliseconds: 16
                    )
                }

                if !citations.isEmpty {
                    FlexWrap(spacing: 6) {
                        ForEach(citations) { citation in
                            CitationChip(citation: citation)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.justControlBackground.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .cardShadow()
    }
}
