import AppKit
import ApplicationServices
import Foundation

/// Whether the focused control can take dictated text. Web pages, windows, and buttons cannot,
/// unless the selection itself is editable (a content-editable region reports that).
enum TextTarget {
    /// Accessibility role names. Search and secure fields are not exposed as Swift constants in this SDK.
    static let writableRoles: Set<String> = [
        "AXTextField",
        "AXTextArea",
        "AXComboBox",
        "AXSearchField",
        "AXSecureTextField",
    ]

    static func canAcceptInsertion(role: String?, selectedTextSettable: Bool) -> Bool {
        if selectedTextSettable { return true }
        guard let role else { return false }
        return writableRoles.contains(role)
    }
}

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
    /// Returns false when nothing reached the field, so the caller can show the text elsewhere.
    @discardableResult
    static func replaceInsertion(with text: String, allowPasteFallback: Bool = false) -> Bool {
        if let field, replaceOwned(text, in: field) {
            insertedWithPaste = false
            return true
        }
        guard allowPasteFallback, !text.isEmpty, !insertedWithPaste, insertedRange == nil else { return false }
        guard let element = focusedElement(), canReceivePaste(element) else { return false }
        paste(text)
        insertedWithPaste = true
        return true
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
            guard setSelectedText(text, of: element), landed(at: existing.location, length: length, in: element) else {
                return false
            }
            insertedRange = CFRange(location: existing.location, length: length)
            return true
        }
        guard let cursor = selectedRange(of: element) else { return false }
        guard setSelectedRange(cursor, of: element) else { return false }
        guard setSelectedText(text, of: element), landed(at: cursor.location, length: length, in: element) else {
            return false
        }
        insertedRange = CFRange(location: cursor.location, length: length)
        return true
    }

    /// Some fields, such as the Mail compose body, report success but drop the text. After a real write the
    /// selection ends right behind the new text.
    private static func landed(at location: Int, length: Int, in element: AXUIElement) -> Bool {
        guard let after = selectedRange(of: element) else { return false }
        return after.location + after.length == location + length
    }

    /// Paste is a guess: it only runs when the focused control is a text field or its selection can be set.
    /// A bare window or web page would swallow Command-V and still look like a successful insert.
    private static func canReceivePaste(_ element: AXUIElement) -> Bool {
        TextTarget.canAcceptInsertion(
            role: role(of: element),
            selectedTextSettable: selectedTextIsSettable(element)
        )
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func selectedTextIsSettable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success else {
            return false
        }
        return settable.boolValue
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
