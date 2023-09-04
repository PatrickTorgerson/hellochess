// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

const Piece = @import("Piece.zig");
const Coordinate = @import("Coordinate.zig");
const Meta = @import("Meta.zig");
const Bitfield = @import("util.zig").Bitfield;

pub const Flag = enum(u4) {
    none = 0,

    // NOTE: values are significant
    // see `@import("movegen.zig").MoveIterator.nextPawn`
    promote_queen = 1,
    promote_rook = 2,
    promote_bishop = 3,
    promote_knight = 4,

    enpassant_capture,
    pawn_double_push,
    castle,
};

const Move = @This();

/// to preserve memory during search, moves are stored as 16 bit numbers
/// The format is as follows:
/// bit 0-5: source square (0 to 63)
/// bit 6-11: dest square (0 to 63)
/// bit 12-15: move flag
bits: Bitfield(u16),

const offset_source = 0;
const offset_dest = 6;
const offset_flag = 12;

pub fn init(source_: Coordinate, dest_: Coordinate, flag_: Flag) Move {
    var this = Move{ .bits = .{} };
    this.bits.set(u6, offset_source, @as(u6, @intCast(source_.value)));
    this.bits.set(u6, offset_dest, @as(u6, @intCast(dest_.value)));
    this.bits.set(u4, offset_flag, @intFromEnum(flag_));
    return this;
}

pub fn setFlag(move: *Move, flag_: Flag) void {
    move.bits.set(u4, offset_flag, @intFromEnum(flag_));
}

/// return source coordinate
pub fn source(move: Move) Coordinate {
    return Coordinate.from1d(@intCast(move.bits.get(u6, offset_source)));
}

/// return destination coordinate
pub fn dest(move: Move) Coordinate {
    return Coordinate.from1d(@intCast(move.bits.get(u6, offset_dest)));
}

/// return move flag, possible values:
///   - none, just a normal move
///   - promote_queen, pawn promotion to queen
///   - promote_rook, pawn promotion to rook
///   - promote_bishop, pawn promotion to bishop
///   - promote_knight, pawn promotion to knight
///   - enpassant_capture, pawn capture en passant
///   - castle, castling, direction is determined by dest coord
///   - pawn_double_push, pawn double push on first move
pub fn flag(move: Move) Flag {
    return @enumFromInt(move.bits.get(u4, offset_flag));
}

/// if move represents a pawn promotion, return
/// the class to promote to, otherwise return null
pub fn promotion(move: Move) ?Piece.Class {
    return switch (move.flag()) {
        .promote_queen => .queen,
        .promote_rook => .rook,
        .promote_bishop => .bishop,
        .promote_knight => .knight,
        .none, .enpassant_capture, .castle, .pawn_double_push => null,
    };
}

pub fn format(value: Move, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
    _ = options;
    _ = fmt;
    try writer.print("{s}{s}\x1b[90m({s})\x1b[0m", .{
        value.source().toString(),
        value.dest().toString(),
        @tagName(value.flag()),
    });
}

pub const invalid = Move.init(Coordinate.a4, Coordinate.h5, .promote_knight);

/// result of attmpting a move
pub const Result = struct {
    move: Move = Move.invalid,
    /// position's meta before this move was played
    prev_meta: Meta,
    tag: Tag,

    pub const Tag = enum {
        ok,
        ok_check,
        ok_mate,
        ok_stalemate,
        ok_repitition,
        ok_insufficient_material,
        ok_fifty_move_rule,
        ok_en_passant,

        bad_notation,
        bad_disambiguation,
        ambiguous_piece,
        no_such_piece,
        no_visibility,
        in_check,
        enters_check,
        blocked,

        bad_castle_in_check,
        bad_castle_through_check,
        bad_castle_king_or_rook_moved,
    };
};
