const std = @import("std");

/// https://learn.microsoft.com/en-us/windows/console/console-virtual-terminal-sequences

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub fn put(bg: Color, fg: Color, comptime fmt: []const u8, args: anytype) void {
    var stdout = std.io.getStdOut().writer();
    stdout.print("\x1b[48;2;{};{};{}m", .{bg.r, bg.g, bg.b}) catch {};
    stdout.print("\x1b[38;2;{};{};{}m", .{fg.r, fg.g, fg.b}) catch {};
    stdout.print(fmt, args) catch {};
    stdout.writeAll("\x1b[0m") catch {};
}

pub fn print(comptime fmt: []const u8, args: anytype) void {
    var stdout = std.io.getStdOut().writer();
    stdout.print(fmt, args) catch {};
}

pub fn write(fmt: []const u8) void {
    var stdout = std.io.getStdOut().writer();
    stdout.writeAll(fmt) catch {};
}

pub fn clear_line() void {
    var stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b[2K") catch {};
    stdout.writeAll("\x1b[0G") catch {};
}

pub fn set_home() void {
    var stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b7") catch {};
}

pub fn home() void {
    var stdout = std.io.getStdOut().writer();
    stdout.writeAll("\x1b8") catch {};
}
