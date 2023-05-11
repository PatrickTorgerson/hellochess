const std = @import("std");

const This = @This();

field: i32 = 0,

const Enemy = union(enum) {
    slime: i32,
    zombie: f64,
};

const Cosa = struct {
    pub fn increase(self: *Cosa) void {
        self.field1 += 4;
    }
};

pub fn main() !void {
    var e = Enemy{ .slime = 33 };

    switch (e) {
        .slime => |_| {},
        .zombie => |_| {},
    }

    var hello: ?i32 = null;

    if (hello) {
        // h stuff
    } else {
        // // hello is null
    }

    while (iter.next()) |item| {
        //
    }

    var this: This = .{ .field = 43 };
    _ = this;

    std.log.info("Welcome to the jungle", .{});

    var i: i32 = 0;
    while (i < 20) : (i += 1) {
        // do stuffs
    }

    for (0..20) |a| {
        _ = a;
        // do stuff
    }

    const array1: [200]i32 = undefined;
    const array2: [200]i32 = undefined;
    for (array1, array2) |v, v2| {
        _ = v;
        _ = v2;
    }

    const ptr: *Cosa = &array1[4];
    const ptr2: [*]i32 = &array1[4];
    _ = ptr2;
    const ptr3: [*c]i32 = &array1[4];
    _ = ptr3;
    const ptr4: [*:0]i32 = &array1[4];
    _ = ptr4;
    const str: []const u8 = "ahdasd";
    _ = str;
    const str2: [:0]const u8 = "ahdasd";
    _ = str2;

    const value = ptr.increase();
    _ = value;
}
