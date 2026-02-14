import Foundation
import TauTUI
import XcodeQueryKit

@MainActor
final class TauInteractiveSession {
    private let core: XcodeProjectQuerySession
    private let debounceMs: Int
    private let colorEnabled: Bool

    private var tui: TUI?
    private var preview: PreviewTextComponent?
    private var running = false
    private var evalTask: Task<Void, Never>?
    private var revision: UInt64 = 0
    private var stopContinuation: CheckedContinuation<Void, Never>?

    init(core: XcodeProjectQuerySession, debounceMs: Int, colorEnabled: Bool) {
        self.core = core
        self.debounceMs = debounceMs
        self.colorEnabled = colorEnabled
    }

    func start() async throws {
        let terminal = ProcessTerminal()
        let tui = TUI(terminal: terminal)
        self.tui = tui

        let preview = PreviewTextComponent(text: hintText())
        self.preview = preview

        let editor = Editor()
        editor.disableSubmit = true
        editor.submitOnEnter = false
        editor.setAutocompleteProvider(GraphQLAutocompleteProvider())
        editor.onChange = { [weak self] text in
            guard let self else { return }
            self.scheduleEval(for: text)
        }

        let editorHost = EscapeAwareEditor(editor: editor)
        editorHost.onEscape = { [weak self] in
            self?.stop()
        }

        tui.onControlC = { [weak self] in
            self?.stop()
        }

        tui.addChild(preview)
        tui.addChild(Spacer(lines: 1))
        tui.addChild(editorHost)
        tui.setFocus(editorHost)

        try tui.start()
        running = true
        await withCheckedContinuation { continuation in
            if self.running {
                self.stopContinuation = continuation
            } else {
                continuation.resume(returning: ())
            }
        }
    }

    private func stop() {
        guard running || tui != nil else { return }
        running = false
        evalTask?.cancel()
        evalTask = nil
        tui?.stop()
        tui = nil
        if let continuation = stopContinuation {
            stopContinuation = nil
            continuation.resume(returning: ())
        }
    }

    private func scheduleEval(for text: String, immediate: Bool = false) {
        evalTask?.cancel()
        revision &+= 1
        let myRev = revision

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            renderPreviewIfLatest(hintText(), myRev: myRev)
            return
        }

        let balance = SmartEditing.computeBalance(text)
        if !balance.balanced {
            let deficit = abs(balance.depthCurlies) + abs(balance.depthParens)
            renderPreviewIfLatest(colorize("Unbalanced (\(deficit))", color: .dim), myRev: myRev)
            return
        }

        let coreBox = UncheckedSendable(core)
        let selfBox = WeakBox(self)
        let delay = immediate ? 0 : debounceMs

        evalTask = Task.detached {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            if Task.isCancelled { return }

            do {
                let any = try coreBox.value.evaluate(query: text)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted]
                let data = try encoder.encode(any)
                let output = String(data: data, encoding: .utf8) ?? ""
                if let strong = selfBox.value {
                    await strong.renderPreviewIfLatest(output, myRev: myRev)
                }
            } catch {
                if let strong = selfBox.value {
                    await strong.renderErrorIfLatest(String(describing: error), myRev: myRev)
                }
            }
        }
    }

    private func renderErrorIfLatest(_ message: String, myRev: UInt64) {
        renderPreviewIfLatest(colorize(message, color: .red), myRev: myRev)
    }

    private func renderPreviewIfLatest(_ text: String, myRev: UInt64) {
        guard myRev == revision else { return }
        preview?.text = text
        tui?.requestRender()
    }

    private func hintText() -> String {
        colorize("Type a selection, e.g., targets { name }", color: .dim)
    }

    private enum AnsiColor { case red, dim }

    private func colorize(_ text: String, color: AnsiColor) -> String {
        guard colorEnabled else { return text }
        let code: String
        switch color {
        case .red: code = "31"
        case .dim: code = "2"
        }
        return "\u{001B}[\(code)m\(text)\u{001B}[0m"
    }
}

private final class PreviewTextComponent: Component {
    var text: String

    init(text: String) {
        self.text = text
    }

    func render(width: Int) -> [String] {
        guard width > 0 else { return [] }
        return AnsiWrapping.wrapText(text, width: width)
    }
}

private final class EscapeAwareEditor: Component {
    private let editor: Editor
    var onEscape: (() -> Void)?

    init(editor: Editor) {
        self.editor = editor
    }

    func render(width: Int) -> [String] {
        editor.render(width: width)
    }

    func handle(input: TerminalInput) {
        if case let .key(.escape, modifiers) = input, modifiers.isEmpty {
            onEscape?()
            return
        }
        editor.handle(input: input)
    }

    func invalidate() {
        editor.invalidate()
    }

    @MainActor
    func apply(theme: ThemePalette) {
        editor.apply(theme: theme)
    }
}

private final class GraphQLAutocompleteProvider: AutocompleteProvider {
    private let completer = CompletionProvider()

    func getSuggestions(lines: [String], cursorLine: Int, cursorCol: Int) -> AutocompleteSuggestion? {
        guard lines.indices.contains(cursorLine) else { return nil }
        guard let suggestions = completer.suggest(lines: lines, row: cursorLine, col: cursorCol) else {
            return nil
        }
        let (prefix, _, _) = currentWord(in: lines[cursorLine], col: cursorCol)
        let items = suggestions.items.map { item in
            AutocompleteItem(value: item, label: item, description: nil)
        }
        return AutocompleteSuggestion(items: items, prefix: prefix)
    }

    func applyCompletion(
        lines: [String],
        cursorLine: Int,
        cursorCol: Int,
        item: AutocompleteItem,
        prefix _: String
    ) -> (lines: [String], cursorLine: Int, cursorCol: Int) {
        guard lines.indices.contains(cursorLine) else {
            return (lines, cursorLine, cursorCol)
        }

        var mutableLines = lines
        let line = lines[cursorLine]
        let (_, startCol, endCol) = currentWord(in: line, col: cursorCol)
        let leftIndex = line.index(line.startIndex, offsetBy: startCol)
        let rightIndex = line.index(line.startIndex, offsetBy: endCol)

        let behavior = completer.insertionBehavior(lines: lines, row: cursorLine, col: cursorCol, selected: item.value)
        var insertion = item.value
        var newCursorCol = startCol + item.value.count
        if behavior.addInputObjectBraces {
            insertion += ": { }"
            newCursorCol = startCol + item.value.count + 3
        } else if behavior.addSelectionBraces {
            insertion += " { }"
            newCursorCol = startCol + item.value.count + 3
        }

        var newLine = line
        newLine.replaceSubrange(leftIndex..<rightIndex, with: insertion)
        mutableLines[cursorLine] = newLine
        return (mutableLines, cursorLine, newCursorCol)
    }

    func forceFileSuggestions(lines _: [String], cursorLine _: Int, cursorCol _: Int) -> AutocompleteSuggestion? {
        nil
    }

    func shouldTriggerFileCompletion(lines _: [String], cursorLine _: Int, cursorCol _: Int) -> Bool {
        false
    }

    private func currentWord(in line: String, col: Int) -> (String, Int, Int) {
        if line.isEmpty { return ("", col, col) }
        let chars = Array(line)
        let count = chars.count
        var left = max(0, min(col, count))
        var right = left
        func isIdentifier(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        while left > 0, isIdentifier(chars[left - 1]) { left -= 1 }
        while right < count, isIdentifier(chars[right]) { right += 1 }
        let prefix = left < right ? String(chars[left..<right]) : ""
        return (prefix, left, right)
    }
}

private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

private final class WeakBox<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
    init(_ value: T) { self.value = value }
}
