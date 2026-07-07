import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

enum HTMLArtifactSupport {
    private static let titlePattern = #"<title\b[^>]*>([\s\S]*?)</title>"#
    private static let invalidFilenameCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
    private static let previewBaseURL = "about:blank"

    static func isHTMLArtifact(language: String?, code: String) -> Bool {
        let normalizedLanguage = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if ["html", "htm", "xhtml"].contains(normalizedLanguage) {
            return true
        }
        if !normalizedLanguage.isEmpty {
            return false
        }

        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else { return false }

        return trimmedCode.range(
            of: #"^(?:<!DOCTYPE\s+html\b|<html\b|<head\b|<body\b)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func extractTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: titlePattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }

        let searchRange = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, options: [], range: searchRange),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }

        let rawTitle = String(html[titleRange])
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return rawTitle.isEmpty ? nil : rawTitle
    }

    static func suggestedFilename(for html: String) -> String {
        let stem = sanitizeFilenameStem(extractTitle(from: html) ?? "html-artifact")
        return stem.hasSuffix(".html") ? stem : stem + ".html"
    }

    static func injectPreviewBase(into html: String) -> String {
        let trimmed = html.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return html }
        guard trimmed.range(of: #"<base(?:\s|>|/)"#, options: [.regularExpression, .caseInsensitive]) == nil else {
            return html
        }

        let baseTag = #"<base href="\#(previewBaseURL)">"#

        if let headRange = html.range(of: #"<head(?:\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: headRange, with: html[headRange] + baseTag)
        }
        if let htmlRange = html.range(of: #"<html(?:\s[^>]*)?>"#, options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: htmlRange, with: html[htmlRange] + "<head>\(baseTag)</head>")
        }
        if let doctypeRange = html.range(of: #"<!doctype\s+html[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
            return html.replacingCharacters(in: doctypeRange, with: html[doctypeRange] + "<head>\(baseTag)</head>")
        }
        return "<head>\(baseTag)</head>\(html)"
    }

    @MainActor
    static func saveHTML(_ html: String, suggestedFilename: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = suggestedFilename

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    static func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存 HTML 失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }

    private static func sanitizeFilenameStem(_ title: String) -> String {
        let replacedInvalidCharacters = String(title.unicodeScalars.map { scalar in
            invalidFilenameCharacters.contains(scalar) ? " " : String(scalar)
        }.joined())

        let collapsed = replacedInvalidCharacters
            .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))

        return collapsed.isEmpty ? "html-artifact" : collapsed
    }
}

private enum HTMLArtifactPreviewMode: String, CaseIterable {
    case preview
    case source

    var title: String {
        switch self {
        case .preview:
            "预览"
        case .source:
            "源码"
        }
    }
}

struct HTMLArtifactCard: View {
    let html: String

    @State private var copied = false
    @State private var previewPresented = false
    @State private var previewMode: HTMLArtifactPreviewMode = .preview
    @State private var saved = false

    private var title: String {
        HTMLArtifactSupport.extractTitle(from: html) ?? "HTML Artifact"
    }

    private var metadataLabel: String {
        let lineCount = html.isEmpty ? 0 : html.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(max(lineCount, 1)) 行 · \(html.count) 字符"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(LinearGradient.justAccent)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "globe")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("HTML")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.justAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                        Text(metadataLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(16)

            Divider()

            HStack(spacing: 8) {
                actionButton("预览", systemImage: "play.rectangle") {
                    openPreview(mode: .preview)
                }

                actionButton("源码", systemImage: "chevron.left.forwardslash.chevron.right") {
                    openPreview(mode: .source)
                }

                actionButton(saved ? "已保存" : "下载", systemImage: saved ? "checkmark" : "arrow.down.circle") {
                    saveHTML()
                }

                actionButton(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(html, forType: .string)
                    flashCopied()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.justCodeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .cardShadow()
        .sheet(isPresented: $previewPresented) {
            HTMLArtifactPreviewSheet(html: html, initialMode: previewMode)
        }
    }

    private func actionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverSurface(radius: Radius.sm, opacity: 0.55)
    }

    private func openPreview(mode: HTMLArtifactPreviewMode) {
        previewMode = mode
        previewPresented = true
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }

    private func flashSaved() {
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            saved = false
        }
    }

    @MainActor
    private func saveHTML() {
        do {
            let savedURL = try HTMLArtifactSupport.saveHTML(
                html,
                suggestedFilename: HTMLArtifactSupport.suggestedFilename(for: html)
            )
            if savedURL != nil {
                flashSaved()
            }
        } catch {
            HTMLArtifactSupport.presentSaveError(error)
        }
    }
}

private struct HTMLArtifactPreviewSheet: View {
    let html: String
    let initialMode: HTMLArtifactPreviewMode

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var mode: HTMLArtifactPreviewMode
    @State private var saved = false

    init(html: String, initialMode: HTMLArtifactPreviewMode) {
        self.html = html
        self.initialMode = initialMode
        _mode = State(initialValue: initialMode)
    }

    private var title: String {
        HTMLArtifactSupport.extractTitle(from: html) ?? "HTML Artifact"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                    Text(HTMLArtifactSupport.suggestedFilename(for: html))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("视图", selection: $mode) {
                    ForEach(HTMLArtifactPreviewMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                previewToolbarButton(saved ? "已保存" : "下载", systemImage: saved ? "checkmark" : "arrow.down.circle") {
                    saveHTML()
                }

                previewToolbarButton(copied ? "已复制" : "复制源码", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(html, forType: .string)
                    flashCopied()
                }

                previewToolbarButton("关闭", systemImage: "xmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch mode {
                case .preview:
                    HTMLPreviewWebView(html: html)
                case .source:
                    ScrollView([.horizontal, .vertical]) {
                        Text(SyntaxHighlighter.highlight(code: html, language: "html"))
                            .textSelection(.enabled)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.justCodeBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 960, minHeight: 680)
        .background(Color.justWindowBackground)
    }

    private func previewToolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverSurface(radius: Radius.sm, opacity: 0.55)
    }

    private func flashCopied() {
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            copied = false
        }
    }

    private func flashSaved() {
        saved = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            saved = false
        }
    }

    @MainActor
    private func saveHTML() {
        do {
            let savedURL = try HTMLArtifactSupport.saveHTML(
                html,
                suggestedFilename: HTMLArtifactSupport.suggestedFilename(for: html)
            )
            if savedURL != nil {
                flashSaved()
            }
        } catch {
            HTMLArtifactSupport.presentSaveError(error)
        }
    }
}

struct HTMLPreviewWebView: NSViewRepresentable {
    let html: String
    var measuredHeight: Binding<CGFloat>? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: "height")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.measuredHeight = measuredHeight
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        webView.loadHTMLString(
            HTMLArtifactSupport.injectPreviewBase(into: html),
            baseURL: URL(string: "about:blank")
        )
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var lastHTML = ""
        var measuredHeight: Binding<CGFloat>?

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "height" else { return }

            let height: CGFloat?
            if let value = message.body as? Double {
                height = CGFloat(value)
            } else if let value = message.body as? Int {
                height = CGFloat(value)
            } else {
                height = nil
            }

            guard let height else { return }

            DispatchQueue.main.async { [weak self] in
                let clampedHeight = min(max(height, 180), 1200)
                guard let measuredHeight = self?.measuredHeight,
                      abs(measuredHeight.wrappedValue - clampedHeight) > 1
                else { return }
                measuredHeight.wrappedValue = clampedHeight
            }
        }
    }
}
