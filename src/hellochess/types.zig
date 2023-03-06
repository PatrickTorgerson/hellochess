// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

const Piece = @import("Piece.zig");

///-----------------------------------------------------------------------------
///  Coordinate of a square on a chess board, rank and file
///
pub const Coordinate = struct {
    /// row, vertical pos
    rank: i8,
    // column, horizantal pos
    file: i8,

    ///  string storang text data for square names, used in to_string
    const pos_strs: []const u8 =
        "a1" ++ "a2" ++ "a3" ++ "a4" ++ "a5" ++ "a6" ++ "a7" ++ "a8" ++
        "b1" ++ "b2" ++ "b3" ++ "b4" ++ "b5" ++ "b6" ++ "b7" ++ "b8" ++
        "c1" ++ "c2" ++ "c3" ++ "c4" ++ "c5" ++ "c6" ++ "c7" ++ "c8" ++
        "d1" ++ "d2" ++ "d3" ++ "d4" ++ "d5" ++ "d6" ++ "d7" ++ "d8" ++
        "e1" ++ "e2" ++ "e3" ++ "e4" ++ "e5" ++ "e6" ++ "e7" ++ "e8" ++
        "f1" ++ "f2" ++ "f3" ++ "f4" ++ "f5" ++ "f6" ++ "f7" ++ "f8" ++
        "g1" ++ "g2" ++ "g3" ++ "g4" ++ "g5" ++ "g6" ++ "g7" ++ "g8" ++
        "h1" ++ "h2" ++ "h3" ++ "h4" ++ "h5" ++ "h6" ++ "h7" ++ "h8";

    /// returns the string representation of a square eg: "e4"
    pub fn to_String(pos: Coordinate) []const u8 {
        std.debug.assert(pos.valid());
        const index = pos.to_1d();
        return pos_strs[index * 2 .. index * 2 + 2];
    }

    /// converts string representation of a square to rank and file position
    pub fn from_string(str: []const u8) Coordinate {
        std.debug.assert(str.len == 2);
        return Coordinate.init(
            Coordinate.file_from_char(str[0]),
            Coordinate.rank_from_char(str[1]),
        );
    }

    /// init a position from a rank and file
    pub fn init(file: i8, rank: i8) Coordinate {
        std.debug.assert(file < 8 and rank < 8);
        return .{
            .rank = rank,
            .file = file,
        };
    }

    /// returns a new position relative to a given position
    pub fn offsetted(pos: Coordinate, file_offset: i8, rank_offset: i8) Coordinate {
        return Coordinate.init(
            pos.file + file_offset,
            pos.rank + rank_offset,
        );
    }

    /// converts a 1d index to a 2d rank and file
    /// used for indexing into an array
    /// 0 = a1, 1 = a2 ...
    pub fn from_1d(d: usize) Coordinate {
        return Coordinate.init(@intCast(i8, @divFloor(d, 8)), @intCast(i8, d % 8));
    }

    /// converts a 2d rank and file to a 1d index
    /// 0 = a1, 1 = a2 ...
    pub fn to_1d(pos: Coordinate) usize {
        std.debug.assert(pos.valid());
        return @intCast(usize, pos.file * 8 + pos.rank);
    }

    /// return true if coord is within bounds of a standard chess board
    pub fn valid(pos: Coordinate) bool {
        return pos.file < 8 and pos.rank < 8;
    }

    /// return file from standard chess file letter ascii
    pub fn file_from_char(char: u8) i8 {
        std.debug.assert(is_file(char));
        return @intCast(i8, char) - 'a';
    }

    /// return rank from standard chess rank number ascii
    pub fn rank_from_char(char: u8) i8 {
        std.debug.assert(is_rank(char));
        return @intCast(i8, char) - '1';
    }

    pub fn is_rank(char: u8) bool {
        return char >= '1' and char <= '8';
    }

    pub fn is_file(char: u8) bool {
        return char >= 'a' and char <= 'h';
    }

    test "2d 1d mapping" {
        try std.testing.expectEqual(@as(usize, 5), Coordinate.from_1d(5).to_1d());
        const pos = Coordinate.init(4, 7);
        try std.testing.expectEqual(pos, Coordinate.from_1d(pos.to_1d()));
        try std.testing.expectEqual(@as(usize, 0), Coordinate.init(0, 0).to_1d());
        try std.testing.expectEqual(@as(usize, 35), Coordinate.init(4, 3).to_1d());
        try std.testing.expectEqual(Coordinate.init(4, 3), Coordinate.from_1d(35));
    }
};

///-----------------------------------------------------------------------------
///  A single square on a board, can be empty or have a piece
///
pub const Square = struct {
    /// encodes piece and empty flag
    bits: u8,

    /// init Square with a piece
    pub fn init(piece_: Piece) Square {
        return .{
            .bits = piece_.bits & 0b00011111,
        };
    }

    /// returns an empty square
    pub fn empty() Square {
        return .{
            .bits = 0b10000000,
        };
    }

    /// return the pice on this square, null if empty
    pub fn piece(square: Square) ?Piece {
        if (square.bits & 0b10000000 == 0) {
            return Piece{
                .bits = square.bits & 0b00011111,
            };
        } else return null;
    }
};

///-----------------------------------------------------------------------------
///  Decoded chess move
///
pub const Move = struct {
    /// piece to move
    piece: Piece,
    /// where it is
    location: Coordinate,
    /// where it's going
    destination: Coordinate,
};

///-----------------------------------------------------------------------------
///  Result of attmpting a move
///
pub const MoveResult = enum {
    ok,
    ok_check,
    ok_mate,
    ok_stalemate,
    ok_repitition,
    ok_insufficient_material,

    bad_notation,
    bad_disambiguation,
    ambiguous_piece,
    no_such_piece,
    no_visibility,
    in_check,
    enters_check,
    blocked,
};

test "refs" {
    // run tests in Position
    std.testing.refAllDeclsRecursive(Coordinate);
}
