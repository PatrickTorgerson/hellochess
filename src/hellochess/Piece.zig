// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

pub const Piece = @This();

const Coordinate = @import("Coordinate.zig");
const Bitfield = @import("util.zig").Bitfield;

///  A piece's affiliation, white or black
pub const Affiliation = enum(u1) {
    white = 0,
    black = 1,

    /// returns enum value as usize
    pub fn index(affiliation_: Affiliation) usize {
        return @intCast(usize, @enumToInt(affiliation_));
    }

    /// returns other affiliation
    pub fn opponent(affiliation_: Affiliation) Affiliation {
        return switch (affiliation_) {
            .white => .black,
            .black => .white,
        };
    }

    /// return the direction pawns move
    pub fn direction(affiliation_: Affiliation) Coordinate.Direction {
        return switch (affiliation_) {
            .white => .north,
            .black => .south,
        };
    }

    /// return the reverse of direction pawns move
    pub fn reverseDirection(affiliation_: Affiliation) Coordinate.Direction {
        return affiliation_.direction().reversed();
    }

    /// return the rank pawns get pushed to when moving two squares
    pub fn doublePushRank(affiliation_: Affiliation) Coordinate.Rank {
        return switch (affiliation_) {
            .white => .rank_4,
            .black => .rank_5,
        };
    }

    /// return the affiliated second rank
    pub fn secondRank(affiliation_: Affiliation) Coordinate.Rank {
        return switch (affiliation_) {
            .white => .rank_2,
            .black => .rank_7,
        };
    }

    /// return rank an allied pawn can en passant from
    pub fn enPassantRank(affiliation_: Affiliation) Coordinate.Rank {
        return switch (affiliation_) {
            .white => .rank_5,
            .black => .rank_4,
        };
    }

    /// return the affiliated back rank
    pub fn backRank(affiliation_: Affiliation) Coordinate.Rank {
        return switch (affiliation_) {
            .white => .rank_1,
            .black => .rank_8,
        };
    }

    /// return starting coord of the rook on file a
    pub fn aRookCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.a1,
            .black => Coordinate.a8,
        };
    }

    /// return starting coord of the rook on file h
    pub fn hRookCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.h1,
            .black => Coordinate.h8,
        };
    }

    /// return initial square of the affiliated king
    pub fn kingCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.e1,
            .black => Coordinate.e8,
        };
    }

    /// return initial square of the affiliated king
    pub fn kingCastleDest(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.g1,
            .black => Coordinate.g8,
        };
    }

    /// return initial square of the affiliated king
    pub fn queenCastleDest(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.c1,
            .black => Coordinate.c8,
        };
    }
};

///  Type of piece independent of affiliation
pub const Class = enum(u4) {
    pawn = 1,
    knight = 3,
    bishop = 4, // bishop value is also 3 but enum vals must be unique
    rook = 5,
    queen = 9,
    king = 0,

    /// return material value of class
    pub fn value(class_: Class) i32 {
        const enum_val = @intCast(i32, @enumToInt(class_));
        // 4 = bishop
        return if (enum_val == 4) 3 else enum_val;
    }

    /// return character used to denote class in move notation
    pub fn character(class_: Class) u8 {
        return switch (class_) {
            // pawns aren't notated but we may want to use these to render
            // if a terminal doesn't support Unicode
            .pawn => 'P',
            .knight => 'N',
            .bishop => 'B',
            .rook => 'R',
            .queen => 'Q',
            .king => 'K',
        };
    }

    /// return ascii art for class
    pub fn ascii(class_: Class) []const u8 {
        const piece_ascii = @import("piece_ascii.zig");
        return switch (class_) {
            .pawn => piece_ascii.pawn,
            .knight => piece_ascii.knight,
            .bishop => piece_ascii.bishop,
            .rook => piece_ascii.rook,
            .queen => piece_ascii.queen,
            .king => piece_ascii.king,
        };
    }
};

/// encodes a pieces class and affiliation
/// bits 0-3: class
/// bit 4: affiliation, 0 = white
/// bit 5: empty flag, 0 = empty
bits: Bitfield(u6),

const offset_empty = 5;
const offset_affiliation = 4;
const offset_class = 0;

/// create piece from a class and affiliation
pub fn init(class_: Class, affiliation_: Affiliation) Piece {
    var this = Piece{ .bits = .{} };
    this.bits.set(u1, offset_empty, @boolToInt(true)); // true mean no empty
    this.bits.set(u1, offset_affiliation, @enumToInt(affiliation_));
    this.bits.set(u4, offset_class, @enumToInt(class_));
    return this;
}

/// create piece from encoded bit field
/// bits 0-3: class
/// bit 4: affiliation, 0 = white
/// bit 5: empty flag, 0 = empty
pub fn fromBits(bits: u6) Piece {
    return .{
        .bits = .{ .bits = bits },
    };
}

/// return empty piece
pub fn empty() Piece {
    return .{ .bits = .{} };
}

/// return if piece is empty
pub fn isEmpty(piece: Piece) bool {
    return piece.bits.bits == 0;
}

/// return piece's class
pub fn class(piece: Piece) ?Class {
    return if (piece.isEmpty())
        null
    else
        @intToEnum(Class, piece.bits.get(u4, offset_class));
}

/// return piece's affiliation
pub fn affiliation(piece: Piece) ?Affiliation {
    return if (piece.isEmpty())
        null
    else
        @intToEnum(Affiliation, piece.bits.get(u1, offset_affiliation));
}

/// return piece's material value
pub fn value(piece: Piece) i32 {
    return (piece.class() orelse return 0).value();
}

/// return character used to denote class in move notation
pub fn character(piece: Piece) u8 {
    return (piece.class() orelse return ' ').character();
}

/// return ascii art for class
pub fn ascii(piece: Piece) []const u8 {
    return (piece.class() orelse return "").ascii();
}

/// return Unicode symbol used to render piece
pub fn symbol(piece: Piece) []const u8 {
    if (piece.isEmpty()) return " ";
    if (piece.affiliation().? == .black)
        return switch (piece.class().?) {
            .pawn => "♟",
            .knight => "♞",
            .bishop => "♝",
            .rook => "♜",
            .queen => "♛",
            .king => "♚",
        }
    else
        return switch (piece.class().?) {
            .pawn => "♙",
            .knight => "♘",
            .bishop => "♗",
            .rook => "♖",
            .queen => "♕",
            .king => "♔",
        };
}

/// returns true if piece's affiliation matches `affiliation_`
/// returns false is piece is empty
pub fn isAffiliated(piece: Piece, affiliation_: Affiliation) bool {
    return if (piece.isEmpty())
        false
    else
        @intToEnum(Affiliation, piece.bits.get(u1, offset_affiliation)) == affiliation_;
}

/// compare two pieces for equality
pub fn eql(lpiece: Piece, rpiece: Piece) bool {
    return lpiece.bits.bits == rpiece.bits.bits;
}

/// compare piece with class and affiliation for equality
pub fn is(piece: Piece, class_: Class, affiliation_: Affiliation) bool {
    return Piece.init(class_, affiliation_).eql(piece);
}
