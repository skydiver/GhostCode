import AppKit

/// What the main window's key monitor does with a keyDown.
enum KeyShortcut: Equatable {
    case previousTab
    case nextTab
    case toggleLeftSidebar
    case toggleRightSidebar
    case selectTab(index: Int)
    case closeActiveTab
    case newShellTab
    case toggleFullScreen
    /// Consume the event: a Ghostty window or split shortcut that has no meaning in GhostCode.
    case swallow
}

/// Maps a keyDown to a GhostCode shortcut. Pure, so the whole table is unit-tested;
/// the controller only performs the returned action.
enum KeyShortcutRouter {
    struct Context {
        /// A project's terminals are on screen (not the startup or landing view).
        let hasActiveProject: Bool
        /// Tabs in the active project (0 when none).
        let tabCount: Int
    }

    /// Returns nil when the event should pass through to the terminal or menus.
    static func route(
        keyCode: UInt16,
        characters: String?,
        modifiers: NSEvent.ModifierFlags,
        context: Context
    ) -> KeyShortcut? {
        let key = Key(keyCode: keyCode, characters: characters,
                      modifiers: modifiers.intersection(.deviceIndependentFlagsMask))
        for rule in rules where rule.modifiers == key.modifiers && rule.matches(key) {
            if let shortcut = rule.action(key, context) { return shortcut }
        }
        return nil
    }

    // MARK: - Table

    private struct Key {
        let keyCode: UInt16
        let characters: String?
        let modifiers: NSEvent.ModifierFlags
    }

    private struct Rule {
        let modifiers: NSEvent.ModifierFlags
        let matches: (Key) -> Bool
        /// nil means "doesn't apply here": later rules are still tried.
        let action: (Key, Context) -> KeyShortcut?
    }

    private static let leftBracketKeyCode: UInt16 = 33
    private static let rightBracketKeyCode: UInt16 = 30
    private static let returnKeyCode: UInt16 = 36
    private static let arrowKeyCodes: Set<UInt16> = [123, 124, 125, 126]

    /// Matches `charactersIgnoringModifiers`, case-insensitively.
    private static func characters(_ options: String...) -> (Key) -> Bool {
        { key in options.contains(key.characters?.lowercased() ?? "") }
    }

    private static func keyCode(_ codes: Set<UInt16>) -> (Key) -> Bool {
        { key in codes.contains(key.keyCode) }
    }

    /// Fires only while a project's terminals are showing.
    private static func inProject(_ shortcut: KeyShortcut) -> (Key, Context) -> KeyShortcut? {
        { _, context in context.hasActiveProject ? shortcut : nil }
    }

    private static func always(_ shortcut: KeyShortcut) -> (Key, Context) -> KeyShortcut? {
        { _, _ in shortcut }
    }

    private static func digit(_ key: Key) -> Int? {
        guard let value = key.characters?.first?.wholeNumberValue, (1...9).contains(value) else { return nil }
        return value
    }

    /// Cmd+1…8 pick that tab (clamped to the last one); Cmd+9 is always the last tab.
    private static func selectTab(_ key: Key, _ context: Context) -> KeyShortcut? {
        guard context.hasActiveProject, context.tabCount > 0, let digit = digit(key) else { return nil }
        let last = context.tabCount - 1
        return .selectTab(index: digit == 9 ? last : min(digit - 1, last))
    }

    private static let rules: [Rule] = [
        // Cmd+Shift. Brackets by key code: Shift turns "[" into "{".
        Rule(modifiers: [.command, .shift], matches: keyCode([leftBracketKeyCode]),
             action: { _, context in context.hasActiveProject && context.tabCount > 1 ? .previousTab : nil }),
        Rule(modifiers: [.command, .shift], matches: keyCode([rightBracketKeyCode]),
             action: { _, context in context.hasActiveProject && context.tabCount > 1 ? .nextTab : nil }),
        Rule(modifiers: [.command, .shift], matches: characters("l"), action: always(.toggleLeftSidebar)),
        Rule(modifiers: [.command, .shift], matches: characters("r"), action: always(.toggleRightSidebar)),
        Rule(modifiers: [.command, .shift], matches: characters("d"), action: inProject(.swallow)), // new_split:down
        Rule(modifiers: [.command, .shift], matches: characters("w"), action: inProject(.swallow)), // close_window
        Rule(modifiers: [.command, .shift], matches: characters("p"), action: inProject(.swallow)), // command palette

        // Cmd+Alt
        Rule(modifiers: [.command, .option], matches: characters("i"), action: inProject(.swallow)), // inspector
        Rule(modifiers: [.command, .option], matches: keyCode(arrowKeyCodes), action: inProject(.swallow)), // goto_split

        // Cmd
        Rule(modifiers: [.command], matches: { digit($0) != nil }, action: selectTab),
        Rule(modifiers: [.command], matches: characters("w"),
             action: { _, context in context.hasActiveProject && context.tabCount > 0 ? .closeActiveTab : nil }),
        Rule(modifiers: [.command], matches: characters("t"), action: inProject(.newShellTab)),
        Rule(modifiers: [.command], matches: characters("n"), action: inProject(.swallow)), // new_window
        Rule(modifiers: [.command], matches: characters("d"), action: inProject(.swallow)), // new_split:right
        Rule(modifiers: [.command], matches: characters("[", "]"), action: inProject(.swallow)), // goto_split
        Rule(modifiers: [.command], matches: keyCode([returnKeyCode]), action: inProject(.toggleFullScreen)),

        // Cmd+Shift+Alt
        Rule(modifiers: [.command, .shift, .option], matches: characters("w"), action: inProject(.swallow)), // close_all_windows

        // Cmd+Ctrl
        Rule(modifiers: [.command, .control], matches: characters("f"), action: inProject(.toggleFullScreen)),
        Rule(modifiers: [.command, .control], matches: keyCode(arrowKeyCodes), action: inProject(.swallow)), // resize_split
        Rule(modifiers: [.command, .control], matches: characters("="), action: inProject(.swallow)), // equalize_splits
    ]
}
