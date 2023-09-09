// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");
const zcon = @import("zcon");
const network = @import("network");
const parsley = @import("parsley");

const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");
const FullscreenFrontend = @import("frontend/Fullscreen.zig");
const Position = @import("hellochess/Position.zig");
const Affiliation = @import("hellochess/Piece.zig").Affiliation;

pub const command_sequence = "join";
pub const description_line = "join peer to peer game";
pub const description_full = description_line ++ "\n\nusage: hellochess join <address> [options]";
pub const positionals = &[_]parsley.Positional{
    .{ "address", .string },
};

pub fn run(
    allocator: std.mem.Allocator,
    writer: *zcon.Writer,
    poss: parsley.Positionals(@This()),
    opts: parsley.Options(@This()),
) anyerror!void {
    try network.init();
    defer network.deinit();

    const address = parseAddress(poss.address) orelse {
        writer.fmt("invalid address\n", .{});
        return;
    };
    var result = connectToHost(writer, allocator, address[0], address[1]) catch |err| {
        writer.fmt("failed to connect ({s})\n", .{@errorName(err)});
        return;
    };

    const position = Position.init();
    const frontend = Frontend.initNetwork(result[1], result[0]);
    if (opts.fullscreen) {
        var game = FullscreenFrontend{ .frontend = frontend };
        game.frontend.position = position;
        try game.run(writer);
    } else {
        var game = InlineFrontend{ .frontend = frontend };
        game.frontend.position = position;
        try game.run(writer);
    }
}

/// connect to host specified by addr and port
/// return resulting socket
fn connectToHost(
    writer: *zcon.Writer,
    allocator: std.mem.Allocator,
    addr: []const u8,
    port: u16,
) !struct { network.Socket, Affiliation } {
    var sock = try network.connectToHost(allocator, addr, port, .tcp);
    errdefer sock.close();

    const endpoint = try sock.getRemoteEndPoint();
    writer.fmt("game connected at {}\n", .{endpoint});

    // recieve affiliation from host
    var affiliation: [1]u8 = undefined;
    const read = try sock.receive(&affiliation);

    if (read == 0)
        return error.SocketNotConnected;

    return .{ sock, @enumFromInt(affiliation[0]) };
}

fn parseAddress(string: []const u8) ?struct { []const u8, u16 } {
    var it = std.mem.split(u8, string, ":");
    const addr = it.next() orelse return null;
    const port_str = it.next() orelse return null;
    if (it.next()) |_| return null;
    const port = std.fmt.parseInt(u16, port_str, 10) catch return null;
    return .{ addr, port };
}

pub const options = &[_]parsley.Option{
    .{
        .name = "fullscreen",
        .name_short = null,
        .description = "use the fullscreen frontend",
        .arguments = &[_]parsley.Argument{},
    },
};
