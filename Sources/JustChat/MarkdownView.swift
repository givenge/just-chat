import AppKit
import Markdown
import SwiftUI

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
            CodeBlockView(language: c.language, code: c.code)
        case let q as BlockQuote:
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(Color.justAccent.opacity(0.5))
                    .frame(width: 3)
                blocksView(q.children)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
