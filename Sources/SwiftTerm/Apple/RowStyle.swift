//
//  RowStyle.swift
//  SwiftTerm
//
//  A style the host lays over one buffer row, on top of what the program
//  wrote. It exists for hosts that draw a shell as a page rather than a
//  grid: the row a command was typed on set in bold, the rows it printed
//  set in a quieter ink, an old prompt faded once its block is done. The
//  program's own colours are kept where it chose them; only the default
//  foreground is replaced.
//

import Foundation

/// How a run of cells is redrawn by a ``TerminalRowStyle``.
public struct TerminalCellStyle: Equatable, Hashable, Sendable {
    /// Draw in the bold face.
    public var bold: Bool
    /// Dim towards the background, as SGR 2 would.
    public var faint: Bool
    /// Underline, as SGR 4 would.
    public var underline: Bool
    /// The foreground for cells the program left in the default colour,
    /// or for every cell when ``overridesProgramColors`` is set.
    public var foreground: Attribute.Color?
    /// The background, on the same terms as ``foreground``.
    public var background: Attribute.Color?
    /// Replace the program's own colours too, not only the defaults.
    public var overridesProgramColors: Bool

    public init(bold: Bool = false, faint: Bool = false, underline: Bool = false,
                foreground: Attribute.Color? = nil, background: Attribute.Color? = nil,
                overridesProgramColors: Bool = false) {
        self.bold = bold
        self.faint = faint
        self.underline = underline
        self.foreground = foreground
        self.background = background
        self.overridesProgramColors = overridesProgramColors
    }

    /// The attribute as this style redraws it.
    func apply(to attribute: Attribute) -> Attribute {
        var style = attribute.style
        if bold { style.insert(.bold) }
        if faint { style.insert(.dim) }
        if underline { style.insert(.underline) }
        var fg = attribute.fg
        var bg = attribute.bg
        if let foreground, overridesProgramColors || fg == .defaultColor {
            fg = foreground
        }
        if let background, overridesProgramColors || bg == .defaultColor {
            bg = background
        }
        return Attribute(fg: fg, bg: bg, style: style,
                         underlineStyle: attribute.underlineStyle,
                         underlineColor: attribute.underlineColor)
    }
}

/// A style over a run of columns on one row. Spans win over the row's
/// role styles where they overlap.
public struct TerminalSpanStyle: Equatable, Hashable, Sendable {
    public var columns: Range<Int>
    public var style: TerminalCellStyle

    public init(columns: Range<Int>, style: TerminalCellStyle) {
        self.columns = columns
        self.style = style
    }
}

/// A style laid over one buffer row by the host, by the shell-declared role
/// of each cell: what a prompt wrote, what the person typed, what the
/// command printed, and cells with no role.
///
/// Roles come from OSC 133 marks and are attached to cells as they are
/// written, so a prompt and the command typed after it share a row and
/// still draw differently. Row styles are applied when a row is shaped for
/// drawing, on both the CoreGraphics and Metal paths, and never change the
/// terminal's buffer: a program that reads its screen back sees what it
/// wrote. Set them through ``TerminalView/rowStyles``, keyed by absolute
/// buffer row.
public struct TerminalRowStyle: Equatable, Hashable, Sendable {
    /// Cells a prompt wrote (after an OSC 133 `A`).
    public var prompt: TerminalCellStyle?
    /// Cells the person typed (after `B`).
    public var input: TerminalCellStyle?
    /// Cells a command printed (after `C` or `D`).
    public var output: TerminalCellStyle?
    /// Cells with no role.
    public var other: TerminalCellStyle?
    /// Styles over runs of columns, laid over the role styles. A host that
    /// recognises a path or a link in a row marks it here.
    public var spans: [TerminalSpanStyle]

    public init(prompt: TerminalCellStyle? = nil, input: TerminalCellStyle? = nil,
                output: TerminalCellStyle? = nil, other: TerminalCellStyle? = nil,
                spans: [TerminalSpanStyle] = []) {
        self.prompt = prompt
        self.input = input
        self.output = output
        self.other = other
        self.spans = spans
    }

    /// The style for a cell at `column` with the given role, if this row
    /// sets one: the span covering the column, else the role's.
    func style(for content: SemanticContent, column: Int) -> TerminalCellStyle? {
        for span in spans where span.columns.contains(column) {
            return span.style
        }
        switch content {
        case .prompt: return prompt
        case .input: return input
        case .output: return output
        case .none: return other
        }
    }
}

/// One cell of a page read, as a copied value.
public struct TerminalPageCell: Equatable, Sendable {
    /// The cell's character, or nil for the empty cell and the trailing
    /// half of a wide character.
    public let character: Character?
    /// Columns the character spans: 0 for the trailing half of a wide one.
    public let width: Int
    public let attribute: Attribute
    /// The shell-declared OSC 133 role.
    public let role: SemanticContent

    public init(character: Character?, width: Int, attribute: Attribute, role: SemanticContent) {
        self.character = character
        self.width = width
        self.attribute = attribute
        self.role = role
    }
}

/// One row of a page read.
public struct TerminalPageRow: Equatable, Sendable {
    /// The absolute buffer row.
    public let row: Int
    /// Whether this row continues the one above it.
    public let isWrapped: Bool
    /// One entry per column.
    public let cells: [TerminalPageCell]

    public init(row: Int, isWrapped: Bool, cells: [TerminalPageCell]) {
        self.row = row
        self.isWrapped = isWrapped
        self.cells = cells
    }

    /// The row's text, one character per column and a space where a cell
    /// is empty, so a column index into it is a column on the row.
    public var text: String {
        var text = ""
        for cell in cells where cell.width > 0 {
            text.append(cell.character ?? " ")
            if cell.width > 1 { text.append(contentsOf: String(repeating: " ", count: cell.width - 1)) }
        }
        return text
    }
}

/// A copied read of rows of the active buffer with each cell's character,
/// attribute and role: what a host post-processes the page from. See
/// ``TerminalView/pageSnapshot(rows:)``.
public struct TerminalPageSnapshot: Equatable, Sendable {
    /// The absolute row the screen's first row sits at.
    public let baseRow: Int
    /// The absolute row at the top of the viewport.
    public let viewportRow: Int
    /// Rows in the buffer, scrollback and screen together.
    public let rowCount: Int
    public let cols: Int
    /// The cursor, as an absolute row.
    public let cursor: Position
    /// Whether the alternate screen is showing.
    public let isAlternateScreen: Bool
    public let rows: [TerminalPageRow]

    public init(baseRow: Int, viewportRow: Int, rowCount: Int, cols: Int, cursor: Position,
                isAlternateScreen: Bool, rows: [TerminalPageRow]) {
        self.baseRow = baseRow
        self.viewportRow = viewportRow
        self.rowCount = rowCount
        self.cols = cols
        self.cursor = cursor
        self.isAlternateScreen = isAlternateScreen
        self.rows = rows
    }
}

/// The shell-declared role of the first cell of every row in the active
/// buffer, as a copied value: what a host needs to lay ``TerminalRowStyle``s
/// over a page without reaching the mutable terminal. Index a role by
/// absolute buffer row; the screen starts at ``baseRow``.
public struct TerminalSemanticRoles: Sendable, Equatable {
    /// The absolute row the screen's first row sits at.
    public let baseRow: Int
    /// One role per buffer row, scrollback first.
    public let roles: [SemanticContent]

    public init(baseRow: Int, roles: [SemanticContent]) {
        self.baseRow = baseRow
        self.roles = roles
    }
}
