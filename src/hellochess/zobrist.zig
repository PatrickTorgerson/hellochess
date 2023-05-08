// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! https://www.chessprogramming.org/Zobrist_Hashing
//!

const std = @import("std");

const Position = @import("Position.zig");
const Coordinate = @import("Coordinate.zig");
const Piece = @import("Piece.zig");

const Class = Piece.Class;
const Affiliation = Piece.Affiliation;

pub const Hash = u64;

/// generate a Zobrist hash from `position`
pub fn hash(position: Position) Hash {
    var hash_code: Hash = 0;

    for (position.squares, 0..) |piece, c| {
        if (!piece.isEmpty()) {
            hash_code ^= values[valueIndex(c, piece.class().?, piece.affiliation().?)];
        }
    }

    if (position.side_to_move == .black)
        hash_code ^= values[0];

    if (position.meta.castleKing(.white))
        hash_code ^= kingCastleHashValue(.white);
    if (position.meta.castleQueen(.white))
        hash_code ^= queenCastleHashValue(.white);
    if (position.meta.castleKing(.black))
        hash_code ^= kingCastleHashValue(.black);
    if (position.meta.castleQueen(.black))
        hash_code ^= queenCastleHashValue(.black);

    if (position.meta.enpassantFile()) |file|
        hash_code ^= enpassantFileHashValue(file);

    return hash_code;
}

/// return the hash value for a `piece` and `coord`
/// xor with position hash to add or remove piece at target coord
/// asserts `piece` is not empty
pub fn pieceHashValue(coord: Coordinate, piece: Piece) Hash {
    std.debug.assert(!piece.isEmpty());
    return values[valueIndex(coord.index(), piece.class().?, piece.affiliation().?)];
}

/// return hash value for black to move
/// xor with position hash to swap side to move
pub fn sideToMoveHashValue() Hash {
    return values[0];
}

/// return hash value for affiliated side castle king
/// xor with position hash add or remove rights
pub fn kingCastleHashValue(affiliation: Affiliation) Hash {
    return values[affiliation.index() * 2 + 1];
}

/// return hash value for affiliated side castle queen
/// xor with position hash add or remove rights
pub fn queenCastleHashValue(affiliation: Affiliation) Hash {
    return values[affiliation.index() * 2 + 2];
}

/// return hash value for en passant target on `file`
/// xor with position hash to add or remove enpassant target file
pub fn enpassantFileHashValue(file: Coordinate.File) Hash {
    return values[file.index() + 5];
}

/// determine value index from `coord_index`, `class`, and `affiliation`
fn valueIndex(coord_index: usize, class: Class, affiliation: Affiliation) usize {
    const class_size = std.meta.fields(@TypeOf(class)).len;
    const affiliation_size = std.meta.fields(@TypeOf(affiliation)).len;
    const class_index = @intCast(usize, @enumToInt(class));
    const affiliation_index = @intCast(usize, @enumToInt(affiliation));
    return (coord_index * class_size * affiliation_size) +
        (affiliation_index * class_size) +
        class_index + 13;
}

/// set of psuedo random numbers used to generate hashes
/// there is a value for each piece at each square,
/// one for side to move,
/// four for castling rights,
/// and eight for possible enpassant target files
const values: [value_count]Hash = init: {
    @setEvalBranchQuota(4006); // any less and we error
    var values_data: [value_count]Hash = undefined;
    var rng = Rkiss.init(52619975261997);
    var i: usize = 0;
    while (i < value_count) : (i += 1)
        values_data[i] = rng.next();
    break :init values_data;
};

const piece_values = 64 * 12;
const side_to_move_values = 1;
const castle_rights_values = 4;
const enpassant_file_values = 8;

const value_count = piece_values + side_to_move_values + castle_rights_values + enpassant_file_values;

/// based on https://www.chessprogramming.org/Bob_Jenkins#RKISS
const Rkiss = struct {
    a: Hash,
    b: Hash,
    c: Hash,
    d: Hash,

    pub fn init(seed: Hash) Rkiss {
        var this: Rkiss = undefined;
        this.a = 0xf1ea5eed;
        this.b = seed;
        this.c = seed;
        this.d = seed;
        var i: i32 = 0;
        while (i < 20) : (i += 1)
            _ = this.next();
        return this;
    }

    pub fn next(rng: *Rkiss) Hash {
        const e: Hash = rng.a -% rot(rng.b, 7);
        rng.a = rng.b ^ rot(rng.c, 13);
        rng.b = rng.c +% rot(rng.d, 37);
        rng.c = rng.d +% e;
        rng.d = e +% rng.a;
        return rng.d;
    }

    fn rot(x: Hash, comptime k: comptime_int) Hash {
        return (x << k) | (x >> (64 - k));
    }
};

test "zobrist deterministic equality" {
    const position = try Position.fromFen("r6k/1P6/8/8/1pP5/8/3P4/7K w - c3 0 1");
    try std.testing.expectEqual(hash(position), hash(position));
    try std.testing.expectEqual(hash(position), hash(position));
}

test "zobrist incremental hashing" {
    const position1 = try Position.fromFen("r6k/1P6/8/8/1pP5/4r3/3P4/7K w - c3 0 1");
    const position2 = try Position.fromFen("r6k/1P6/8/8/1pP5/4P3/8/7K b - - 0 1");

    const target_hash = hash(position2);
    var actual_hash = hash(position1);

    // remove white pawn on d2
    actual_hash ^= pieceHashValue(Coordinate.d2, Piece.init(.pawn, .white));
    // remove black rook on e3
    actual_hash ^= pieceHashValue(Coordinate.e3, Piece.init(.rook, .black));
    // add white pawn on e3
    actual_hash ^= pieceHashValue(Coordinate.e3, Piece.init(.pawn, .white));
    // swap side to move
    actual_hash ^= sideToMoveHashValue();
    // remove c file enpassant target
    actual_hash ^= enpassantFileHashValue(Coordinate.File.file_c);

    try std.testing.expectEqual(target_hash, actual_hash);
}

test "zobrist value uniquness" {
    var map = std.AutoHashMap(Hash, void).init(std.testing.allocator);
    defer map.deinit();
    try map.ensureTotalCapacity(values.len);
    for (values) |value| {
        if (map.get(value)) |_|
            return error.DuplicateZobristValue;
        try map.put(value, {});
    }
}
