// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

//! Here is the logic and main loop for the fullscreen front end
//! This front end uses a full alternate buffer

const std = @import("std");
const chess = @import("../hellochess.zig");
const zcon = @import("zcon");

const Frontend = @import("Frontend.zig");

/// characters high the rendering area is
const render_height = 20;
/// characters wide the rendering area is
const render_width = 128;
const file_line = "#dgry   a b c d e f g h \n";

frontend: Frontend,

/// runs the inline frontend
pub fn run(this: *@This(), writer: *zcon.Writer) !void {
    writer.put("\n#wht ============= Hello Chess =============\n#dgry /exit to exit, /help for more commands#prv#prv\n");
    writer.indent(1);

    primeBuffer(writer);
    writer.saveCursor();

    while (true) {
        writer.restoreCursor();
        writer.put("\n");
        try this.renderBoard(writer);

        // status line
        writer.clearLine();
        writer.fmt(" #dgry {s}#def : {s}\n\n", .{ this.frontend.getLastInput(), this.frontend.status });
        writer.useDefaultColors();

        try this.frontend.doTurn(writer);

        if (this.frontend.should_exit)
            break;
    }
    writer.put("\n");
}

/// write spaces to the area we will be rendering to
/// this is important to keep the board rendering in place
/// (without scrolling) on smaller buffers
fn primeBuffer(writer: *zcon.Writer) void {
    var i: i32 = 0;
    while (i < render_height) : (i += 1)
        writer.fmt("{s: <[w]}\n", .{ .s = " ", .w = render_width });
    writer.setCursorX(1);
    writer.cursorUp(render_height);
}

/// writes the chess board to the buffer
fn renderBoard(this: @This(), writer: *zcon.Writer) !void {
    const white_material = this.frontend.board.countMaterial(.white);
    const black_material = this.frontend.board.countMaterial(.black);
    const black_advantage = black_material - white_material;
    const white_advantage = white_material - black_material;

    writer.clearLine();
    writer.put("#cyn");
    try this.frontend.board.writeCapturedPieces(writer, .white);
    if (black_advantage >= 0)
        writer.fmt("#dgry; +{}", .{black_advantage});
    writer.put("\n\n");

    writer.put(file_line);
    var pos = chess.Coordinate.init(0, 7); // a8
    while (pos.rank >= 0) : (pos.rank -= 1) {
        writer.fmt("#dgry {} ", .{pos.rank + 1});
        while (pos.file < 8) : (pos.file += 1) {
            if (this.frontend.board.at(pos)) |piece| {
                const piece_col = if (piece.affiliation() == .white)
                    "#cyn"
                else
                    "#yel";
                writer.fmt("{s}{u} ", .{ piece_col, piece.character() });
            } else writer.put("#dgry . ");
        }
        writer.fmt("#dgry {}\n", .{pos.rank + 1});
        pos.file = 0;
    }
    writer.put(file_line);
    writer.putChar('\n');

    writer.clearLine();
    writer.put("#yel");
    try this.frontend.board.writeCapturedPieces(writer, .black);
    if (white_advantage >= 0)
        writer.fmt("#dgry; +{}", .{white_advantage});
    writer.put("\n\n");

    writer.useDefaultColors();
}
