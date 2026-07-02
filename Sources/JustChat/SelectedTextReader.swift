import AppKit
import ApplicationServices
import Foundation

struct SelectedTextSnapshot {
    var text: String
    var bounds: CGRect?
}

enum SelectedTextReader {
    /// Reads the currently selected text from the frontmost application using the
    /// macOS Accessibility API. Returns `nil` when Accessibility permissions are
    /// not granted or when no text is selected.
    static func readSelectedText() -> String? {
        readSelection()?.text
    }

    static func readSelection() -> SelectedTextSnapshot? {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return nil }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = frontmost.processIdentifier
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusResult == .success, let focused else { return nil }
        var selectedText: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(
            focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selectedText
        )
        guard textResult == .success, let selectedText else { return nil }
        guard let text = selectedText as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return SelectedTextSnapshot(text: text, bounds: selectedBounds(focused as! AXUIElement))
    }

    private static func selectedBounds(_ element: AXUIElement) -> CGRect? {
        if let bounds = selectedTextRangeBounds(element), isUsableSelectionBounds(bounds) {
            return bounds
        }
        if let bounds = selectedTextRangesBounds(element), isUsableSelectionBounds(bounds) {
            return bounds
        }
        return nil
    }

    private static func selectedTextRangeBounds(_ element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeResult == .success,
              let rangeValue
        else {
            return nil
        }
        return bounds(for: rangeValue as! AXValue, in: element)
    }

    private static func selectedTextRangesBounds(_ element: AXUIElement) -> CGRect? {
        var rangesValue: CFTypeRef?
        let rangesResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangesAttribute as CFString,
            &rangesValue
        )
        guard rangesResult == .success,
              let rangeValues = rangesValue as? [AXValue]
        else {
            return nil
        }

        let rects = rangeValues.compactMap { bounds(for: $0, in: element) }
        guard var union = rects.first else { return nil }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union
    }

    private static func bounds(for rangeAXValue: AXValue, in element: AXUIElement) -> CGRect? {
        guard AXValueGetType(rangeAXValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeAXValue, .cfRange, &range),
              let parameter = AXValueCreate(.cfRange, &range)
        else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsResult = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            parameter,
            &boundsValue
        )
        guard boundsResult == .success,
              let boundsValue
        else {
            return nil
        }
        let boundsAXValue = boundsValue as! AXValue
        guard AXValueGetType(boundsAXValue) == .cgRect else {
            return nil
        }

        var bounds = CGRect.zero
        guard AXValueGetValue(boundsAXValue, .cgRect, &bounds) else {
            return nil
        }
        return bounds.isEmpty ? nil : bounds
    }

    private static func isUsableSelectionBounds(_ bounds: CGRect) -> Bool {
        guard bounds.origin.x.isFinite,
              bounds.origin.y.isFinite,
              bounds.width.isFinite,
              bounds.height.isFinite,
              !bounds.isEmpty
        else {
            return false
        }

        let screenUnion = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        guard !screenUnion.isNull, !screenUnion.isEmpty else { return true }

        let maxUsableWidth = screenUnion.width * 0.95
        let maxUsableHeight = max(CGFloat(120), screenUnion.height * 0.35)
        return bounds.width <= maxUsableWidth && bounds.height <= maxUsableHeight
    }
}
