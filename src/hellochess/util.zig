// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

/// Iterates through fields in an enum
pub fn EnumIterator(comptime T: type) type {
    std.debug.assert(@typeInfo(T) == .Enum); // EnumIterator, T must be an enum
    return struct {
        i: std.meta.Tag(T) = 0,

        pub fn init(initial: T) @This() {
            return .{
                .i = @enumToInt(initial),
            };
        }

        pub fn next(this: *@This()) ?T {
            if (this.i >= 8)
                return null;
            defer this.i += 1;
            return @intToEnum(T, this.i);
        }
    };
}

/// Allows getting and setting bit ranges in an unsigned integer
pub fn Bitfield(comptime T: type) type {
    std.debug.assert(std.meta.trait.isUnsignedInt(T));
    return struct {
        bits: T = 0,

        pub const Index = std.math.Log2Int(T);

        pub fn set(this: *@This(), comptime V: type, offset: Index, val: V) void {
            std.debug.assert(std.meta.trait.isUnsignedInt(V));
            const len = @typeInfo(V).Int.bits;
            std.debug.assert(offset + len <= @typeInfo(T).Int.bits);
            this.bits &= ~mask(offset, len);
            this.bits |= @intCast(T, val) << offset;
        }

        pub fn get(this: @This(), comptime V: type, offset: Index) V {
            std.debug.assert(std.meta.trait.isUnsignedInt(V));
            const len = @typeInfo(V).Int.bits;
            std.debug.assert(offset + len <= @typeInfo(T).Int.bits);
            return @intCast(V, (this.bits & mask(offset, len)) >> offset);
        }

        pub fn mask(offset: Index, len: Index) T {
            return ~(~@as(T, 0) << len) << offset;
        }
    };
}

test "Bitfield" {
    var bits = Bitfield(u32){ .bits = @as(u32, 0b0000011000000000) };
    bits.set(8, @as(u8, 6));
    try std.testing.expectEqual(@as(u32, 0b11000000000), bits.bits);
    try std.testing.expectEqual(@as(u32, 0b1111111100000000), Bitfield(u32).mask(8, 8));
    try std.testing.expectEqual(@as(u8, 0), bits.get(u8, 0));
    try std.testing.expectEqual(@as(u8, 6), bits.get(u8, 8));
    try std.testing.expectEqual(@as(u8, 96), bits.get(u8, 4));
    bits.set(5, @as(u16, 6969));
    bits.set(0, @as(u5, 16));
    try std.testing.expectEqual(@as(u16, 6969), bits.get(u16, 5));
    try std.testing.expectEqual(@as(u5, 16), bits.get(u5, 0));
}
