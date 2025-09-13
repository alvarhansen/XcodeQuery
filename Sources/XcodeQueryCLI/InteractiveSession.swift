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

    // UI State
    private var buffer: String = ""
    private var cursor: Int = 0 // index in buffer (characters count)
    private var lastPreviewLines: Int = 0
    private var previewCache: String = ""
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
                        moveCursorRight()
                    } else if code == 0x44 { // 'D' -> Left
                        moveCursorLeft()
                    } else if code == 0x41 || code == 0x42 {
                        // Up/Down ignored in single-line mode
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
            case 21: // Ctrl+U -> clear line
                buffer.removeAll(); cursor = 0; scheduleEval(); render(preview: hintText())
            case 127, 8: // Backspace
                if cursor > 0 {
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursor - 1)
                    buffer.remove(at: idx)
                    cursor -= 1
                    scheduleEval(); render()
                }
            case 10, 13: // Enter
                // Trigger immediate evaluation (no newline in single-line mode)
                scheduleEval(immediate: true)
            default:
                if ch >= 32 { // printable
                    let scalar = UnicodeScalar(ch)
                    let c = Character(scalar)
                    let idx = buffer.index(buffer.startIndex, offsetBy: cursor)
                    buffer.insert(c, at: idx)
                    cursor += 1
                    scheduleEval(); render()
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
        let current = buffer
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
            if lastPreviewLines > 0 { s += "\u{001B}[\(lastPreviewLines)A" }
            s += "\u{001B}[0J" // clear to end of screen
        }

        // Cache and write preview (CRLF to avoid raw-mode newline issues)
        if let p = preview { previewCache = p }
        let previewText = preview ?? previewCache
        let lines = previewText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        for line in lines {
            s += "\r" + line + "\n"
        }

        // Write prompt + buffer
        s += "\r" + prompt + buffer
        // Position cursor
        let endPos = prompt.count + buffer.count
        let targetPos = prompt.count + cursor
        if endPos > targetPos { s += "\u{001B}[\(endPos - targetPos)D" }

        // Update lastPreviewLines
        lastPreviewLines = max(1, lines.count)

        out.write(Data(s.utf8))
    }

    @MainActor
    private func hintText() -> String {
        colorize("Type a selection, e.g., targets { name }", color: .dim)
    }

    // MARK: - Cursor movement
    @MainActor private func moveCursorLeft() { if cursor > 0 { cursor -= 1 } }
    @MainActor private func moveCursorRight() { if cursor < buffer.count { cursor += 1 } }

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
    private enum AnsiColor { case red, dim }
    @MainActor
    private func colorize(_ s: String, color: AnsiColor) -> String {
        guard colorEnabled else { return s }
        let esc = "\u{001B}"
        let code: String
        switch color {
        case .red: code = "31"
        case .dim: code = "2"
        }
        return "\(esc)[\(code)m\(s)\(esc)[0m"
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
