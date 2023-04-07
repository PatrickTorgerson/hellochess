// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

//!
//! 64 bits, one for each square on a chess board
//! set them, get them, iterate them
//!

const std = @import("std");

const Coordinate = @import("Coordinate.zig");

const Bitboard = @This();
const BitSet = std.bit_set.IntegerBitSet(64);

bits: BitSet,

/// create a bitboard, all bits off
pub fn init() Bitboard {
    return .{
        .bits = BitSet.initEmpty(),
    };
}

/// create a bitbord from a u64
pub fn fromInt(int: u64) Bitboard {
    return .{
        .bits = .{ .mask = int },
    };
}

/// set bit associated with `coord` to `value`
pub fn set(bitboard: *Bitboard, coord: Coordinate, value: bool) void {
    bitboard.bits.setValue(coord.index(), value);
}

/// get value of bit associated with `coord`
pub fn get(bitboard: Bitboard, coord: Coordinate) bool {
    return bitboard.bits.isSet(coord.index());
}

/// iterate over set bits
pub const Iterator = struct {
    iter: BitSet.Iterator(.{}),

    pub fn init(bitboard: Bitboard) Iterator {
        return .{
            .iter = bitboard.bits.iterator(.{}),
        };
    }

    pub fn next(iter: *Iterator) ?Coordinate {
        if (iter.iter.next()) |index|
            return Coordinate.from1d(@intCast(i8, index))
        else
            return null;
    }
};

/// return iterator to iterate over set bits
pub fn iterator(bitboard: Bitboard) Iterator {
    return Iterator.init(bitboard);
}
