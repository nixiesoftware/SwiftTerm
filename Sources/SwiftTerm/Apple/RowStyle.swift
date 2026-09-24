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
    /// The foreground for cells the program left in the default colour.
    /// Cells with a colour of their own keep it.
    public var foreground: Attribute.Color?

    public init(bold: Bool = false, faint: Bool = false, foreground: Attribute.Color? = nil) {
        self.bold = bold
        self.faint = faint
        self.foreground = foreground
    }

    /// The attribute as this style redraws it.
    func apply(to attribute: Attribute) -> Attribute {
        var style = attribute.style
        if bold { style.insert(.bold) }
        if faint { style.insert(.dim) }
        var fg = attribute.fg
        if let foreground, fg == .defaultColor {
            fg = foreground
        }
        return Attribute(fg: fg, bg: attribute.bg, style: style,
                         underlineStyle: attribute.underlineStyle,
                         underlineColor: attribute.underlineColor)
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

    public init(prompt: TerminalCellStyle? = nil, input: TerminalCellStyle? = nil,
                output: TerminalCellStyle? = nil, other: TerminalCellStyle? = nil) {
        self.prompt = prompt
        self.input = input
        self.output = output
        self.other = other
    }

    /// The style for a cell of the given role, if this row sets one.
    func style(for content: SemanticContent) -> TerminalCellStyle? {
        switch content {
        case .prompt: return prompt
        case .input: return input
        case .output: return output
        case .none: return other
        }
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
