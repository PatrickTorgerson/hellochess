// ********************************************************************************
//! https://github.com/PatrickTorgerson/chess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const console = @import("console.zig");
const chess = @import("chess.zig");


pub fn main() !void {

    const dark_col = console.Color {.r = 121, .g = 76, .b = 39};
    const light_col = console.Color {.r = 181, .g = 136, .b = 99};
    const black_col = console.Color {.r = 0, .g = 0, .b = 0};
    const white_col = console.Color {.r = 255, .g = 255, .b = 255};
    const coord_col = console.Color {.r = 80, .g = 56, .b = 40};

    std.debug.print(" == Hello Chess ==\n\n", .{});

    var board = chess.Board.init();
    var turn_affiliation = chess.Piece.Affiliation.white;
    var prompt: []const u8 = "white to move";
    var status: []const u8 = "Let's play some chess";
    console.set_home();

    while (true) {
        console.home();

        var pos = chess.Coordinate.init(0,7);
        console.put(coord_col, white_col, "   a b c d e f g h \x1b[0m\n", .{});
        while (pos.rank >= 0) : (pos.rank -= 1) {

            console.put(coord_col, white_col, " {} ", .{pos.rank + 1});
            while (pos.file < 8) : (pos.file += 1) {
                const square_col = if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                    dark_col else light_col;
                if (board.at(pos)) |piece| {
                    const piece_col = //if (piece.affiliation() == .white)
                        black_col; // white_col else black_col;
                    console.put(square_col, piece_col, "{s} ", .{piece.symbol()});
                }
                else console.put(square_col, square_col, "  ", .{});
            }
            std.debug.print("\n", .{});
            pos.file = 0;

        }
        console.put(coord_col, white_col, "   a b c d e f g h \x1b[0m\n", .{});

        // status line
        console.clear_line();
        console.print(" {s}\n\n", .{status});

        // prompt
        console.clear_line();
        console.print(" > {s}: ", .{prompt});

        var buffer: [200]u8 = undefined;
        const count = try std.io.getStdIn().read(&buffer)-2;

        if (std.mem.eql(u8, buffer[0..count], "exit")) {
            break;
        }

        status = @tagName(board.submit_move(turn_affiliation, buffer[0..count]));

        turn_affiliation = if (turn_affiliation == .white)
            .black else .white;

        prompt = if (turn_affiliation == .white)
            "white to move" else "black to move";
    }

}
