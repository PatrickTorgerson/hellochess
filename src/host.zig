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

pub const command_sequence = "host";
pub const description_line = "host peer to peer game";
pub const description_full = description_line;
pub const positionals = &[_]parsley.Positional{
    .{ "port", .integer },
};

pub fn run(
    _: *void,
    _: std.mem.Allocator,
    writer: *zcon.Writer,
    poss: parsley.Positionals(@This()),
    opts: parsley.Options(@This()),
) anyerror!void {
    try network.init();
    defer network.deinit();

    const affiliation = parseAffiliation(opts.affiliation orelse "random") orelse {
        writer.fmt("invalid affiliation '{s}'\n", .{opts.affiliation orelse "random"});
        return;
    };
    const client = waitForClient(writer, @intCast(poss.port), affiliation) catch |err| {
        writer.fmt("failed to connect ({s})\n", .{@errorName(err)});
        return;
    };

    const frontend = Frontend.initNetwork(affiliation, client);
    const position = Position.init();
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

/// wait for client connection on port
/// return resulting socket
fn waitForClient(writer: *zcon.Writer, port: u16, affiliation: Affiliation) !network.Socket {
    var sock = try network.Socket.create(.ipv4, .tcp);
    defer sock.close();

    try sock.bindToPort(port);
    try sock.listen();

    writer.fmt("\nwaiting for opponent ...\n", .{});
    writer.flush();

    var client = try sock.accept();
    errdefer client.close();

    std.debug.print("client connected from {}.\n", .{
        try client.getLocalEndPoint(),
    });

    // send affiliation to client
    const opponent = @as(u8, @intCast(@intFromEnum(affiliation.opponent())));
    _ = try client.send(&[_]u8{opponent});

    return client;
}

fn parseAffiliation(string: []const u8) ?Affiliation {
    if (std.mem.eql(u8, string, "white"))
        return .white
    else if (std.mem.eql(u8, string, "black"))
        return .black
    else if (std.mem.eql(u8, string, "random")) {
        const seed = @as(u64, @truncate(@as(u128, @bitCast(std.time.nanoTimestamp()))));
        var rng = std.Random.DefaultPrng.init(seed);
        if (rng.random().boolean())
            return .white
        else
            return .black;
    } else return null;
}

pub const options = &[_]parsley.Option{
    .{
        .name = "fullscreen",
        .name_short = null,
        .description = "use the fullscreen frontend",
        .arguments = &[_]parsley.Argument{},
    },
    .{
        .name = "affiliation",
        .name_short = 'a',
        .description = "set player affiliation, can be one of #i #b:white;, #b:black;, or #b:random;#i:off;",
        .arguments = &[_]parsley.Argument{.string},
    },
};
