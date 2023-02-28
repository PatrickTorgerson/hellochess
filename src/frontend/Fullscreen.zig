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
const ascii = @import("../hellochess/piece_ascii.zig");

const Frontend = @import("Frontend.zig");

frontend: Frontend,

const col_light_square = zcon.Color.background(.cyan, .dim, .normal);
const col_dark_square = zcon.Color.background(.black, .bright, .normal);
const col_light_square_label = zcon.Color.foreground(.black, .bright, .normal);
const col_dark_square_label = zcon.Color.foreground(.cyan, .dim, .normal);
const col_light_piece = zcon.Color.foreground(.white, .bright, .normal);
const col_dark_piece = zcon.Color.foreground(.black, .dim, .normal);

const square_width = 10;
const square_height = 5;

pub fn run(this: *@This()) !void {
    zcon.alternate_buffer();
    defer zcon.main_buffer();

    while (true) {
        var pos = chess.Coordinate.init(0, 7); // a8
        while (pos.rank >= 0) : (pos.rank -= 1) {
            while (pos.file < 8) : (pos.file += 1) {
                zcon.set_color(
                    if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                        col_dark_square
                    else
                        col_light_square,
                );
                zcon.set_color(
                    if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                        col_dark_square_label
                    else
                        col_light_square_label,
                );

                zcon.draw(
                    .{
                        .x = square_width * pos.file + 4,
                        .y = square_height * (7 - pos.rank) + 2,
                    },
                    "{s}",
                    .{ascii.empty},
                );
                zcon.print("{s}", .{pos.to_String()});

                if (this.frontend.board.at(pos)) |piece| {
                    zcon.set_color(
                        if (piece.affiliation() == .white)
                            col_light_piece
                        else
                            col_dark_piece,
                    );
                    zcon.draw(
                        .{
                            .x = square_width * pos.file + 4,
                            .y = square_height * (7 - pos.rank) + 2,
                        },
                        "{s}",
                        .{piece.ascii()},
                    );
                }
            }
            pos.file = 0;
        }
        zcon.set_color(.default);
        zcon.write("\n\n");

        // status line
        zcon.clear_line();
        zcon.print(" #dgry {s}#def : {s}\n\n", .{ this.frontend.get_last_input(), this.frontend.status });
        zcon.set_color(.default);

        if (try this.frontend.prompt())
            break;
    }
}
