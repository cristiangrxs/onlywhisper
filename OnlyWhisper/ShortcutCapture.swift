import Carbon.HIToolbox
import CoreGraphics
import Foundation
import IOKit.hidsystem

/// Which side of a modifier is held. `.both` means either the two sides together or the side is unknown.
enum KeySide: Equatable, Sendable {
    case left
    case right
    case both
}

/// A dictation binding: one modifier, or a modifier chord plus a key.
enum DictationKey: Equatable, Sendable {
    case modifier(SideModifier)
    case chord(keyCode: Int, carbonModifiers: Int, function: Bool)

    static let rightOption = DictationKey.modifier(.rightOption)
    static let leftOption = DictationKey.modifier(.leftOption)

    enum SideModifier: String, Codable, Sendable {
        case rightOption
        case leftOption
        case option
        case rightControl
        case leftControl
        case control
        case rightShift
        case leftShift
        case shift
        case rightCommand
        case leftCommand
        case command
        case function
    }

    var keycaps: [String] {
        switch self {
        case .modifier(let side):
            [ShortcutSymbols.label(for: side)]
        case .chord(let keyCode, let carbonModifiers, let function):
            ShortcutSymbols.keycaps(keyCode: keyCode, carbonModifiers: carbonModifiers, function: function)
        }
    }

    var title: String { keycaps.joined() }
}

extension DictationKey: Codable {
    private enum CodingKeys: String, CodingKey {
        case modifier
        case keyCode
        case carbonModifiers
        case function
    }

    init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            self = Self(legacy: raw)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let name = try container.decodeIfPresent(String.self, forKey: .modifier) {
            self = .modifier(SideModifier(rawValue: name) ?? .rightOption)
            return
        }
        let keyCode = try container.decode(Int.self, forKey: .keyCode)
        let carbonModifiers = try container.decodeIfPresent(Int.self, forKey: .carbonModifiers) ?? 0
        let function = try container.decodeIfPresent(Bool.self, forKey: .function) ?? false
        self = .chord(keyCode: keyCode, carbonModifiers: carbonModifiers, function: function)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .modifier(let side):
            try container.encode(side.rawValue, forKey: .modifier)
        case .chord(let keyCode, let carbonModifiers, let function):
            try container.encode(keyCode, forKey: .keyCode)
            try container.encode(carbonModifiers, forKey: .carbonModifiers)
            try container.encode(function, forKey: .function)
        }
    }

    /// Settings written before chords existed stored `"rightOption"` or `"leftOption"`.
    private init(legacy: String) {
        switch legacy {
        case "leftOption": self = .leftOption
        default: self = .rightOption
        }
    }
}

enum ShortcutCaptureMode: Equatable, Sendable {
    /// Needs Control, Option, Command, or a function key. Backspace clears.
    case global
    /// A single modifier, or a modifier plus a key. Cannot be cleared.
    case dictation
}

enum ShortcutToken: Equatable, Sendable {
    case control(KeySide)
    case option(KeySide)
    case shift(KeySide)
    case command(KeySide)
    case function
}

struct ShortcutPreview: Equatable, Sendable {
    var tokens: [ShortcutToken]
    var showsPlus: Bool

    static let empty = ShortcutPreview(tokens: [], showsPlus: false)
}

enum ShortcutCaptureEvent: Equatable, Sendable {
    case flagsChanged(keyCode: Int, flags: UInt64)
    case keyDown(keyCode: Int, flags: UInt64)
}

enum ShortcutCaptureResult: Equatable, Sendable {
    case preview(ShortcutPreview)
    case commit(DictationKey)
    case clear
    case cancel
    case reject
}

/// Turns key events into a live preview and, once the chord is complete, a binding.
struct ShortcutCapture: Sendable {
    var mode: ShortcutCaptureMode
    private var seen = Set<ModifierKind>()
    private var lastNonEmpty: HeldModifiers?

    init(mode: ShortcutCaptureMode) {
        self.mode = mode
    }

    mutating func handle(_ event: ShortcutCaptureEvent) -> ShortcutCaptureResult? {
        switch event {
        case .flagsChanged(let keyCode, let flags):
            return flagsChanged(keyCode: keyCode, flags: flags)
        case .keyDown(let keyCode, let flags):
            return keyDown(keyCode: keyCode, flags: flags)
        }
    }

    private mutating func flagsChanged(keyCode: Int, flags: UInt64) -> ShortcutCaptureResult {
        let held = HeldModifiers(flags: flags, sideKeyCode: keyCode)
        guard !held.isEmpty else {
            let modifier = mode == .dictation && seen.count == 1 ? lastNonEmpty?.soleModifier : nil
            seen = []
            lastNonEmpty = nil
            if let modifier {
                return .commit(.modifier(modifier))
            }
            return .preview(.empty)
        }
        seen.formUnion(held.kinds)
        lastNonEmpty = held
        return .preview(held.preview)
    }

    private func keyDown(keyCode: Int, flags: UInt64) -> ShortcutCaptureResult? {
        if Self.modifierKeyCodes.contains(keyCode) { return nil }
        if keyCode == Int(kVK_Escape) { return .cancel }
        let held = HeldModifiers(flags: flags, sideKeyCode: nil)
        if keyCode == Int(kVK_Tab), held.isEmpty { return .cancel }
        if (keyCode == Int(kVK_Delete) || keyCode == Int(kVK_ForwardDelete)), held.isEmpty {
            return mode == .global ? .clear : .reject
        }
        let functionKey = ShortcutSymbols.isFunctionKey(keyCode)
        switch mode {
        case .global:
            guard functionKey || held.hasNonShiftModifier else { return .reject }
        case .dictation:
            guard functionKey || !held.isEmpty else { return .reject }
        }
        return .commit(.chord(
            keyCode: keyCode,
            carbonModifiers: held.carbon,
            function: functionKey ? false : held.function
        ))
    }

    private static let modifierKeyCodes: Set<Int> = [
        Int(kVK_Command), Int(kVK_RightCommand),
        Int(kVK_Shift), Int(kVK_RightShift),
        Int(kVK_Option), Int(kVK_RightOption),
        Int(kVK_Control), Int(kVK_RightControl),
        Int(kVK_Function), Int(kVK_CapsLock)
    ]
}

enum ShortcutSymbols {
    static func keycaps(_ preview: ShortcutPreview) -> [String] {
        let showSide = preview.tokens.count == 1
        var caps = preview.tokens.map { label(for: $0, showSide: showSide) }
        if preview.showsPlus { caps.append("+") }
        return caps
    }

    static func keycaps(keyCode: Int, carbonModifiers: Int, function: Bool) -> [String] {
        var caps: [String] = []
        if function { caps.append("fn") }
        if carbonModifiers & Int(controlKey) != 0 { caps.append("⌃") }
        if carbonModifiers & Int(optionKey) != 0 { caps.append("⌥") }
        if carbonModifiers & Int(shiftKey) != 0 { caps.append("⇧") }
        if carbonModifiers & Int(cmdKey) != 0 { caps.append("⌘") }
        caps.append(label(for: keyCode))
        return caps
    }

    static func label(for modifier: DictationKey.SideModifier) -> String {
        switch modifier {
        case .rightOption: t("Right ⌥", "Rechts ⌥")
        case .leftOption: t("Left ⌥", "Links ⌥")
        case .option: "⌥"
        case .rightControl: t("Right ⌃", "Rechts ⌃")
        case .leftControl: t("Left ⌃", "Links ⌃")
        case .control: "⌃"
        case .rightShift: t("Right ⇧", "Rechts ⇧")
        case .leftShift: t("Left ⇧", "Links ⇧")
        case .shift: "⇧"
        case .rightCommand: t("Right ⌘", "Rechts ⌘")
        case .leftCommand: t("Left ⌘", "Links ⌘")
        case .command: "⌘"
        case .function: "fn"
        }
    }

    static func isFunctionKey(_ keyCode: Int) -> Bool {
        functionKeyLabels[keyCode] != nil
    }

    static func label(for keyCode: Int) -> String {
        if let special = specialLabels[keyCode] { return special }
        if let function = functionKeyLabels[keyCode] { return function }
        if let layout = layoutCharacter(for: keyCode), !layout.isEmpty {
            return layout.count == 1 ? layout.uppercased() : layout
        }
        if let ansi = ansiLabels[keyCode] { return ansi }
        return "?"
    }

    private static func label(for token: ShortcutToken, showSide: Bool) -> String {
        switch token {
        case .control(let side):
            sideLabel(side, showSide: showSide, symbol: "⌃", left: label(for: .leftControl), right: label(for: .rightControl))
        case .option(let side):
            sideLabel(side, showSide: showSide, symbol: "⌥", left: label(for: .leftOption), right: label(for: .rightOption))
        case .shift(let side):
            sideLabel(side, showSide: showSide, symbol: "⇧", left: label(for: .leftShift), right: label(for: .rightShift))
        case .command(let side):
            sideLabel(side, showSide: showSide, symbol: "⌘", left: label(for: .leftCommand), right: label(for: .rightCommand))
        case .function:
            "fn"
        }
    }

    private static func sideLabel(_ side: KeySide, showSide: Bool, symbol: String, left: String, right: String) -> String {
        guard showSide else { return symbol }
        switch side {
        case .left: return left
        case .right: return right
        case .both: return symbol
        }
    }

    /// Character for the physical key, ignoring Option so ⌥F stays F.
    private static func layoutCharacter(for keyCode: Int) -> String? {
        guard
            let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeyState: UInt32 = 0
        let maxLength = 4
        var length = 0
        var characters = [UniChar](repeating: 0, count: maxLength)
        let error = UCKeyTranslate(
            keyLayout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0,
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            maxLength,
            &length,
            &characters
        )
        guard error == noErr else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }

    private static let specialLabels: [Int: String] = [
        Int(kVK_Space): "Space",
        Int(kVK_Return): "↩",
        Int(kVK_ANSI_KeypadEnter): "↩",
        Int(kVK_Tab): "⇥",
        Int(kVK_Escape): "esc",
        Int(kVK_Delete): "⌫",
        Int(kVK_ForwardDelete): "⌦",
        Int(kVK_LeftArrow): "←",
        Int(kVK_RightArrow): "→",
        Int(kVK_UpArrow): "↑",
        Int(kVK_DownArrow): "↓"
    ]

    private static let functionKeyLabels: [Int: String] = [
        Int(kVK_F1): "F1", Int(kVK_F2): "F2", Int(kVK_F3): "F3", Int(kVK_F4): "F4",
        Int(kVK_F5): "F5", Int(kVK_F6): "F6", Int(kVK_F7): "F7", Int(kVK_F8): "F8",
        Int(kVK_F9): "F9", Int(kVK_F10): "F10", Int(kVK_F11): "F11", Int(kVK_F12): "F12",
        Int(kVK_F13): "F13", Int(kVK_F14): "F14", Int(kVK_F15): "F15", Int(kVK_F16): "F16",
        Int(kVK_F17): "F17", Int(kVK_F18): "F18", Int(kVK_F19): "F19", Int(kVK_F20): "F20"
    ]

    private static let ansiLabels: [Int: String] = [
        Int(kVK_ANSI_A): "A", Int(kVK_ANSI_B): "B", Int(kVK_ANSI_C): "C", Int(kVK_ANSI_D): "D",
        Int(kVK_ANSI_E): "E", Int(kVK_ANSI_F): "F", Int(kVK_ANSI_G): "G", Int(kVK_ANSI_H): "H",
        Int(kVK_ANSI_I): "I", Int(kVK_ANSI_J): "J", Int(kVK_ANSI_K): "K", Int(kVK_ANSI_L): "L",
        Int(kVK_ANSI_M): "M", Int(kVK_ANSI_N): "N", Int(kVK_ANSI_O): "O", Int(kVK_ANSI_P): "P",
        Int(kVK_ANSI_Q): "Q", Int(kVK_ANSI_R): "R", Int(kVK_ANSI_S): "S", Int(kVK_ANSI_T): "T",
        Int(kVK_ANSI_U): "U", Int(kVK_ANSI_V): "V", Int(kVK_ANSI_W): "W", Int(kVK_ANSI_X): "X",
        Int(kVK_ANSI_Y): "Y", Int(kVK_ANSI_Z): "Z"
    ]
}

/// Press and release edges for the dictation binding.
struct DictationPress: Sendable {
    enum Change: Equatable, Sendable {
        case pressed
        case released
    }

    enum Event: Equatable, Sendable {
        case flagsChanged
        case keyDown
        case keyUp
    }

    struct Step: Equatable, Sendable {
        var change: Change?
        var swallow: Bool
    }

    var binding: DictationKey
    private(set) var isDown = false
    /// The chord key's key-down was swallowed, so its key-up must be swallowed too.
    private var armedKey = false

    init(binding: DictationKey = .rightOption) {
        self.binding = binding
    }

    mutating func reset() {
        isDown = false
        armedKey = false
    }

    mutating func handle(flags: UInt64, eventKeyCode: Int64) -> Change? {
        handle(event: .flagsChanged, flags: flags, eventKeyCode: eventKeyCode, isRepeat: false).change
    }

    mutating func handle(event: Event, flags: UInt64, eventKeyCode: Int64, isRepeat: Bool = false) -> Step {
        switch binding {
        case .modifier(let side):
            let keyCode = event == .flagsChanged ? eventKeyCode : 0
            return Step(change: set(Self.modifierIsDown(side, flags: flags, eventKeyCode: keyCode)), swallow: false)
        case .chord(let keyCode, let carbonModifiers, let function):
            return chordStep(
                event: event,
                flags: flags,
                eventKeyCode: eventKeyCode,
                isRepeat: isRepeat,
                keyCode: keyCode,
                carbonModifiers: carbonModifiers,
                function: function
            )
        }
    }

    /// Corrects a missed key-up. A key that is already held does not count as a new press.
    mutating func reconcile(flags: UInt64) -> Change? {
        switch binding {
        case .modifier(let side):
            let down = Self.modifierIsDown(side, flags: flags, eventKeyCode: 0)
            guard isDown, !down else { return nil }
            isDown = false
            return .released
        case .chord(let keyCode, let carbonModifiers, let function):
            guard isDown else { return nil }
            let modsOK = Self.chordModifiersMatch(
                flags: flags,
                carbonModifiers: carbonModifiers,
                function: function,
                keyCode: keyCode
            )
            guard !modsOK else { return nil }
            isDown = false
            return .released
        }
    }

    private mutating func chordStep(
        event: Event,
        flags: UInt64,
        eventKeyCode: Int64,
        isRepeat: Bool,
        keyCode: Int,
        carbonModifiers: Int,
        function: Bool
    ) -> Step {
        let modsOK = Self.chordModifiersMatch(
            flags: flags,
            carbonModifiers: carbonModifiers,
            function: function,
            keyCode: keyCode
        )
        let isKey = eventKeyCode == Int64(keyCode)
        switch event {
        case .keyDown where isKey && modsOK:
            armedKey = true
            if isRepeat { return Step(change: nil, swallow: true) }
            return Step(change: set(true), swallow: true)
        case .keyUp where isKey && armedKey:
            armedKey = false
            return Step(change: set(false), swallow: true)
        case .flagsChanged where isDown && !modsOK:
            return Step(change: set(false), swallow: false)
        default:
            return Step(change: nil, swallow: false)
        }
    }

    private mutating func set(_ down: Bool) -> Change? {
        guard down != isDown else { return nil }
        isDown = down
        return down ? .pressed : .released
    }

    static func modifierIsDown(_ modifier: DictationKey.SideModifier, flags: UInt64, eventKeyCode: Int64) -> Bool {
        switch modifier {
        case .rightOption:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELALTKEYMASK), rightBit: UInt64(NX_DEVICERALTKEYMASK), generic: CGEventFlags.maskAlternate.rawValue, leftCode: Int64(kVK_Option), rightCode: Int64(kVK_RightOption), wantRight: true)
        case .leftOption:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELALTKEYMASK), rightBit: UInt64(NX_DEVICERALTKEYMASK), generic: CGEventFlags.maskAlternate.rawValue, leftCode: Int64(kVK_Option), rightCode: Int64(kVK_RightOption), wantRight: false)
        case .option:
            eitherIsDown(flags: flags, leftBit: UInt64(NX_DEVICELALTKEYMASK), rightBit: UInt64(NX_DEVICERALTKEYMASK), generic: CGEventFlags.maskAlternate.rawValue)
        case .rightControl:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELCTLKEYMASK), rightBit: UInt64(NX_DEVICERCTLKEYMASK), generic: CGEventFlags.maskControl.rawValue, leftCode: Int64(kVK_Control), rightCode: Int64(kVK_RightControl), wantRight: true)
        case .leftControl:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELCTLKEYMASK), rightBit: UInt64(NX_DEVICERCTLKEYMASK), generic: CGEventFlags.maskControl.rawValue, leftCode: Int64(kVK_Control), rightCode: Int64(kVK_RightControl), wantRight: false)
        case .control:
            eitherIsDown(flags: flags, leftBit: UInt64(NX_DEVICELCTLKEYMASK), rightBit: UInt64(NX_DEVICERCTLKEYMASK), generic: CGEventFlags.maskControl.rawValue)
        case .rightShift:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELSHIFTKEYMASK), rightBit: UInt64(NX_DEVICERSHIFTKEYMASK), generic: CGEventFlags.maskShift.rawValue, leftCode: Int64(kVK_Shift), rightCode: Int64(kVK_RightShift), wantRight: true)
        case .leftShift:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELSHIFTKEYMASK), rightBit: UInt64(NX_DEVICERSHIFTKEYMASK), generic: CGEventFlags.maskShift.rawValue, leftCode: Int64(kVK_Shift), rightCode: Int64(kVK_RightShift), wantRight: false)
        case .shift:
            eitherIsDown(flags: flags, leftBit: UInt64(NX_DEVICELSHIFTKEYMASK), rightBit: UInt64(NX_DEVICERSHIFTKEYMASK), generic: CGEventFlags.maskShift.rawValue)
        case .rightCommand:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELCMDKEYMASK), rightBit: UInt64(NX_DEVICERCMDKEYMASK), generic: CGEventFlags.maskCommand.rawValue, leftCode: Int64(kVK_Command), rightCode: Int64(kVK_RightCommand), wantRight: true)
        case .leftCommand:
            sideIsDown(flags: flags, eventKeyCode: eventKeyCode, leftBit: UInt64(NX_DEVICELCMDKEYMASK), rightBit: UInt64(NX_DEVICERCMDKEYMASK), generic: CGEventFlags.maskCommand.rawValue, leftCode: Int64(kVK_Command), rightCode: Int64(kVK_RightCommand), wantRight: false)
        case .command:
            eitherIsDown(flags: flags, leftBit: UInt64(NX_DEVICELCMDKEYMASK), rightBit: UInt64(NX_DEVICERCMDKEYMASK), generic: CGEventFlags.maskCommand.rawValue)
        case .function:
            flags & CGEventFlags.maskSecondaryFn.rawValue != 0
        }
    }

    static func chordModifiersMatch(flags: UInt64, carbonModifiers: Int, function: Bool, keyCode: Int) -> Bool {
        func matches(bit: Int, generic: UInt64, left: UInt64, right: UInt64) -> Bool {
            let wants = carbonModifiers & bit != 0
            let down = flags & generic != 0 || flags & left != 0 || flags & right != 0
            return wants == down
        }
        let fnDown = flags & CGEventFlags.maskSecondaryFn.rawValue != 0
        let fnOK = function ? fnDown : (ShortcutSymbols.isFunctionKey(keyCode) || !fnDown)
        return matches(bit: Int(controlKey), generic: CGEventFlags.maskControl.rawValue, left: UInt64(NX_DEVICELCTLKEYMASK), right: UInt64(NX_DEVICERCTLKEYMASK))
            && matches(bit: Int(optionKey), generic: CGEventFlags.maskAlternate.rawValue, left: UInt64(NX_DEVICELALTKEYMASK), right: UInt64(NX_DEVICERALTKEYMASK))
            && matches(bit: Int(shiftKey), generic: CGEventFlags.maskShift.rawValue, left: UInt64(NX_DEVICELSHIFTKEYMASK), right: UInt64(NX_DEVICERSHIFTKEYMASK))
            && matches(bit: Int(cmdKey), generic: CGEventFlags.maskCommand.rawValue, left: UInt64(NX_DEVICELCMDKEYMASK), right: UInt64(NX_DEVICERCMDKEYMASK))
            && fnOK
    }

    private static func sideIsDown(
        flags: UInt64,
        eventKeyCode: Int64,
        leftBit: UInt64,
        rightBit: UInt64,
        generic: UInt64,
        leftCode: Int64,
        rightCode: Int64,
        wantRight: Bool
    ) -> Bool {
        let left = flags & leftBit != 0
        let right = flags & rightBit != 0
        if left || right {
            return wantRight ? right : left
        }
        let alternate = flags & generic != 0
        return alternate && eventKeyCode == (wantRight ? rightCode : leftCode)
    }

    private static func eitherIsDown(flags: UInt64, leftBit: UInt64, rightBit: UInt64, generic: UInt64) -> Bool {
        flags & leftBit != 0 || flags & rightBit != 0 || flags & generic != 0
    }
}

private enum ModifierKind: Hashable {
    case control
    case option
    case shift
    case command
    case function
}

private struct HeldModifiers: Equatable {
    var control: KeySide?
    var option: KeySide?
    var shift: KeySide?
    var command: KeySide?
    var function: Bool

    var isEmpty: Bool {
        control == nil && option == nil && shift == nil && command == nil && !function
    }

    var hasNonShiftModifier: Bool {
        control != nil || option != nil || command != nil
    }

    var carbon: Int {
        var value = 0
        if control != nil { value |= Int(controlKey) }
        if option != nil { value |= Int(optionKey) }
        if shift != nil { value |= Int(shiftKey) }
        if command != nil { value |= Int(cmdKey) }
        return value
    }

    var kinds: Set<ModifierKind> {
        var result = Set<ModifierKind>()
        if control != nil { result.insert(.control) }
        if option != nil { result.insert(.option) }
        if shift != nil { result.insert(.shift) }
        if command != nil { result.insert(.command) }
        if function { result.insert(.function) }
        return result
    }

    var preview: ShortcutPreview {
        var tokens: [ShortcutToken] = []
        if let control { tokens.append(.control(control)) }
        if let option { tokens.append(.option(option)) }
        if let shift { tokens.append(.shift(shift)) }
        if let command { tokens.append(.command(command)) }
        if function { tokens.append(.function) }
        return ShortcutPreview(tokens: tokens, showsPlus: !tokens.isEmpty)
    }

    var soleModifier: DictationKey.SideModifier? {
        var found: DictationKey.SideModifier?
        func take(_ side: KeySide?, _ value: DictationKey.SideModifier) -> Bool {
            guard side != nil else { return true }
            guard found == nil else { return false }
            found = value
            return true
        }
        guard take(control, controlValue), take(option, optionValue), take(shift, shiftValue), take(command, commandValue) else {
            return nil
        }
        if function {
            guard found == nil else { return nil }
            return .function
        }
        return found
    }

    private var controlValue: DictationKey.SideModifier {
        switch control {
        case .left: .leftControl
        case .right: .rightControl
        case .both, nil: .control
        }
    }

    private var optionValue: DictationKey.SideModifier {
        switch option {
        case .left: .leftOption
        case .right: .rightOption
        case .both, nil: .option
        }
    }

    private var shiftValue: DictationKey.SideModifier {
        switch shift {
        case .left: .leftShift
        case .right: .rightShift
        case .both, nil: .shift
        }
    }

    private var commandValue: DictationKey.SideModifier {
        switch command {
        case .left: .leftCommand
        case .right: .rightCommand
        case .both, nil: .command
        }
    }

    init(flags: UInt64, sideKeyCode: Int?) {
        control = Self.side(
            flags: flags,
            sideKeyCode: sideKeyCode,
            leftBit: UInt64(NX_DEVICELCTLKEYMASK),
            rightBit: UInt64(NX_DEVICERCTLKEYMASK),
            generic: CGEventFlags.maskControl.rawValue,
            leftCode: Int(kVK_Control),
            rightCode: Int(kVK_RightControl)
        )
        option = Self.side(
            flags: flags,
            sideKeyCode: sideKeyCode,
            leftBit: UInt64(NX_DEVICELALTKEYMASK),
            rightBit: UInt64(NX_DEVICERALTKEYMASK),
            generic: CGEventFlags.maskAlternate.rawValue,
            leftCode: Int(kVK_Option),
            rightCode: Int(kVK_RightOption)
        )
        shift = Self.side(
            flags: flags,
            sideKeyCode: sideKeyCode,
            leftBit: UInt64(NX_DEVICELSHIFTKEYMASK),
            rightBit: UInt64(NX_DEVICERSHIFTKEYMASK),
            generic: CGEventFlags.maskShift.rawValue,
            leftCode: Int(kVK_Shift),
            rightCode: Int(kVK_RightShift)
        )
        command = Self.side(
            flags: flags,
            sideKeyCode: sideKeyCode,
            leftBit: UInt64(NX_DEVICELCMDKEYMASK),
            rightBit: UInt64(NX_DEVICERCMDKEYMASK),
            generic: CGEventFlags.maskCommand.rawValue,
            leftCode: Int(kVK_Command),
            rightCode: Int(kVK_RightCommand)
        )
        function = flags & CGEventFlags.maskSecondaryFn.rawValue != 0
    }

    private static func side(
        flags: UInt64,
        sideKeyCode: Int?,
        leftBit: UInt64,
        rightBit: UInt64,
        generic: UInt64,
        leftCode: Int,
        rightCode: Int
    ) -> KeySide? {
        let left = flags & leftBit != 0
        let right = flags & rightBit != 0
        if left && right { return .both }
        if right { return .right }
        if left { return .left }
        guard flags & generic != 0 else { return nil }
        if sideKeyCode == leftCode { return .left }
        if sideKeyCode == rightCode { return .right }
        return .both
    }
}
