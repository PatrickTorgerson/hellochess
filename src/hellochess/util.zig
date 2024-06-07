// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");

/// Iterates through fields in an enum
pub fn EnumIterator(comptime E: type) type {
    std.debug.assert(@typeInfo(E) == .Enum); // EnumIterator, T must be an enum
    const size = std.meta.fields(E).len;
    const T = std.meta.Tag(E);
    return struct {
        i: T = 0,
        dir: Direction,

        pub const Direction = enum { reverse, forward };

        pub fn init(initial: E, direction: Direction) @This() {
            return .{
                .i = @intFromEnum(initial),
                .dir = direction,
            };
        }

        pub fn next(this: *@This()) ?E {
            if (this.i < 0 or this.i >= size)
                return null;
            defer {
                switch (this.dir) {
                    .reverse => this.i -%= 1,
                    .forward => this.i += 1,
                }
            }
            return @as(E, @enumFromInt(this.i));
        }
    };
}

test "EnumIterator" {
    const E = enum(u8) { one, two, three };

    var iter = EnumIterator(E).init(.three, .reverse);

    try std.testing.expectEqual(@as(?E, E.three), iter.next());
    try std.testing.expectEqual(@as(?E, E.two), iter.next());
    try std.testing.expectEqual(@as(?E, E.one), iter.next());
    try std.testing.expectEqual(@as(?E, null), iter.next());
}

/// Allows getting and setting bit ranges in an unsigned integer
pub fn Bitfield(comptime T: type) type {
    return struct {
        bits: T = 0,

        pub const Index = std.math.Log2Int(T);

        pub fn set(this: *@This(), comptime V: type, offset: Index, val: V) void {
            const len = @typeInfo(V).Int.bits;
            std.debug.assert(offset + len <= @typeInfo(T).Int.bits);
            this.bits &= ~mask(offset, len);
            this.bits |= @as(T, @intCast(val)) << offset;
        }

        pub fn get(this: @This(), comptime V: type, offset: Index) V {
            const len = @typeInfo(V).Int.bits;
            std.debug.assert(offset + len <= @typeInfo(T).Int.bits);
            return @intCast((this.bits & mask(offset, len)) >> offset);
        }

        pub fn mask(offset: Index, len: Index) T {
            return ~(~@as(T, 0) << len) << offset;
        }
    };
}

test "Bitfield" {
    var bits = Bitfield(u32){ .bits = @as(u32, 0b0000011000000000) };
    bits.set(u8, 8, 6);
    try std.testing.expectEqual(@as(u32, 0b11000000000), bits.bits);
    try std.testing.expectEqual(@as(u32, 0b1111111100000000), Bitfield(u32).mask(8, 8));
    try std.testing.expectEqual(@as(u8, 0), bits.get(u8, 0));
    try std.testing.expectEqual(@as(u8, 6), bits.get(u8, 8));
    try std.testing.expectEqual(@as(u8, 96), bits.get(u8, 4));
    bits.set(u16, 5, 6969);
    bits.set(u5, 0, 16);
    try std.testing.expectEqual(@as(u16, 6969), bits.get(u16, 5));
    try std.testing.expectEqual(@as(u5, 16), bits.get(u5, 0));
}
