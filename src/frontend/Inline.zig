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
const render_height = 25;
/// characters wide the rendering area is
const render_width = 128;
const col_white = zcon.Color.col16(.bright_yellow);
const col_black = zcon.Color.col16(.bright_cyan);
const col_light_sq = zcon.Color.col16(.yellow);
const col_dark_sq = zcon.Color.col16(.cyan);

frontend: Frontend,

/// runs the inline frontend
pub fn run(this: *@This(), writer: *zcon.Writer) !void {
    defer this.frontend.deinit();

    writer.put("\n#wht ================ Hello Chess ================\n   #dgry /exit to exit, /help for more commands#prv#prv\n");
    writer.indent(1);

    // set color used for move prompts
    this.frontend.col_white = col_white;
    this.frontend.col_black = col_black;

    primeBuffer(writer, render_height);
    writer.saveCursor();

    while (true) {
        writer.restoreCursor();
        writer.put("\n");
        try this.renderBoard(writer);
        primeBuffer(writer, render_height - 20);
        this.frontend.printStatus(writer);
        try this.frontend.doTurn(writer);
        if (this.frontend.should_exit)
            break;
        writer.restoreCursor();
        writer.setCursorX(28);
        writer.cursorDown(2);
        this.frontend.printHistory(writer, 12);
        writer.flush();
    }
    writer.put("\n");
}

/// write spaces to the area we will be rendering to
/// this is important to keep the board rendering in place
/// (without scrolling) on smaller buffers
fn primeBuffer(writer: *zcon.Writer, count: i16) void {
    var i: i32 = 0;
    while (i < count) : (i += 1) {
        writer.clearLine();
        writer.put("\n");
    }
    writer.cursorUp(count);
}

/// writes the chess board to the buffer
fn renderBoard(this: @This(), writer: *zcon.Writer) !void {
    const white_material = this.frontend.position.countMaterial(.white);
    const black_material = this.frontend.position.countMaterial(.black);
    const black_advantage = black_material - white_material;
    const white_advantage = white_material - black_material;

    this.drawCaptured(writer, this.frontend.player_affiliation.opponent(), black_advantage);
    this.drawFileLine(writer);

    var rank_iter = this.frontend.rankIterator();
    while (rank_iter.next()) |rank| {
        writer.fmt("#dgry {} ", .{rank.val() + 1});
        var file_iter = this.frontend.fileIterator();
        while (file_iter.next()) |file| {
            const coord = chess.Coordinate.from2d(file, rank);
            const piece = this.frontend.position.at(coord);
            if (!piece.isEmpty()) {
                setAffiliatedColor(writer, piece.affiliation().?);
                writer.fmt("#b{u}#b:off; ", .{piece.character()});
                writer.usePreviousColor();
            } else {
                setSquareColor(writer, file, rank);
                writer.put("#d:*; ");
                writer.useDefaultColors();
            }
        }
        writer.fmt("#dgry {}", .{rank.val() + 1});
        writer.cursorDown(1);
        writer.cursorLeft(19);
    }

    this.drawFileLine(writer);
    writer.putChar('\n');
    this.drawCaptured(writer, this.frontend.player_affiliation, white_advantage);
    writer.useDefaultColors();
}

/// draw file letters on board edges
fn drawFileLine(this: @This(), writer: *zcon.Writer) void {
    writer.put("#dgry;  ");
    var file_iter = this.frontend.fileIterator();
    while (file_iter.next()) |file| {
        writer.fmt("{c} ", .{'a' + @intCast(u8, file.val())});
    }
    writer.put("\n");
}

/// draw the line of captured pieces and points of material
/// for `affiliation`
fn drawCaptured(this: @This(), writer: *zcon.Writer, affiliation: chess.Affiliation, material_advantage: i32) void {
    writer.clearLine();
    setAffiliatedColor(writer, affiliation.opponent());
    this.frontend.position.writeCapturedPieces(writer, affiliation.opponent()) catch {};
    if (material_advantage >= 0)
        writer.fmt("#dgry; +{}#prv", .{material_advantage});
    writer.put("\n\n");
    writer.usePreviousColor();
}

fn setAffiliatedColor(writer: *zcon.Writer, affiliation: chess.Affiliation) void {
    writer.setForeground(switch (affiliation) {
        .white => col_white,
        .black => col_black,
    });
}

fn setSquareColor(writer: *zcon.Writer, file: chess.Coordinate.File, rank: chess.Coordinate.Rank) void {
    if (@rem(file.val() + rank.val(), 2) != 0)
        writer.setForeground(col_light_sq)
    else
        writer.setForeground(col_dark_sq);
}
