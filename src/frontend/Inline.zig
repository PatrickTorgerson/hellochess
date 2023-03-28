// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! Here is the logic and main loop for the inline front end
//!

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
    const white_material = this.frontend.position.countMaterial(.white);
    const black_material = this.frontend.position.countMaterial(.black);
    const black_advantage = black_material - white_material;
    const white_advantage = white_material - black_material;

    writer.clearLine();
    writer.put("#cyn");
    try this.frontend.position.writeCapturedPieces(writer, .white);
    if (black_advantage >= 0)
        writer.fmt("#dgry; +{}", .{black_advantage});
    writer.put("\n\n");

    writer.put(file_line);
    var rankv: i8 = 7; // Rank 8
    while (rankv >= 0) : (rankv -= 1) {
        writer.fmt("#dgry {} ", .{rankv + 1});
        var file_iter = chess.File.file_a.iterator();
        while (file_iter.next()) |file| {
            const coord = chess.Coordinate.from2d(file, chess.Rank.init(rankv));
            const piece = this.frontend.position.at(coord);
            if (!piece.isEmpty()) {
                const piece_col = if (piece.affiliation().? == .white)
                    "#cyn"
                else
                    "#yel";
                writer.fmt("{s}{u} ", .{ piece_col, piece.character() });
            } else writer.put("#dgry . ");
        }
        writer.fmt("#dgry {}\n", .{rankv + 1});
    }
    writer.put(file_line);
    writer.putChar('\n');

    writer.clearLine();
    writer.put("#yel");
    try this.frontend.position.writeCapturedPieces(writer, .black);
    if (white_advantage >= 0)
        writer.fmt("#dgry; +{}", .{white_advantage});
    writer.put("\n\n");

    writer.useDefaultColors();
}
