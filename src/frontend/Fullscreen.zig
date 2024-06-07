// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! Here is the logic and main loop for the fullscreen front end
//! This front end uses a full alternate buffer
//!

const std = @import("std");
const chess = @import("../hellochess.zig");
const zcon = @import("zcon");
const ascii = @import("../hellochess/piece_ascii.zig");

const Frontend = @import("Frontend.zig");

frontend: Frontend,

const col_light_square = zcon.Color.rgb(137, 137, 137);
const col_dark_square = zcon.Color.rgb(117, 117, 117);
const col_light_piece = zcon.Color.rgb(255, 255, 255);
const col_dark_piece = zcon.Color.rgb(0, 0, 0);

const square_width = 10;
const square_height = 5;

pub fn run(this: *@This(), writer: *zcon.Writer) !void {
    defer this.frontend.deinit();

    writer.useDedicatedScreen();
    defer writer.useDefaultScreen();

    while (true) {
        try this.drawBoard(writer);
        writer.setCursor(.{ .x = 1, .y = 44 });

        // status line
        writer.clearLine();
        writer.fmt(" #dgry {s}#def : {s}\n\n", .{ this.frontend.getLastInput(), this.frontend.status });
        writer.useDefaultColors();

        try this.frontend.doTurn(writer);

        if (this.frontend.should_exit)
            break;
    }
}

pub fn drawBoard(this: @This(), writer: *zcon.Writer) !void {
    var rank_iter = chess.Rank.rank_1.iterator();
    while (rank_iter.next()) |rank| {
        var file_iter = chess.File.file_a.iterator();
        while (file_iter.next()) |file| {
            writer.setBackground(
                if (@abs(@mod(rank.val(), 2) - @mod(file.val(), 2)) == 0)
                    col_dark_square
                else
                    col_light_square,
            );
            writer.setForeground(
                if (@abs(@mod(rank.val(), 2) - @mod(file.val(), 2)) == 0)
                    col_light_square
                else
                    col_dark_square,
            );
            writer.drawAt(.{
                .x = square_width * file.val() + 4,
                .y = square_height * (7 - rank.val()) + 2,
            }, "{s}", .{ascii.empty});
            writer.fmt("{s}", .{chess.Coordinate.from2d(file, rank).toString()});

            const piece = this.frontend.position.at(chess.Coordinate.from2d(file, rank));
            if (!piece.isEmpty()) {
                writer.setForeground(
                    if (piece.affiliation().? == .white)
                        col_light_piece
                    else
                        col_dark_piece,
                );
                writer.drawAt(.{
                    .x = square_width * file.val() + 4,
                    .y = square_height * (7 - rank.val()) + 2,
                }, "{s}", .{piece.ascii()});
            }
        }
    }
    writer.useDefaultColors();
    writer.putRaw("\n\n");
}
