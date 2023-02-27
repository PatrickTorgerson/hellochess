// ********************************************************************************
//* https://github.com/PatrickTorgerson/hellochess
//* Copyright (c) 2022 Patrick Torgerson
//* MIT license, see LICENSE for more information
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
const render_width = 64;
const file_line = "#dgry   a b c d e f g h \n";

frontend: Frontend,

/// runs the inline frontend
pub fn run(this: *@This()) !void {
    prime_buffer();
    zcon.save_cursor();

    while (true) {
        zcon.restore_cursor();
        try this.render_board();

        // status line
        zcon.clear_line();
        zcon.print(" #dgry {s}#def : {s}\n\n", .{ this.frontend.get_last_input(), this.frontend.status });
        zcon.set_color(.default);

        if (try this.frontend.prompt())
            break;
    }
}

/// write spaces to the area we will be rendering to
/// this is important to keep the board rendering in place
/// (without scrolling) on smaller buffers
fn prime_buffer() void {
    var i: i32 = 0;
    while (i < render_height) : (i += 1)
        zcon.print("{s: <[w]}\n", .{ .s = " ", .w = render_width });
    zcon.set_cursor_x(1);
    zcon.cursor_up(render_height);
}

/// writes the chess board to the buffer
fn render_board(this: @This()) !void {
    zcon.write(file_line);
    var pos = chess.Coordinate.init(0, 7); // a8
    while (pos.rank >= 0) : (pos.rank -= 1) {
        zcon.print("#dgry {} ", .{pos.rank + 1});
        while (pos.file < 8) : (pos.file += 1) {
            if (this.frontend.board.at(pos)) |piece| {
                const piece_col = if (piece.affiliation() == .white)
                    "#cyn"
                else
                    "#yel";
                zcon.print("{s}{u} ", .{ piece_col, piece.character() });
            } else zcon.write("#dgry . ");
        }
        zcon.print("#dgry {}\n", .{pos.rank + 1});
        pos.file = 0;
    }
    zcon.write(file_line);
    zcon.write("\n");
    zcon.set_color(.default);
}
