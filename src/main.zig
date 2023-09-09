// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");
const zcon = @import("zcon");
const parsley = @import("parsley");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var writer = zcon.Writer.init();
    defer writer.flush();
    defer writer.useDefaultColors();

    try parsley.run(allocator, &writer, &.{
        @import("play.zig"),
        @import("host.zig"),
        @import("join.zig"),
    }, .{ .command_descriptions = command_descriptions });
}

const command_descriptions = &[_]parsley.CommandDescription{.{
    .command_sequence = "",
    .line = "not used",
    .full =
    \\ It's chess, on the command line
    \\
    \\ Usage: hellochess <command> [args] [options]
    ,
}};
