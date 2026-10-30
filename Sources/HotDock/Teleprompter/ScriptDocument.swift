import Foundation

/// A paragraph-sized unit of rendering. One source line each, so wrapping happens naturally
/// within a line and blank lines survive as breathing space.
struct ScriptBlock: Identifiable, Equatable {
    let id: Int
    let text: String
    /// 1...6 for a Markdown heading, 0 for body text.
    let headingLevel: Int

    var isBlank: Bool { text.isEmpty }
    var isHeading: Bool { headingLevel > 0 }
}

/// A heading used as a jump target.
struct ScriptSection: Identifiable, Equatable {
    let id: Int          // matches the id of the block that starts it
    let title: String
    let level: Int
    let blockIndex: Int
}

/// Plain text, or Markdown-style headings used as section markers. Nothing else is
/// interpreted: a script with no `#` lines is simply one long section, which is what you want
/// when you paste something in from elsewhere.
struct ScriptDocument: Equatable {
    let rawText: String
    let blocks: [ScriptBlock]
    let sections: [ScriptSection]

    init(text: String) {
        rawText = text
        var blocks: [ScriptBlock] = []
        var sections: [ScriptSection] = []

        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let (level, body) = Self.parseHeading(line)
            blocks.append(ScriptBlock(id: index, text: body, headingLevel: level))
            if level > 0 {
                sections.append(ScriptSection(id: index, title: body, level: level,
                                              blockIndex: blocks.count - 1))
            }
        }

        self.blocks = blocks
        self.sections = sections
    }

    /// Returns (level, text-without-hashes) for a Markdown heading, or (0, line) otherwise.
    /// Requires whitespace after the hashes so a line like "#1 priority" stays body text.
    private static func parseHeading(_ line: String) -> (Int, String) {
        guard line.hasPrefix("#") else { return (0, line) }
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard let next = rest.first, next == " " || next == "\t" else { return (0, line) }
        return (level, rest.trimmingCharacters(in: .whitespaces))
    }

    var isEmpty: Bool { rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Shown until script storage lands, so there is always something to scroll.
    static let sample = ScriptDocument(text: """
        # Welcome to HotDock

        This is your teleprompter. The text scrolls on its own, and
        hovering the cursor over this panel pauses it so you can catch up.

        # Adjusting as you go

        Speed, font size and width are all live settings. From Step 3
        onwards you will be able to change them without touching the mouse.

        # Markdown headings are section markers

        Any line starting with a hash becomes a jump target, so you can
        skip to the next part of your script with one keystroke.

        Plain text works too. If a script has no headings at all it is
        simply treated as one long section, which is what you want when
        you paste something in from somewhere else.

        # That is the whole idea

        Read from just below the camera, keep your eyes up, and let the
        words come to you.
        """)
}
