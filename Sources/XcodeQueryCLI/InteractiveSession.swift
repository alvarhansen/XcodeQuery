import Foundation
import XcodeQueryKit
import Darwin

final class InteractiveSession {
    private let core: XcodeProjectQuerySession
    private let debounceMs: Int
    private let colorEnabled: Bool

    init(core: XcodeProjectQuerySession, debounceMs: Int, colorEnabled: Bool) {
        self.core = core
        self.debounceMs = debounceMs
        self.colorEnabled = colorEnabled
    }

    // UI State (multiline)
    private var lines: [String] = [""]
    private var cursorRow: Int = 0
    private var cursorCol: Int = 0 // character offset within current line
    private var lastPreviewLines: Int = 0
    private var previewCache: String = ""
    private var lastWindowStart: Int = 0
    private var lastInputVisibleLines: Int = 1
    private let maxInputHeight: Int = 10
    // Completions
    private var suggestionsActive: Bool = false
    private var suggestions: [String] = []
    private var selectedSuggestion: Int = 0
    private let completer = CompletionProvider()
    private var evalTask: Task<Void, Never>? = nil
    private var revision: UInt64 = 0
    private let prompt = "> "

    // Terminal state
    private var origTerm = termios()

    @MainActor
    func start() async throws {
        try enterRawMode()
        defer { restoreTerminal() }
        render(initial: true, preview: hintText())

        var escSeq: [UInt8] = []
        while true {
            var ch: UInt8 = 0
            let n = read(STDIN_FILENO, &ch, 1)
            if n <= 0 { await Task.yield(); continue }

            if !escSeq.isEmpty || ch == 0x1B { // Escape or part of sequence
                if ch == 0x1B { escSeq = [0x1B]; continue }
                escSeq.append(ch)
                // Expect ESC [ <code>
                if escSeq.count == 2 && escSeq[1] != 0x5B { // not '[' -> treat as lone ESC
                    return // exit
                }
                if escSeq.count >= 3 {
                    let code = escSeq[2]
                    if code == 0x43 { // 'C' -> Right
                        if suggestionsActive { acceptCurrentSuggestion() } else { moveCursorRight() }
                    } else if code == 0x44 { // 'D' -> Left
                        moveCursorLeft()
                    } else if code == 0x41 { // Up
                        if suggestionsActive { moveSuggestionUp() } else { moveCursorUp() }
                    } else if code == 0x42 { // Down
                        if suggestionsActive { moveSuggestionDown() } else { moveCursorDown() }
                    } else {
                        // Unhandled escape sequence: ignore
                    }
                    escSeq.removeAll(keepingCapacity: true)
                    render()
                }
                continue
            }

            switch ch {
            case 3: // Ctrl+C
                return
            case 9: // Tab -> toggle/show completions
                handleTab()
            case 21: // Ctrl+U -> clear current line
                lines[cursorRow] = ""; cursorCol = 0; scheduleEval(); render(preview: hintText())
            case 127, 8: // Backspace
                handleBackspace()
            case 10, 13: // Enter
                if suggestionsActive { acceptCurrentSuggestion() } else { insertNewline(); scheduleEval(immediate: true); render() }
            default:
                if ch >= 32 { // printable
                    let scalar = UnicodeScalar(ch)
                    insertCharacter(Character(scalar))
                    scheduleEval(); render()
                    if suggestionsActive { refreshSuggestions() }
                }
            }
            await Task.yield()
        }
    }

    // MARK: - Debounced evaluation
    private func scheduleEval(immediate: Bool = false) {
        evalTask?.cancel()
        revision &+= 1
        let myRev = revision
        let current = lines.joined(separator: "\n")
        let delay = immediate ? 0 : debounceMs
        let coreBox = UncheckedSendable(self.core)
        let selfBox = WeakBox(self)
        evalTask = Task.detached {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
            }
            if Task.isCancelled { return }
            do {
                let any = try coreBox.value.evaluate(query: current)
                let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
                let data = try enc.encode(any)
                let text = String(data: data, encoding: .utf8) ?? ""
                if let strong = selfBox.value { await strong.renderIfLatest(preview: text, myRev: myRev) }
            } catch {
                if let strong = selfBox.value { await strong.renderErrorIfLatest(error, myRev: myRev) }
            }
        }
    }

    // MARK: - Rendering
    @MainActor
    private func render(initial: Bool = false, preview: String? = nil) {
        let out = FileHandle.standardOutput
        var s = ""

        // Move to preview start (above input line) and clear
        if !initial {
            s += "\r" // start of line
            // Move up to top of preview: preview lines + cursor row within previous window
            let prevRowInWindow = max(0, min(lastInputVisibleLines - 1, cursorRow - lastWindowStart))
            let up = lastPreviewLines + prevRowInWindow
            if up > 0 { s += "\u{001B}[\(up)A" }
            s += "\u{001B}[0J" // clear to end of screen
        }

        // Cache and write preview (CRLF to avoid raw-mode newline issues)
        if let p = preview { previewCache = p }
        let previewText = preview ?? previewCache
        let previewLines = previewText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in previewLines {
            s += "\r" + line + "\n"
        }

        // Suggestions panel (above input)
        var suggestionsLinesCount = 0
        if suggestionsActive && !suggestions.isEmpty {
            let maxShow = min(8, suggestions.count)
            s += "\r" + colorize("Suggestions:", color: .dim) + "\n"
            suggestionsLinesCount += 1
            for i in 0..<maxShow {
                let item = suggestions[i]
                if i == selectedSuggestion {
                    s += "\r" + colorize("› " + item, color: .cyan) + "\n"
                } else {
                    s += "\r" + "  " + item + "\n"
                }
                suggestionsLinesCount += 1
            }
        }

        // Compute input window
        let totalLines = lines.count
        let windowHeight = min(maxInputHeight, totalLines)
        let windowStart = max(0, min(totalLines - windowHeight, cursorRow - (windowHeight - 1)))
        let windowEnd = min(totalLines, windowStart + windowHeight)

        // Write input lines with prompt/indent
        for i in windowStart..<windowEnd {
            let prefix = (i == windowStart) ? prompt : "  "
            s += "\r" + prefix + lines[i] + "\n"
        }

        // Position cursor within the input window
        let rowInWindow = cursorRow - windowStart
        let linesUp = (windowEnd - windowStart) - rowInWindow
        if linesUp > 0 { s += "\u{001B}[\(linesUp)A" }
        s += "\r"
        let base = (rowInWindow == 0) ? prompt.count : 2
        let targetCol = base + cursorCol
        if targetCol > 0 { s += "\u{001B}[\(targetCol)C" }

        // Update last counters
        lastPreviewLines = max(1, previewLines.count + suggestionsLinesCount)
        lastWindowStart = windowStart
        lastInputVisibleLines = windowEnd - windowStart

        out.write(Data(s.utf8))
    }

    @MainActor
    private func hintText() -> String {
        colorize("Type a selection, e.g., targets { name }", color: .dim)
    }

    // MARK: - Cursor movement
    @MainActor private func moveCursorLeft() {
        if cursorCol > 0 {
            cursorCol -= 1
        } else if cursorRow > 0 {
            cursorRow -= 1
            cursorCol = lines[cursorRow].count
        }
    }
    @MainActor private func moveCursorRight() {
        let len = lines[cursorRow].count
        if cursorCol < len {
            cursorCol += 1
        } else if cursorRow + 1 < lines.count {
            cursorRow += 1
            cursorCol = 0
        }
    }
    @MainActor private func moveCursorUp() {
        if cursorRow > 0 {
            cursorRow -= 1
            cursorCol = min(cursorCol, lines[cursorRow].count)
        }
    }
    @MainActor private func moveCursorDown() {
        if cursorRow + 1 < lines.count {
            cursorRow += 1
            cursorCol = min(cursorCol, lines[cursorRow].count)
        }
    }

    // Editing helpers
    @MainActor private func insertCharacter(_ c: Character) {
        var line = lines[cursorRow]
        let idx = line.index(line.startIndex, offsetBy: cursorCol)
        line.insert(c, at: idx)
        lines[cursorRow] = line
        cursorCol += 1
    }
    @MainActor private func handleBackspace() {
        if cursorCol > 0 {
            var line = lines[cursorRow]
            let idx = line.index(line.startIndex, offsetBy: cursorCol - 1)
            line.remove(at: idx)
            lines[cursorRow] = line
            cursorCol -= 1
            scheduleEval(); render()
        } else if cursorRow > 0 {
            let prevLen = lines[cursorRow - 1].count
            lines[cursorRow - 1] += lines[cursorRow]
            lines.remove(at: cursorRow)
            cursorRow -= 1
            cursorCol = prevLen
            scheduleEval(); render()
        }
    }
    @MainActor private func insertNewline() {
        let line = lines[cursorRow]
        let splitIdx = line.index(line.startIndex, offsetBy: cursorCol)
        let left = String(line[..<splitIdx])
        let right = String(line[splitIdx...])
        lines[cursorRow] = left
        lines.insert(right, at: cursorRow + 1)
        cursorRow += 1
        cursorCol = 0
    }

    // Render helpers for async tasks
    @MainActor
    private func renderIfLatest(preview: String, myRev: UInt64) {
        if myRev == revision { render(preview: preview) }
    }
    @MainActor
    private func renderErrorIfLatest(_ error: any Error, myRev: UInt64) {
        if myRev != revision { return }
        let msg = String(describing: error)
        render(preview: colorize(msg, color: .red))
    }

    // MARK: - Terminal helpers
    private func enterRawMode() throws {
        if tcgetattr(STDIN_FILENO, &origTerm) != 0 { throw Errno.last }
        var raw = origTerm
        raw.c_lflag &= ~tcflag_t(ICANON | ECHO | IEXTEN | ISIG)
        raw.c_iflag &= ~tcflag_t(ICRNL)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_cc.16 /* VMIN */ = 0
        raw.c_cc.17 /* VTIME */ = 1
        if tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw) != 0 { throw Errno.last }
    }

    private func restoreTerminal() {
        _ = tcsetattr(STDIN_FILENO, TCSAFLUSH, &origTerm)
        // Move to new line to avoid prompt stuck at bottom
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    // MARK: - Color helper
    private enum AnsiColor { case red, dim, cyan }
    @MainActor
    private func colorize(_ s: String, color: AnsiColor) -> String {
        guard colorEnabled else { return s }
        let esc = "\u{001B}"
        let code: String
        switch color {
        case .red: code = "31"
        case .dim: code = "2"
        case .cyan: code = "36"
        }
        return "\(esc)[\(code)m\(s)\(esc)[0m"
    }

    // MARK: - Completions handling
    @MainActor private func handleTab() {
        if suggestionsActive {
            // Toggle off without accepting
            suggestionsActive = false
            render()
            return
        }
        refreshSuggestions()
        if suggestions.isEmpty { return }
        if suggestions.count == 1 {
            applySuggestion(suggestions[0])
            suggestionsActive = false
            render()
        } else {
            suggestionsActive = true
            selectedSuggestion = 0
            render()
        }
    }
    @MainActor private func refreshSuggestions() {
        if let s = completer.suggest(lines: lines, row: cursorRow, col: cursorCol) {
            suggestions = s.items
        } else {
            suggestions = []
            suggestionsActive = false
        }
    }
    @MainActor private func moveSuggestionUp() {
        guard suggestionsActive, !suggestions.isEmpty else { return }
        selectedSuggestion = (selectedSuggestion - 1 + suggestions.count) % suggestions.count
    }
    @MainActor private func moveSuggestionDown() {
        guard suggestionsActive, !suggestions.isEmpty else { return }
        selectedSuggestion = (selectedSuggestion + 1) % suggestions.count
    }
    @MainActor private func acceptCurrentSuggestion() {
        guard suggestionsActive, !suggestions.isEmpty else { return }
        applySuggestion(suggestions[selectedSuggestion])
        suggestionsActive = false
        render()
    }
    @MainActor private func applySuggestion(_ item: String) {
        // Replace current word (identifier) on current line with the suggestion
        let line = lines[cursorRow]
        let (prefix, startCol, endCol) = currentWord(in: line, col: cursorCol)
        let leftIdx = line.index(line.startIndex, offsetBy: startCol)
        let rightIdx = line.index(line.startIndex, offsetBy: endCol)
        var newLine = line
        newLine.replaceSubrange(leftIdx..<rightIdx, with: item)
        lines[cursorRow] = newLine
        cursorCol = startCol + item.count
        scheduleEval(); render()
    }
    @MainActor private func currentWord(in line: String, col: Int) -> (String, Int, Int) {
        if line.isEmpty { return ("", col, col) }
        let chars = Array(line)
        let n = chars.count
        var left = max(0, min(col, n))
        var right = left
        func isIdent(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        while left > 0 && isIdent(chars[left - 1]) { left -= 1 }
        while right < n && isIdent(chars[right]) { right += 1 }
        let prefix = left < right ? String(chars[left..<right]) : ""
        return (prefix, left, right)
    }
}

// MARK: - errno helper
private struct Errno: Swift.Error, CustomStringConvertible { let code: Int32
    static var last: Errno { Errno(code: errno) }
    var description: String { "errno \(code)" }
}

// Concurrency utility wrappers
private struct UncheckedSendable<T>: @unchecked Sendable { let value: T; init(_ v: T) { self.value = v } }
private final class WeakBox<T: AnyObject>: @unchecked Sendable { weak var value: T?; init(_ v: T) { self.value = v } }
