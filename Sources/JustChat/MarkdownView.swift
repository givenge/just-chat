import AppKit
import Foundation
import Markdown
import SwiftUI
import UniformTypeIdentifiers

/// Renders a markdown string as native SwiftUI blocks using `apple/swift-markdown`
/// for parsing. Supports headings, paragraphs (inline markdown), fenced/indented
/// code blocks with syntax highlighting + copy, blockquotes, ordered/unordered
/// lists (nested), tables, and thematic breaks. Re-parses on each streaming delta.
struct MarkdownText: View {
    let content: String
    var fontSize: CGFloat = 15

    private var document: Document { Document(parsing: Self.normalizedMarkdown(content)) }

    nonisolated static func normalizedMarkdown(_ markdown: String) -> String {
        var inFence = false
        return markdown.components(separatedBy: "\n").map { rawLine in
            let line = String(rawLine)
            let leadingSpaces = line.prefix { $0 == " " }.count
            let trimmed = line.dropFirst(leadingSpaces)

            if leadingSpaces <= 3,
               trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                return line
            }

            guard !inFence, leadingSpaces <= 3 else {
                return line
            }

            let hashes = trimmed.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes) else {
                return line
            }

            let afterHashes = trimmed.dropFirst(hashes)
            guard let next = afterHashes.first,
                  next != "#",
                  !next.isWhitespace
            else {
                return line
            }

            let prefix = String(line.prefix(leadingSpaces + hashes))
            return prefix + " " + afterHashes
        }.joined(separator: "\n")
    }

    var body: some View {
        blocksView(document.children)
    }

    @ViewBuilder
    private func blocksView(_ children: MarkupChildren) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                // `AnyView` breaks the blockView ↔ blocksView opaque-type cycle
                // (mutually recursive `some View` returns can't be inferred).
                AnyView(blockView(for: child))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(for block: any Markup) -> some View {
        switch block {
        case let h as Heading:
            headingView(h)
        case let p as Paragraph:
            SwiftUI.Text(attributedMarkdownString(p.format()))
                .font(.system(size: fontSize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case let c as CodeBlock:
            if MermaidSupport.isMermaid(language: c.language) {
                MermaidBlockView(code: c.code)
            } else {
                CodeBlockView(language: c.language, code: c.code)
            }
        case let q as BlockQuote:
            blockQuoteView(q)
        case let ul as UnorderedList:
            listChildrenView(ul, ordered: false, start: 1)
        case let ol as OrderedList:
            listChildrenView(ol, ordered: true, start: 1)
        case let t as Markdown.Table:
            tableView(t)
        case is ThematicBreak:
            Divider()
        default:
            SwiftUI.Text(block.format())
                .font(.system(size: fontSize))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func blockQuoteView(_ quote: BlockQuote) -> some View {
        if let compactText = compactBlockQuoteText(quote) {
            blockQuoteContainer {
                SwiftUI.Text(compactText)
                    .font(.system(size: fontSize))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            blockQuoteContainer {
                blocksView(quote.children)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func blockQuoteContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(Color.justAccent.opacity(0.5))
                .frame(width: 3)
            content()
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func headingView(_ heading: Heading) -> some View {
        let text = SwiftUI.Text(inlineAttributedString(heading.children))
        switch heading.level {
        case 1: text.font(.system(size: fontSize + 7, weight: .bold)).textSelection(.enabled)
        case 2: text.font(.system(size: fontSize + 4, weight: .bold)).textSelection(.enabled)
        case 3: text.font(.system(size: fontSize + 2, weight: .bold)).textSelection(.enabled)
        case 4: text.font(.system(size: fontSize + 1, weight: .semibold)).textSelection(.enabled)
        case 5: text.font(.system(size: fontSize, weight: .semibold)).textSelection(.enabled)
        default: text.font(.system(size: max(12, fontSize - 1), weight: .semibold)).textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func listChildrenView(_ list: any Markup, ordered: Bool, start: Int) -> some View {
        let items = list.children.compactMap { $0 as? ListItem }
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(ordered ? "\(start + idx)." : "•")
                        .font(.system(size: max(12, fontSize - 1), weight: .semibold))
                        .foregroundStyle(.secondary)
                    blocksView(item.children)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func tableView(_ table: Markdown.Table) -> some View {
        let head = table.children.compactMap { $0 as? Markdown.Table.Head }.first
        let body = table.children.compactMap { $0 as? Markdown.Table.Body }.first
        let headerCells = head?.children.compactMap { $0 as? Markdown.Table.Cell } ?? []
        let rows = body?.children.compactMap { $0 as? Markdown.Table.Row } ?? []
        let columnCount = max(headerCells.count, rows.map { Array($0.children).count }.max() ?? 0)

        VStack(alignment: .leading, spacing: 0) {
            if !headerCells.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { i in
                        let cell = i < headerCells.count ? headerCells[i] : nil
                        cellText(cell)
                            .font(.system(size: max(12, fontSize - 2), weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                Divider()
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                let cells = row.children.compactMap { $0 as? Markdown.Table.Cell }
                HStack(alignment: .top, spacing: 0) {
                    ForEach(0..<columnCount, id: \.self) { i in
                        let cell = i < cells.count ? cells[i] : nil
                        cellText(cell)
                            .font(.system(size: max(12, fontSize - 2)))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                    }
                }
                Divider()
            }
        }
        .background(Color.justControlBackground.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
    }

    private func cellText(_ cell: Markdown.Table.Cell?) -> SwiftUI.Text {
        guard let cell else { return SwiftUI.Text("") }
        return SwiftUI.Text(inlineAttributedString(cell.children))
    }

    private func compactBlockQuoteText(_ quote: BlockQuote) -> AttributedString? {
        let children = Array(quote.children)
        let paragraphs = children.compactMap { $0 as? Paragraph }
        guard !paragraphs.isEmpty, paragraphs.count == children.count else { return nil }
        let mergedMarkdown = paragraphs.map { $0.format() }.joined(separator: "\n\n")
        return attributedMarkdownString(mergedMarkdown)
    }

    private func attributedMarkdownString(_ markdown: String) -> AttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return AttributedString() }
        if let attr = try? AttributedString(markdown: trimmed) {
            return attr
        }
        return AttributedString(trimmed)
    }

    /// Parses inline markup back to markdown and lets Foundation render it to an
    /// `AttributedString` (bold/italic/`code`/links/strikethrough), dark-mode aware.
    private func inlineAttributedString(_ children: MarkupChildren) -> AttributedString {
        let markdown = children.map { $0.format() }.joined()
        return attributedMarkdownString(markdown)
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        if HTMLArtifactSupport.isHTMLArtifact(language: language, code: code) {
            HTMLArtifactCard(html: code)
        } else if SVGSupport.isSVG(language: language, code: code) {
            SVGBlockView(code: code)
        } else {
            sourceCodeBlock
        }
    }

    private var sourceCodeBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(languageLabel)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .suppressFocusRing()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.justCodeBackground.opacity(0.6))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code: code, language: language))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.justCodeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .cardShadow()
    }

    private var languageLabel: String {
        let trimmed = language?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "code" : trimmed
    }
}

// MARK: - Mermaid diagrams

enum MermaidSupport {
    static func isMermaid(language: String?) -> Bool {
        let normalized = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "mermaid" || normalized == "mmd"
    }

    static func html(for code: String) -> String {
        let jsonCode = (try? String(
            data: JSONEncoder().encode(code),
            encoding: .utf8
        ))?.replacingOccurrences(of: "</", with: "<\\/") ?? "\"\""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; background: transparent; color: #1d1d1f; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { padding: 16px; }
        #diagram { min-width: max-content; }
        .error { color: #dc2626; white-space: pre-wrap; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        @media (prefers-color-scheme: dark) {
          html, body { color: #f5f5f7; }
          .error { color: #ff453a; }
        }
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        </head>
        <body>
        <div id="diagram"></div>
        <script>
        const source = \(jsonCode);
        const sendHeight = () => {
          const height = Math.ceil(Math.max(
            document.body.scrollHeight,
            document.documentElement.scrollHeight,
            document.getElementById("diagram").scrollHeight
          ));
          window.webkit?.messageHandlers?.height?.postMessage(height);
        };
        const showError = error => {
          const node = document.getElementById("diagram");
          node.className = "error";
          node.textContent = error.message || String(error);
          sendHeight();
        };
        if (!window.mermaid) {
          showError("Mermaid 加载失败，请检查网络连接。");
        } else {
          const theme = window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "default";
          mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme });
          mermaid.render("mermaid-diagram", source)
            .then(({ svg }) => {
              document.getElementById("diagram").innerHTML = svg;
              requestAnimationFrame(sendHeight);
            })
            .catch(showError);
        }
        window.addEventListener("load", () => setTimeout(sendHeight, 0));
        </script>
        </body>
        </html>
        """
    }
}

struct MermaidBlockView: View {
    let code: String

    @State private var copied = false
    @State private var diagramHeight: CGFloat = 360

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("MERMAID")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .suppressFocusRing()
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.justCodeBackground.opacity(0.6))

            HTMLPreviewWebView(html: MermaidSupport.html(for: code), measuredHeight: $diagramHeight)
                .allowsHitTesting(false)
                .frame(height: diagramHeight)
        }
        .background(Color.justCodeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .cardShadow()
    }
}

// MARK: - SVG previews

enum SVGSupport {
    private static let svgPrefixPattern = #"^(?:<\?xml[\s\S]*?\?>\s*)?(?:<!--[\s\S]*?-->\s*)*<svg(?:\s|>|/)"#

    static func isSVG(language: String?, code: String) -> Bool {
        let normalized = language?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard normalized.isEmpty || normalized == "svg" || normalized == "xml" || normalized == "image/svg+xml" else {
            return false
        }

        return code.trimmingCharacters(in: .whitespacesAndNewlines).range(
            of: svgPrefixPattern,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    static func html(for svg: String) -> String {
        let jsonSVG = (try? String(
            data: JSONEncoder().encode(svg),
            encoding: .utf8
        ))?.replacingOccurrences(of: "</", with: "<\\/") ?? "\"\""

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body { margin: 0; min-height: 100%; background: transparent; color: #1d1d1f; font: 14px -apple-system, BlinkMacSystemFont, sans-serif; }
        body { box-sizing: border-box; padding: 18px; display: flex; align-items: center; justify-content: center; }
        #svg-root { width: 100%; min-height: 220px; display: flex; align-items: center; justify-content: center; overflow: hidden; }
        #svg-root > svg { display: block; max-width: 100%; max-height: 520px; width: auto; height: auto; }
        .error { color: #dc2626; white-space: pre-wrap; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
        @media (prefers-color-scheme: dark) {
          html, body { color: #f5f5f7; }
          .error { color: #ff453a; }
        }
        </style>
        </head>
        <body>
        <div id="svg-root"></div>
        <script>
        const source = \(jsonSVG);
        const root = document.getElementById("svg-root");
        const sendHeight = () => {
          const height = Math.ceil(Math.max(
            document.body.scrollHeight,
            document.documentElement.scrollHeight,
            root.scrollHeight
          ));
          window.webkit?.messageHandlers?.height?.postMessage(height);
        };
        try {
          root.innerHTML = source;
          requestAnimationFrame(sendHeight);
        } catch (error) {
          root.className = "error";
          root.textContent = error.message || String(error);
          sendHeight();
        }
        window.addEventListener("load", () => setTimeout(sendHeight, 0));
        </script>
        </body>
        </html>
        """
    }

    static func suggestedFilename(for svg: String) -> String {
        "image.svg"
    }

    @MainActor
    static func saveSVG(_ svg: String, suggestedFilename: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        }
        panel.nameFieldStringValue = suggestedFilename

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try svg.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @MainActor
    static func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "保存 SVG 失败"
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

private enum SVGPreviewMode: String, CaseIterable {
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

struct SVGBlockView: View {
    let code: String

    @State private var copied = false
    @State private var mode: SVGPreviewMode = .preview
    @State private var previewHeight: CGFloat = 260
    @State private var saved = false

    private var metadataLabel: String {
        let lineCount = code.isEmpty ? 0 : code.split(separator: "\n", omittingEmptySubsequences: false).count
        return "\(max(lineCount, 1)) 行 · \(code.count) 字符"
    }

    private var previewFrameHeight: CGFloat {
        min(max(previewHeight, 240), 620)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SVG")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(metadataLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Picker("视图", selection: $mode) {
                    ForEach(SVGPreviewMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)

                toolbarButton(saved ? "已保存" : "下载", systemImage: saved ? "checkmark" : "arrow.down.circle") {
                    saveSVG()
                }

                toolbarButton(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    flashCopied()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.justCodeBackground.opacity(0.6))

            Divider()

            Group {
                switch mode {
                case .preview:
                    HTMLPreviewWebView(html: SVGSupport.html(for: code), measuredHeight: $previewHeight)
                        .allowsHitTesting(false)
                        .frame(height: previewFrameHeight)
                case .source:
                    ScrollView([.horizontal, .vertical]) {
                        Text(SyntaxHighlighter.highlight(code: code, language: "xml"))
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 360)
                    .background(Color.justCodeBackground)
                }
            }
        }
        .background(Color.justCodeBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.justBorderSoft, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .cardShadow()
    }

    private func toolbarButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .frame(height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .suppressFocusRing()
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
    private func saveSVG() {
        do {
            let savedURL = try SVGSupport.saveSVG(
                code,
                suggestedFilename: SVGSupport.suggestedFilename(for: code)
            )
            if savedURL != nil {
                flashSaved()
            }
        } catch {
            SVGSupport.presentSaveError(error)
        }
    }
}

// MARK: - Syntax highlighting

/// Lightweight regex-based tokenizer that colors comments, strings, numbers, and
/// keywords/types for a handful of languages. Not a real parser — good enough for
/// readable code blocks in chat output.
enum SyntaxHighlighter {
    static func highlight(code: String, language: String?) -> AttributedString {
        let keywords = Self.keywords(for: Self.normalize(language))
        let nsCode = code as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return styled(code, color: .justCodeForeground)
        }
        let matches = regex.matches(in: code, range: NSRange(location: 0, length: nsCode.length))
        var result = AttributedString()
        var lastEnd = 0
        for m in matches {
            let r = m.range
            if r.location > lastEnd {
                result += styled(nsCode.substring(with: NSRange(location: lastEnd, length: r.location - lastEnd)),
                                 color: .justCodeForeground)
            }
            let comment = m.range(at: 1)
            let string = m.range(at: 2)
            let number = m.range(at: 3)
            let ident = m.range(at: 4)
            if comment.location != NSNotFound && comment.length > 0 {
                result += styled(nsCode.substring(with: comment), color: .justCodeComment, italic: true)
            } else if string.location != NSNotFound && string.length > 0 {
                result += styled(nsCode.substring(with: string), color: .justCodeString)
            } else if number.location != NSNotFound && number.length > 0 {
                result += styled(nsCode.substring(with: number), color: .justCodeNumber)
            } else if ident.location != NSNotFound && ident.length > 0 {
                let word = nsCode.substring(with: ident)
                if keywords.contains(word) {
                    result += styled(word, color: .justCodeKeyword, bold: true)
                } else if let first = word.first, first.isUppercase {
                    result += styled(word, color: .justCodeType)
                } else {
                    result += styled(word, color: .justCodeForeground)
                }
            }
            lastEnd = r.location + r.length
        }
        if lastEnd < nsCode.length {
            result += styled(nsCode.substring(from: lastEnd), color: .justCodeForeground)
        }
        return result
    }

    private static func styled(_ text: String, color: Color, bold: Bool = false, italic: Bool = false) -> AttributedString {
        var s = AttributedString(text)
        var container = AttributeContainer()
        container.foregroundColor = color
        var font = Font.system(size: 13, weight: bold ? .semibold : .regular, design: .monospaced)
        if italic { font = font.italic() }
        container.font = font
        s.mergeAttributes(container)
        return s
    }

    // swiftlint:disable:next line_length
    private static let pattern = #"(//[^\n]*|/\*[\s\S]*?\*/|#[^\n]*)|("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`[^`]*`)|(\b\d[\d_]*(?:\.\d+)?\b)|([A-Za-z_][A-Za-z0-9_]*)"#

    private static func normalize(_ language: String?) -> String {
        guard let l = language?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), !l.isEmpty else {
            return ""
        }
        switch l {
        case "ts", "typescript": return "typescript"
        case "js", "javascript": return "javascript"
        case "py", "python": return "python"
        case "rs", "rust": return "rust"
        case "go", "golang": return "go"
        case "sh", "bash", "shell", "zsh": return "shell"
        case "kt", "kotlin": return "kotlin"
        default: return l
        }
    }

    private static func keywords(for language: String) -> Set<String> {
        switch language {
        case "swift":
            return Self.swiftKeywords
        case "python":
            return Self.pythonKeywords
        case "javascript", "typescript":
            return Self.jsKeywords
        case "rust":
            return Self.rustKeywords
        case "go":
            return Self.goKeywords
        case "shell":
            return Self.shellKeywords
        case "kotlin":
            return Self.kotlinKeywords
        default:
            return Self.defaultKeywords
        }
    }

    private static let swiftKeywords: Set<String> = [
        "func", "let", "var", "if", "else", "guard", "return", "for", "while", "switch",
        "case", "default", "break", "continue", "struct", "class", "enum", "protocol",
        "extension", "import", "init", "deinit", "self", "Self", "super", "true", "false",
        "nil", "in", "as", "is", "where", "throws", "throw", "try", "catch", "do", "defer",
        "public", "private", "internal", "fileprivate", "static", "final", "lazy", "weak",
        "unowned", "some", "any", "async", "await", "actor", "repeat", "fallthrough", "inout"
    ]
    private static let pythonKeywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return", "import", "from",
        "as", "try", "except", "finally", "raise", "with", "yield", "lambda", "pass",
        "break", "continue", "global", "nonlocal", "in", "is", "not", "and", "or", "None",
        "True", "False", "self", "async", "await", "del", "assert", "print"
    ]
    private static let jsKeywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "return", "for", "while", "switch",
        "case", "break", "continue", "class", "extends", "import", "export", "from", "as",
        "default", "new", "this", "super", "true", "false", "null", "undefined", "typeof",
        "instanceof", "in", "of", "try", "catch", "finally", "throw", "async", "await",
        "yield", "delete", "void", "do", "static", "get", "set"
    ]
    private static let rustKeywords: Set<String> = [
        "fn", "let", "mut", "if", "else", "match", "return", "for", "while", "loop", "struct",
        "enum", "impl", "trait", "use", "mod", "pub", "priv", "as", "in", "ref", "move",
        "self", "Self", "super", "crate", "true", "false", "async", "await", "dyn", "unsafe",
        "const", "static", "type", "where", "break", "continue"
    ]
    private static let goKeywords: Set<String> = [
        "func", "var", "const", "type", "struct", "interface", "if", "else", "for", "range",
        "switch", "case", "default", "return", "break", "continue", "package", "import",
        "go", "defer", "select", "chan", "map", "make", "new", "nil", "true", "false"
    ]
    private static let shellKeywords: Set<String> = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "case", "esac",
        "function", "return", "echo", "export", "local", "unset", "in", "select", "until"
    ]
    private static let kotlinKeywords: Set<String> = [
        "fun", "val", "var", "if", "else", "when", "for", "while", "return", "class",
        "object", "interface", "import", "package", "in", "is", "as", "by", "init",
        "this", "super", "true", "false", "null", "companion", "override", "open", "data",
        "sealed", "abstract", "private", "public", "internal", "protected", "suspend", "try", "catch", "finally", "throw"
    ]
    private static let defaultKeywords: Set<String> = [
        "if", "else", "for", "while", "return", "function", "class", "import", "export",
        "true", "false", "null", "none", "nil", "self", "this", "new", "const", "let", "var",
        "def", "case", "switch", "break", "continue", "default", "try", "catch", "throw"
    ]
}
