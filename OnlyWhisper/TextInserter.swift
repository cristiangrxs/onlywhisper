import AppKit
import ApplicationServices
import Foundation

@MainActor
enum TextInserter {
    private static var field: AXUIElement?
    private static var insertedRange: CFRange?
    private static var insertedWithPaste = false

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        if replaceSelection(with: text) { return }
        paste(text)
    }

    /// Remembers the focused field so later updates replace the same insertion.
    static func beginInsertion() {
        field = focusedElement()
        insertedRange = nil
        insertedWithPaste = false
    }

    /// Replaces the text this dictation already wrote. Paste is only used when the field cannot be edited directly.
    static func replaceInsertion(with text: String, allowPasteFallback: Bool = false) {
        if let field, replaceOwned(text, in: field) {
            insertedWithPaste = false
            return
        }
        guard allowPasteFallback, !text.isEmpty, !insertedWithPaste, insertedRange == nil else { return }
        paste(text)
        insertedWithPaste = true
    }

    /// Removes the text this dictation inserted.
    static func revertInsertion() {
        if let field, insertedRange != nil {
            _ = replaceOwned("", in: field)
        }
        field = nil
        insertedRange = nil
        insertedWithPaste = false
    }

    static func selectedText() -> String? {
        guard let element = focusedElement() else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        return text
    }

    @discardableResult
    static func replaceSelection(with text: String) -> Bool {
        guard let element = focusedElement() else { return false }
        return setSelectedText(text, of: element)
    }

    @discardableResult
    private static func replaceOwned(_ text: String, in element: AXUIElement) -> Bool {
        let length = (text as NSString).length
        if let existing = insertedRange {
            guard setSelectedRange(existing, of: element) else { return false }
            guard setSelectedText(text, of: element) else { return false }
            insertedRange = CFRange(location: existing.location, length: length)
            return true
        }
        let cursor = selectedRange(of: element) ?? CFRange(location: 0, length: 0)
        guard setSelectedRange(CFRange(location: cursor.location, length: cursor.length), of: element) else { return false }
        guard setSelectedText(text, of: element) else { return false }
        insertedRange = CFRange(location: cursor.location, length: length)
        return true
    }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let element = value else { return nil }
        return (element as! AXUIElement)
    }

    private static func selectedRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        var range = CFRange()
        guard AXValueGetType(axValue) == .cfRange, AXValueGetValue(axValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func setSelectedRange(_ range: CFRange, of element: AXUIElement) -> Bool {
        var range = range
        guard let axValue = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axValue) == .success
    }

    private static func setSelectedText(_ text: String, of element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private static func paste(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            pasteboard.clearContents()
            if let previous {
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}
