// ********************************************************************************
//! https://github.com/PatrickTorgerson/chess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const chess = @import("chess.zig");
const zcon = @import("zcon");


pub fn main() !void {

    zcon.write(" == Hello Chess ==\n\n");

    var board = chess.Board.init();
    var turn_affiliation = chess.Piece.Affiliation.white;
    var prompt: []const u8 = "white to move";
    var status: []const u8 = "Let's play some chess";
    zcon.save_cursor();

    while (true) {
        zcon.restore_cursor();

        var pos = chess.Coordinate.init(0,7);
        zcon.write("#dgry   a b c d e f g h \n");
        while (pos.rank >= 0) : (pos.rank -= 1) {
            zcon.print("#dgry {} ", .{pos.rank + 1});
            while (pos.file < 8) : (pos.file += 1) {
                // const square_col = if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                //     dark_col else light_col;
                if (board.at(pos)) |piece| {
                    const piece_col = if (piece.affiliation() == .white)
                        "#cyn" else "#yel";
                    zcon.print("{s}{u} ", .{piece_col, piece.character()});
                }
                else zcon.write("#dgry . ");
            }
            zcon.print("#dgry {}\n", .{pos.rank + 1});
            pos.file = 0;

        }
        zcon.write("#dgry   a b c d e f g h #def \n\n");

        // status line
        zcon.clear_line();
        zcon.print(" {s}\n\n", .{status});

        // prompt
        zcon.clear_line();
        zcon.print(" > {s}: ", .{prompt});

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
