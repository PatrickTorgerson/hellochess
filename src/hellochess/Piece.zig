// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub const Piece = @This();

const Coordinate = @import("types.zig").Coordinate;

///-----------------------------------------------------------------------------
///  A piece's affiliation, white or black
///
pub const Affiliation = enum(u8) {
    white = 0,
    black = 1,

    /// returns other affiliation
    pub fn opponent(affiliation_: Affiliation) Affiliation {
        return switch (affiliation_) {
            .white => .black,
            .black => .white,
        };
    }

    /// return the direction pawns move, -1 or +1
    pub fn direction(affiliation_: Affiliation) i8 {
        return switch (affiliation_) {
            .white => 1,
            .black => -1,
        };
    }
    /// return the reverse of direction pawns move, -1 or +1
    pub fn reverseDirection(affiliation_: Affiliation) i8 {
        return -affiliation_.direction();
    }

    /// return the rank pawns get pushed to when moving two squares
    pub fn doublePushRank(affiliation_: Affiliation) i8 {
        return switch (affiliation_) {
            .white => 3, // 4
            .black => 4, // 5  zero based indecies am I right
        };
    }

    /// return the second rank
    pub fn secondRank(affiliation_: Affiliation) i8 {
        return switch (affiliation_) {
            .white => 1, // 2
            .black => 6, // 7  zero based indecies am I right
        };
    }

    /// return rank an allied pawn can en passant from
    pub fn enPassantRank(affiliation_: Affiliation) i8 {
        return switch (affiliation_) {
            .white => 4, // 5
            .black => 3, // 4  zero based indecies am I right
        };
    }

    /// return the back rank
    pub fn backRank(affiliation_: Affiliation) i8 {
        return switch (affiliation_) {
            .white => 0, // 1
            .black => 7, // 8  zero based indecies am I right
        };
    }

    /// return starting coord of the rook on file a
    pub fn aRookCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.fromString("a1"),
            .black => Coordinate.fromString("a8"),
        };
    }

    /// return starting coord of the rook on file h
    pub fn hRookCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.fromString("h1"),
            .black => Coordinate.fromString("h8"),
        };
    }

    pub fn kingCoord(affiliation_: Affiliation) Coordinate {
        return switch (affiliation_) {
            .white => Coordinate.fromString("e1"),
            .black => Coordinate.fromString("e8"),
        };
    }
};

///-----------------------------------------------------------------------------
///  Type of piece independent of affiliation
///
pub const Class = enum(u8) {
    pawn = 1,
    knight = 3,
    bishop = 4, // bishop value is also 3 but enume vals must be unique
    rook = 6,
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
            // is a terminal doesn't support Unicode
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
///  - high nibble is affiliation
///  - low nibble is class
bits: u8,

/// init piece from a class and affiliation
pub fn init(class_: Class, affiliation_: Affiliation) Piece {
    return .{
        .bits = (@enumToInt(affiliation_) << 4) | @enumToInt(class_),
    };
}

/// return piece's class
pub fn class(piece: Piece) Class {
    return @intToEnum(Class, piece.bits & 0b01111);
}

/// return piece's affiliation
pub fn affiliation(piece: Piece) Affiliation {
    return @intToEnum(Affiliation, piece.bits >> 4);
}

/// return piece's material value
pub fn value(piece: Piece) i32 {
    return piece.class().value();
}

/// return character used to denote class in move notation
pub fn character(piece: Piece) u8 {
    return piece.class().character();
}

/// return ascii art for class
pub fn ascii(piece: Piece) []const u8 {
    return piece.class().ascii();
}

/// return Unicode symbol used to render piece
pub fn symbol(piece: Piece) []const u8 {
    if (piece.affiliation() == .black)
        return switch (piece.class()) {
            .pawn => "♟",
            .knight => "♞",
            .bishop => "♝",
            .rook => "♜",
            .queen => "♛",
            .king => "♚",
        }
    else
        return switch (piece.class()) {
            .pawn => "♙",
            .knight => "♘",
            .bishop => "♗",
            .rook => "♖",
            .queen => "♕",
            .king => "♔",
        };
}

/// compare piece with class and affiliation for equality
pub fn eq(piece: Piece, class_: Class, affiliation_: Affiliation) bool {
    return piece.bits == Piece.init(class_, affiliation_).bits;
}

/// compare piece with class and affiliation for inequality
pub fn neq(piece: Piece, class_: Class, affiliation_: Affiliation) bool {
    return !piece.eq(class_, affiliation_);
}
