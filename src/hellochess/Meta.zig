// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! Stores information about a chess position other than
//! the piece locations. Such as castling rights, and
//! en passant files. this information is also used
//! to restore previous states when un making moves
//!

const std = @import("std");

const Piece = @import("Piece.zig");
const File = @import("Coordinate.zig").File;
const Bitfield = @import("util.zig").Bitfield;

const Affiliation = Piece.Affiliation;

const Meta = @This();

const InitialValues = struct {
    /// can white castle king side
    white_castle_king: bool = true,
    /// can white castle queen side
    white_castle_queen: bool = true,
    /// can black castle king side
    black_castle_king: bool = true,
    /// can black castle queen side
    black_castle_queen: bool = true,
    /// if last move was a double pawn push, stores file
    /// usefull for enpassant validation
    enpassant_file: ?File = null,
    /// piece captured last move
    /// useull for undoing captures
    captured_piece: Piece = Piece.empty(),
    /// half moves made since last capture or pawn move
    fifty_counter: u18 = 0,
};

/// all data is encoded into this 32 bit integer
/// bits 0-3: white and black kingside/queenside castling rights
/// bits 4-7: file of ep square (starting at 1, so 0 = no ep square)
/// bits 8-13: piece captured last move (for undoing captures)
/// bits 14-31: fifty move counter
bits: Bitfield(u32),

// bit offsets
const offset_whiteking = 0;
const offset_whitequeen = 1;
const offset_blackking = 2;
const offset_blackqueen = 3;
const offset_enpassant = 4;
const offset_capture = 8;
const offset_fifty = 14;

pub fn init(values: InitialValues) Meta {
    var this = Meta.initEmpty();
    this.setCastleKing(.white, values.white_castle_king);
    this.setCastleKing(.black, values.black_castle_king);
    this.setCastleQueen(.white, values.white_castle_queen);
    this.setCastleQueen(.black, values.black_castle_queen);
    this.setCapturedPiece(values.captured_piece);
    this.setFiftyCounter(values.fifty_counter);
    this.setEnpassantFile(values.enpassant_file);
    return this;
}

pub fn initEmpty() Meta {
    return .{ .bits = .{ .bits = 0 } };
}

pub fn castleKing(meta: Meta, affiliation: Affiliation) bool {
    return switch (affiliation) {
        .white => meta.bits.get(u1, offset_whiteking) == 1,
        .black => meta.bits.get(u1, offset_blackking) == 1,
    };
}

pub fn castleQueen(meta: Meta, affiliation: Affiliation) bool {
    return switch (affiliation) {
        .white => meta.bits.get(u1, offset_whitequeen) == 1,
        .black => meta.bits.get(u1, offset_blackqueen) == 1,
    };
}

pub fn castleKingBit(meta: Meta, affiliation: Affiliation) u1 {
    return switch (affiliation) {
        .white => meta.bits.get(u1, offset_whiteking),
        .black => meta.bits.get(u1, offset_blackking),
    };
}

pub fn castleQueenBit(meta: Meta, affiliation: Affiliation) u1 {
    return switch (affiliation) {
        .white => meta.bits.get(u1, offset_whitequeen),
        .black => meta.bits.get(u1, offset_blackqueen),
    };
}

pub fn enpassantFile(meta: Meta) ?File {
    const val = meta.bits.get(u4, offset_enpassant);
    return if (val == 0) null else @as(File, @enumFromInt(val - 1));
}

pub fn capturedPiece(meta: Meta) Piece {
    return Piece.fromBits(meta.bits.get(u6, offset_capture));
}

pub fn fiftyCounter(meta: Meta) u18 {
    return meta.bits.get(u18, offset_fifty);
}

pub fn setCastleKing(meta: *Meta, affiliation: Affiliation, val: bool) void {
    switch (affiliation) {
        .white => meta.bits.set(u1, offset_whiteking, @intFromBool(val)),
        .black => meta.bits.set(u1, offset_blackking, @intFromBool(val)),
    }
}

pub fn setCastleQueen(meta: *Meta, affiliation: Affiliation, val: bool) void {
    switch (affiliation) {
        .white => meta.bits.set(u1, offset_whitequeen, @intFromBool(val)),
        .black => meta.bits.set(u1, offset_blackqueen, @intFromBool(val)),
    }
}

pub fn setEnpassantFile(meta: *Meta, file: ?File) void {
    if (file) |f|
        meta.bits.set(u4, offset_enpassant, @as(u4, @intCast(f.val() + 1)))
    else
        meta.bits.set(u4, offset_enpassant, 0);
}

pub fn setCapturedPiece(meta: *Meta, piece: Piece) void {
    meta.bits.set(u6, offset_capture, piece.bits.bits);
}

pub fn setFiftyCounter(meta: *Meta, val: u18) void {
    meta.bits.set(u18, offset_fifty, val);
}

pub fn incFiftyCounter(meta: *Meta) void {
    meta.bits.set(u18, offset_fifty, meta.bits.get(u18, offset_fifty) + 1);
}
