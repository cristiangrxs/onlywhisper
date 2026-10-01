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

    /// Walks from the focused control toward the window and stops at the window itself.
    /// The first control that can take text is the insertion target.
    static func insertionIndex(in chain: [(role: String?, selectedTextSettable: Bool)]) -> Int? {
        for (index, candidate) in chain.prefix(6).enumerated() {
            if candidate.role == "AXWindow" || candidate.role == "AXApplication" { return nil }
            if canAcceptInsertion(role: candidate.role, selectedTextSettable: candidate.selectedTextSettable) {
                return index
            }
        }
        return nil
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
        revealFrontApplication()
        field = focusedElement().flatMap(editableElement(from:))
        insertedRange = nil
        insertedWithPaste = false
    }

    /// Replaces the text this dictation already wrote.
    /// A direct write is enough for native fields. Electron fields such as Cursor's composer report success
    /// and then drop the characters, so the finished text is pasted into that same field instead.
    /// Returns false when no input was focused, so the caller can keep the text for copying.
    @discardableResult
    static func replaceInsertion(with text: String, allowPasteFallback: Bool = false) async -> Bool {
        if let field, replaceOwned(text, in: field) {
            insertedWithPaste = false
            return true
        }
        guard allowPasteFallback, !text.isEmpty, !insertedWithPaste, insertedRange == nil else { return false }
        if field == nil {
            field = await editableFocus()
        }
        guard let target = field, canReceivePaste(target) else { return false }
        await focusForPaste(target)
        if replaceOwned(text, in: target) {
            insertedWithPaste = false
            return true
        }
        paste(text)
        insertedWithPaste = true
        return true
    }

    /// Removes the text this dictation inserted and forgets the field.
    static func revertInsertion() {
        undoLiveInsertion()
        field = nil
    }

    /// Removes a live draft but keeps the field captured when dictation started.
    static func undoLiveInsertion() {
        if let field, insertedRange != nil {
            _ = replaceOwned("", in: field)
        }
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
            guard setSelectedText(text, of: element), confirmed(text, at: existing.location, in: element) else {
                return false
            }
            insertedRange = CFRange(location: existing.location, length: length)
            return true
        }
        guard let cursor = selectedRange(of: element) else { return false }
        guard setSelectedRange(cursor, of: element) else { return false }
        guard setSelectedText(text, of: element), confirmed(text, at: cursor.location, in: element) else {
            return false
        }
        insertedRange = CFRange(location: cursor.location, length: length)
        return true
    }

    /// Some fields, such as Mail and Cursor, report success and move the caret but drop the text.
    /// The write counts only when those characters can be read back.
    private static func confirmed(_ text: String, at location: Int, in element: AXUIElement) -> Bool {
        let length = (text as NSString).length
        if text.isEmpty {
            guard let after = selectedRange(of: element) else { return false }
            return after.location == location && after.length == 0
        }
        let range = CFRange(location: location, length: length)
        guard setSelectedRange(range, of: element), selectedText(of: element) == text else { return false }
        return true
    }

    /// Electron hides its text fields until this is set. Native fields are unchanged.
    private static let manualAccessibility = "AXManualAccessibility" as CFString

    private static func revealFrontApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetAttributeValue(element, manualAccessibility, kCFBooleanTrue)
    }

    /// Asks the front app to expose its text field, then reads it. Electron needs a moment the first time.
    private static func editableFocus() async -> AXUIElement? {
        revealFrontApplication()
        if let element = focusedElement().flatMap(editableElement(from:)) { return element }
        try? await Task.sleep(for: .milliseconds(400))
        revealFrontApplication()
        return focusedElement().flatMap(editableElement(from:))
    }

    /// The focused control, or a text control that contains it. A window or a plain web page is not a target.
    private static func editableElement(from element: AXUIElement) -> AXUIElement? {
        var chain: [(role: String?, selectedTextSettable: Bool)] = []
        var elements: [AXUIElement] = []
        var node: AXUIElement? = element
        for _ in 0..<6 {
            guard let visited = node else { break }
            elements.append(visited)
            chain.append((role(of: visited), selectedTextIsSettable(visited)))
            node = parent(of: visited)
        }
        guard let index = TextTarget.insertionIndex(in: chain) else { return nil }
        return elements[index]
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &value) == .success,
              let value else { return nil }
        return (value as! AXUIElement)
    }

    private static func canReceivePaste(_ element: AXUIElement) -> Bool {
        TextTarget.canAcceptInsertion(
            role: role(of: element),
            selectedTextSettable: selectedTextIsSettable(element)
        )
    }

    /// Puts the captured field in front so Command-V reaches it after the capsule was on screen.
    private static func focusForPaste(_ element: AXUIElement) async {
        if NSApp.isActive {
            NSApp.hide(nil)
        }
        var pid: pid_t = 0
        if AXUIElementGetPid(element, &pid) == .success,
           let app = NSRunningApplication(processIdentifier: pid),
           !app.isActive {
            _ = app.activate(from: .current, options: [.activateIgnoringOtherApps])
        }
        try? await Task.sleep(for: .milliseconds(200))
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard result == .success, let text = value as? String else { return nil }
        return text
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
