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
const ascii = @import("../hellochess/piece_ascii.zig");

const Frontend = @import("Frontend.zig");

frontend: Frontend,

// const col_light_square = zcon.Color.rgb(240, 217, 181);
// const col_dark_square = zcon.Color.rgb(181, 136, 99);

const col_light_square = zcon.Color.rgb(137, 137, 137);
const col_dark_square = zcon.Color.rgb(117, 117, 117);
const col_light_piece = zcon.Color.rgb(255, 255, 255);
const col_dark_piece = zcon.Color.rgb(0, 0, 0);

const square_width = 10;
const square_height = 5;

pub fn run(this: *@This(), writer: *zcon.Writer) !void {
    writer.useDedicatedScreen();
    defer writer.useDefaultScreen();

    while (true) {
        try this.drawBoard(writer);

        // status line
        writer.clearLine();
        writer.fmt(" #dgry {s}#def : {s}\n\n", .{ this.frontend.getLastInput(), this.frontend.status });
        writer.useDefaultColors();

        if (try this.frontend.prompt(writer))
            break;
    }
}

pub fn drawBoard(this: @This(), writer: *zcon.Writer) !void {
    var pos = chess.Coordinate.init(0, 7); // a8
    while (pos.rank >= 0) : (pos.rank -= 1) {
        while (pos.file < 8) : (pos.file += 1) {
            writer.setBackground(
                if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                    col_dark_square
                else
                    col_light_square,
            );
            writer.setForeground(
                if (try std.math.absInt(@mod(pos.rank, 2) - @mod(pos.file, 2)) == 0)
                    col_light_square
                else
                    col_dark_square,
            );

            writer.drawAt(
                .{
                    .x = square_width * pos.file + 4,
                    .y = square_height * (7 - pos.rank) + 2,
                },
                "{s}",
                .{ascii.empty},
            );
            writer.fmt("{s}", .{pos.to_String()});

            if (this.frontend.board.at(pos)) |piece| {
                writer.setForeground(
                    if (piece.affiliation() == .white)
                        col_light_piece
                    else
                        col_dark_piece,
                );
                writer.drawAt(
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
    writer.useDefaultColors();
    writer.putRaw("\n\n");
}
