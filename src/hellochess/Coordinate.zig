// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! Coordinate of a square on a chess board
//!

const std = @import("std");

const EnumIterator = @import("util.zig").EnumIterator;

/// the 8 ranks on a chess board
pub const Rank = enum(i8) {
    rank_1,
    rank_2,
    rank_3,
    rank_4,
    rank_5,
    rank_6,
    rank_7,
    rank_8,

    pub fn init(value: i8) Rank {
        return @intToEnum(Rank, value);
    }

    pub fn val(rank: Rank) i8 {
        return @enumToInt(rank);
    }

    pub fn index(rank: Rank) usize {
        return @intCast(usize, rank.val());
    }

    pub fn iterator(rank: Rank) EnumIterator(Rank) {
        return EnumIterator(Rank).init(rank);
    }
};

/// the 8 files on a chess board
pub const File = enum(i8) {
    file_a,
    file_b,
    file_c,
    file_d,
    file_e,
    file_f,
    file_g,
    file_h,

    pub fn init(value: i8) File {
        return @intToEnum(File, value);
    }

    pub fn val(file: File) i8 {
        return @enumToInt(file);
    }

    pub fn index(file: File) usize {
        return @intCast(usize, file.val());
    }

    pub fn iterator(file: File) EnumIterator(File) {
        return EnumIterator(File).init(file);
    }
};

/// the 8 directions on a chess board
///   * north: towards rank 8
///   * south: towards rank 1
///   * east: towards file h
///   * west: towards file a
///   * northeast: towards rank 8, file h
///   * northwest: towards rank 8, file a
///   * southeast: towards rank 1, file h
///   * southwest: towards rank 1, file a
pub const Direction = enum(u3) {
    north,
    south,
    east,
    west,
    northeast,
    northwest,
    southeast,
    southwest,

    // zig fmt: off
    /// offset required to move a 1d index 1 square in a given direction
    const offsets = [_]i8{
         1,  // north
        -1,  // south
         8,  // east
        -8,  // west
         9,  // northeast
        -7,  // northwest
         7,  // southeast
        -9,  // southwest
    };
    // zig fmt: on

    /// return offset required to move a 1d index 1 square in given direction
    pub fn offset(dir: Direction) i8 {
        return offsets[dir.asUsize()];
    }

    /// returns reversed version of `dir`
    pub fn reversed(dir: Direction) Direction {
        return switch (dir) {
            .north => .south,
            .south => .north,
            .east => .west,
            .west => .east,
            .northeast => .southwest,
            .northwest => .southeast,
            .southeast => .northwest,
            .southwest => .northeast,
        };
    }

    /// returns enum value as usize
    pub fn asUsize(dir: Direction) usize {
        return @intCast(usize, @enumToInt(dir));
    }
};

const Coordinate = @This();

/// encodes rank and file as a 1d index
/// 0 = a1, 1 = a2 ... 8 = b1
value: i8,

/// creates Coordinate from 1d index
/// 0 = a1, 1 = a2 ...
pub fn from1d(i: i8) Coordinate {
    return .{
        .value = i,
    };
}

/// creates Coordinate from 2d coord
/// file and rank
pub fn from2d(file: File, rank: Rank) Coordinate {
    return Coordinate.from1d(file.val() * 8 + rank.val());
}

/// returns the string representation of a square eg: "e4"
pub fn toString(coord: Coordinate) []const u8 {
    std.debug.assert(coord.valid());
    return square_names[coord.index() * 2 .. coord.index() * 2 + 2];
}

/// converts string representation of a square to rank and file coord
pub fn fromString(str: []const u8) Coordinate {
    std.debug.assert(str.len == 2);
    return Coordinate.from2d(
        Coordinate.fileFromChar(str[0]),
        Coordinate.rankFromChar(str[1]),
    );
}

/// return true if coord is within bounds of a standard chess board
pub fn valid(coord: Coordinate) bool {
    return coord.value >= 0 and coord.value < 64;
}

/// return coord as 1d index
pub fn index(coord: Coordinate) usize {
    std.debug.assert(coord.valid());
    return @intCast(usize, coord.value);
}

/// return file coord lies on
pub fn getFile(coord: Coordinate) File {
    std.debug.assert(coord.valid());
    return File.init(@divFloor(coord.value, 8));
}

/// return rank coord lies on
pub fn getRank(coord: Coordinate) Rank {
    std.debug.assert(coord.valid());
    return Rank.init(@rem(coord.value, 8));
}

pub fn eql(coord: Coordinate, other: Coordinate) bool {
    return coord.value == other.value;
}

/// offset coord `amt` squares in direction `dir`
/// if offest would leave coord off board, clamp values
/// such that coord gets left on the edge of board
/// returns whether coord was clamped due to bounds failure
pub fn offsetDir(coord: *Coordinate, dir: Direction, amt: i8) bool {
    const multiplier = std.math.min(amt, squares_to_edge[coord.index()][dir.asUsize()]);
    coord.value += dir.offset() * multiplier;
    return multiplier == amt;
}

/// offset coord rank and file
/// if offest would leave coord off board, clamp values
/// such that coord gets left on the edge of board
/// returns whether coord was clamped due to bounds failure
pub fn offset(coord: *Coordinate, file_offset: i8, rank_offset: i8) bool {
    const capped_file_offset = if (file_offset > 0)
        std.math.min(file_offset, squares_to_edge[coord.index()][Direction.east.asUsize()])
    else
        std.math.max(file_offset, -squares_to_edge[coord.index()][Direction.west.asUsize()]);

    const capped_rank_offset = if (rank_offset > 0)
        std.math.min(rank_offset, squares_to_edge[coord.index()][Direction.north.asUsize()])
    else
        std.math.max(rank_offset, -squares_to_edge[coord.index()][Direction.south.asUsize()]);

    coord.value += capped_rank_offset + capped_file_offset * 8;
    return capped_file_offset == file_offset and capped_rank_offset == rank_offset;
}

/// returns a new coord offsetted relative to a given coord
/// if resulting coord is off board, return null
pub fn offsettedDir(coord: Coordinate, dir: Direction, amt: i8) ?Coordinate {
    var new_coord = coord;
    return if (new_coord.offsetDir(dir, amt))
        new_coord
    else
        null;
}

/// returns a new coord offsetted relative to a given coord
/// if resulting coord is off board, return null
pub fn offsetted(coord: Coordinate, file_offset: i8, rank_offset: i8) ?Coordinate {
    var new_coord = coord;
    return if (new_coord.offset(file_offset, rank_offset))
        new_coord
    else
        null;
}

/// return file from standard chess file letter ascii
pub fn fileFromChar(char: u8) File {
    std.debug.assert(isFile(char));
    return File.init(@intCast(i8, char) - 'a');
}

/// return rank from standard chess rank number ascii
pub fn rankFromChar(char: u8) Rank {
    std.debug.assert(isRank(char));
    return Rank.init(@intCast(i8, char) - '1');
}

/// return if ascii char represents a valid rank
pub fn isRank(char: u8) bool {
    return char >= '1' and char <= '8';
}

/// return if ascii char represents a valid file
pub fn isFile(char: u8) bool {
    return char >= 'a' and char <= 'h';
}

/// stores number of cells to edge of board for each index in each direction
/// usefull for bounds checking due to how 1d coords wrap the board
const squares_to_edge: [64][8]i8 = blk: {
    @setEvalBranchQuota(2000);
    var num_to_edge: [64][8]i8 = undefined;
    var rank: usize = 0;
    while (rank < 8) : (rank += 1) {
        var file: usize = 0;
        while (file < 8) : (file += 1) {
            var north = 8 - 1 - rank;
            var south = rank;
            var east = 8 - 1 - file;
            var west = file;
            const i = file * 8 + rank;
            num_to_edge[i][Direction.north.asUsize()] = north;
            num_to_edge[i][Direction.south.asUsize()] = south;
            num_to_edge[i][Direction.east.asUsize()] = east;
            num_to_edge[i][Direction.west.asUsize()] = west;
            num_to_edge[i][Direction.northeast.asUsize()] = std.math.min(north, east);
            num_to_edge[i][Direction.northwest.asUsize()] = std.math.min(north, west);
            num_to_edge[i][Direction.southeast.asUsize()] = std.math.min(south, east);
            num_to_edge[i][Direction.southwest.asUsize()] = std.math.min(south, west);
        }
    }
    break :blk num_to_edge;
};

///  string storing text data for square names, used in toString
const square_names: []const u8 =
    "a1" ++ "a2" ++ "a3" ++ "a4" ++ "a5" ++ "a6" ++ "a7" ++ "a8" ++
    "b1" ++ "b2" ++ "b3" ++ "b4" ++ "b5" ++ "b6" ++ "b7" ++ "b8" ++
    "c1" ++ "c2" ++ "c3" ++ "c4" ++ "c5" ++ "c6" ++ "c7" ++ "c8" ++
    "d1" ++ "d2" ++ "d3" ++ "d4" ++ "d5" ++ "d6" ++ "d7" ++ "d8" ++
    "e1" ++ "e2" ++ "e3" ++ "e4" ++ "e5" ++ "e6" ++ "e7" ++ "e8" ++
    "f1" ++ "f2" ++ "f3" ++ "f4" ++ "f5" ++ "f6" ++ "f7" ++ "f8" ++
    "g1" ++ "g2" ++ "g3" ++ "g4" ++ "g5" ++ "g6" ++ "g7" ++ "g8" ++
    "h1" ++ "h2" ++ "h3" ++ "h4" ++ "h5" ++ "h6" ++ "h7" ++ "h8";

/// named square constants
pub const a1 = Coordinate.from1d(0);
pub const a2 = Coordinate.from1d(1);
pub const a3 = Coordinate.from1d(2);
pub const a4 = Coordinate.from1d(3);
pub const a5 = Coordinate.from1d(4);
pub const a6 = Coordinate.from1d(5);
pub const a7 = Coordinate.from1d(6);
pub const a8 = Coordinate.from1d(7);
pub const b1 = Coordinate.from1d(8);
pub const b2 = Coordinate.from1d(9);
pub const b3 = Coordinate.from1d(10);
pub const b4 = Coordinate.from1d(11);
pub const b5 = Coordinate.from1d(12);
pub const b6 = Coordinate.from1d(13);
pub const b7 = Coordinate.from1d(14);
pub const b8 = Coordinate.from1d(15);
pub const c1 = Coordinate.from1d(16);
pub const c2 = Coordinate.from1d(17);
pub const c3 = Coordinate.from1d(18);
pub const c4 = Coordinate.from1d(19);
pub const c5 = Coordinate.from1d(20);
pub const c6 = Coordinate.from1d(21);
pub const c7 = Coordinate.from1d(22);
pub const c8 = Coordinate.from1d(23);
pub const d1 = Coordinate.from1d(24);
pub const d2 = Coordinate.from1d(25);
pub const d3 = Coordinate.from1d(26);
pub const d4 = Coordinate.from1d(27);
pub const d5 = Coordinate.from1d(28);
pub const d6 = Coordinate.from1d(29);
pub const d7 = Coordinate.from1d(30);
pub const d8 = Coordinate.from1d(31);
pub const e1 = Coordinate.from1d(32);
pub const e2 = Coordinate.from1d(33);
pub const e3 = Coordinate.from1d(34);
pub const e4 = Coordinate.from1d(35);
pub const e5 = Coordinate.from1d(36);
pub const e6 = Coordinate.from1d(37);
pub const e7 = Coordinate.from1d(38);
pub const e8 = Coordinate.from1d(39);
pub const f1 = Coordinate.from1d(40);
pub const f2 = Coordinate.from1d(41);
pub const f3 = Coordinate.from1d(42);
pub const f4 = Coordinate.from1d(43);
pub const f5 = Coordinate.from1d(44);
pub const f6 = Coordinate.from1d(45);
pub const f7 = Coordinate.from1d(46);
pub const f8 = Coordinate.from1d(47);
pub const g1 = Coordinate.from1d(48);
pub const g2 = Coordinate.from1d(49);
pub const g3 = Coordinate.from1d(50);
pub const g4 = Coordinate.from1d(51);
pub const g5 = Coordinate.from1d(52);
pub const g6 = Coordinate.from1d(53);
pub const g7 = Coordinate.from1d(54);
pub const g8 = Coordinate.from1d(55);
pub const h1 = Coordinate.from1d(56);
pub const h2 = Coordinate.from1d(57);
pub const h3 = Coordinate.from1d(58);
pub const h4 = Coordinate.from1d(59);
pub const h5 = Coordinate.from1d(60);
pub const h6 = Coordinate.from1d(61);
pub const h7 = Coordinate.from1d(62);
pub const h8 = Coordinate.from1d(63);
