// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");
const zcon = @import("zcon");
const network = @import("network");

const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");
const FullscreenFrontend = @import("frontend/Fullscreen.zig");
const Position = @import("hellochess/Position.zig");
const Affiliation = @import("hellochess/Piece.zig").Affiliation;

/// enumeration of cli commands
const Command = enum {
    host,
    join,
    play,
};

/// cli command specified
var command: Command = .play;
/// port used for host and join commands
var port: u16 = 0;
/// address used for join command
var addr: std.ArrayList(u8) = undefined;
/// whether to use the fullscreen frontend
var use_fullscreen: bool = false;
/// whether to enable dev commands in play command
var use_dev_commands: bool = false;
/// initial chess position for play command
var position = Position.init();
/// player affiliation for host command
var player_affiliation: Affiliation = .white;

pub fn main() !void {
    try network.init();
    defer network.deinit();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    addr = std.ArrayList(u8).init(allocator);
    defer addr.deinit();

    var writer = zcon.Writer.init();
    defer writer.flush();
    defer writer.useDefaultColors();

    // parse command line
    if (!try parseCli(&writer))
        return;

    switch (command) {
        .host => {
            var client = waitForClient(&writer) catch |err| {
                writer.fmt("failed to connect ({s})\n", .{@errorName(err)});
                return;
            };
            try runGame(&writer, Frontend.initNetwork(player_affiliation, client));
        },
        .join => {
            var sock = connectToHost(&writer, allocator) catch |err| {
                writer.fmt("failed to connect ({s})\n", .{@errorName(err)});
                return;
            };
            try runGame(&writer, Frontend.initNetwork(player_affiliation, sock));
        },
        .play => {
            const mode: Frontend.PlayMode = if (use_dev_commands) .development else .pass_and_play;
            try runGame(&writer, Frontend.init(mode, .white));
        },
    }
}

/// launch the game with parsed options
fn runGame(writer: *zcon.Writer, frontend: Frontend) !void {
    if (use_fullscreen) {
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
fn waitForClient(writer: *zcon.Writer) !network.Socket {
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
    const opponent = @intCast(u8, @enumToInt(player_affiliation.opponent()));
    _ = try client.send(&[_]u8{opponent});

    return client;
}

/// connect to host specified by addr and port
/// return resulting socket
fn connectToHost(writer: *zcon.Writer, allocator: std.mem.Allocator) !network.Socket {
    var sock = try network.connectToHost(allocator, addr.items, port, .tcp);
    errdefer sock.close();

    const endpoint = try sock.getRemoteEndPoint();
    writer.fmt("game connected at {}\n", .{endpoint});

    // recieve affiliation from host
    var affiliation: [1]u8 = undefined;
    const read = try sock.receive(&affiliation);

    if (read == 0)
        return error.SocketNotConnected;

    player_affiliation = @intToEnum(Affiliation, affiliation[0]);

    return sock;
}

/// parse command line, populating globals
fn parseCli(writer: *zcon.Writer) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var cli = try zcon.Cli.init(allocator, writer);
    defer cli.deinit();

    cli.option_callback = option;
    cli.input_callback = input;
    cli.help_callback = help;

    const command_str = cli.readString() orelse return true;

    if (std.mem.eql(u8, command_str, "help") or
        std.mem.eql(u8, command_str, "--help") or
        std.mem.eql(u8, command_str, "h") or
        std.mem.eql(u8, command_str, "-h") or
        std.mem.eql(u8, command_str, "--h"))
    {
        return try help(&cli);
    }

    const commands = std.enums.values(Command);
    for (commands[0..]) |cmd| {
        if (std.mem.eql(u8, command_str, @tagName(cmd))) {
            command = cmd;
            break;
        }
    } else {
        cli.writer.put("expected command: ");
        for (commands[0..]) |cmd|
            cli.writer.fmt("`{s}` ", .{@tagName(cmd)});
        cli.writer.put("\n");
        return false;
    }

    switch (command) {
        .host => {
            port = cli.readArg(u16) catch {
                cli.writer.put("invalid port\n");
                return false;
            } orelse {
                cli.writer.put("expected port\n");
                return false;
            };
            return try cli.parse(host_options);
        },
        .join => {
            const addr_str = cli.peekString() orelse {
                cli.writer.put("expected address\n");
                return false;
            };
            if (addr_str.len == 0 or addr_str[0] == '-') {
                cli.writer.put("expected address\n");
                return false;
            }
            cli.consumePeeked();

            var it = std.mem.split(u8, addr_str, ":");
            try addr.appendSlice(
                it.next() orelse {
                    writer.put("missing address\n");
                    return false;
                },
            );
            const port_str = it.next() orelse {
                writer.put("missing port\n");
                return false;
            };

            port = std.fmt.parseInt(u16, port_str, 10) catch {
                writer.put("invalid port\n");
                return false;
            };

            return try cli.parse(join_options);
        },
        .play => {
            return try cli.parse(play_options);
        },
    }
}

/// callback to handle command line options
fn option(cli: *zcon.Cli) !bool {

    // --fullscreen
    if (cli.isOption("fullscreen")) {
        use_fullscreen = true;
    }

    // --enable-dev-commands
    else if (cli.isOption("enable-dev-commands")) {
        use_dev_commands = true;
    }

    // --fen
    else if (cli.isOption("fen")) {
        const fen = cli.peekString() orelse {
            cli.writer.put("expected fen string\n");
            return false;
        };
        if (fen.len == 0 or fen[0] == '-') {
            cli.writer.put("expected fen string\n");
            return false;
        }
        cli.consumePeeked();
        position = Position.fromFen(fen) catch {
            cli.writer.put("invalid fen string\n");
            return false;
        };
    }

    // --affiliation, -a
    else if (cli.isOption("affiliation")) {
        const affiliation = cli.peekString() orelse {
            cli.writer.put("expected affiliation, white, black, or random\n");
            return false;
        };
        if (affiliation.len == 0 or affiliation[0] == '-') {
            cli.writer.put("expected affiliation, white, black, or random\n");
            return false;
        }
        cli.consumePeeked();
        if (std.mem.eql(u8, affiliation, "white"))
            player_affiliation = .white
        else if (std.mem.eql(u8, affiliation, "black"))
            player_affiliation = .black
        else if (std.mem.eql(u8, affiliation, "random")) {
            var rng = std.rand.DefaultPrng.init((try std.time.Instant.now()).timestamp);
            if (rng.random().boolean())
                player_affiliation = .white
            else
                player_affiliation = .black;
        }
    }
    return true;
}

/// callback to handle non option commandline args
fn input(cli: *zcon.Cli) !bool {
    cli.writer.fmt("unexpected arg `{s}`\n", .{cli.current_arg});
    return false;
}

/// callback to handle help options
fn help(cli: *zcon.Cli) !bool {
    cli.writer.put("\n#yel ==== Usage ====#prv\n\n");
    cli.writer.indent(1);
    cli.writer.put("hellochess (help|h)\n#indent#dgry display this help message#prv\n");
    cli.writer.put("hellochess play [options]\n#indent#dgry start pass and play game#prv\n");
    cli.writer.put("hellochess host <PORT> [options]\n#indent#dgry host peer to peer game#prv\n");
    cli.writer.put("hellochess join <ADDRESS>:<PORT> [options]\n#indent#dgry join peer to peer game#prv\n");
    cli.writer.put("\n#cyn;NOTE:#prv; not all options are available for all commands\n");
    cli.writer.unindent(1);

    cli.writer.put("\n#yel ==== Options ====#prv\n\n");
    cli.writer.indent(1);
    cli.printOptionHelp(all_options);
    cli.writer.put("--help, --h, -help, -h\n#indent#dgry display this help message#prv\n");
    cli.writer.unindent(1);
    cli.writer.putChar('\n');
    return false;
}

const host_options = zcon.Cli.OptionList(.{
    opt_affiliation,
    opt_fullscreen,
});

const join_options = zcon.Cli.OptionList(.{
    opt_fullscreen,
});

const play_options = zcon.Cli.OptionList(.{
    opt_fullscreen,
    opt_dev,
    opt_fen,
});

const all_options = zcon.Cli.OptionList(.{
    opt_affiliation,
    opt_fullscreen,
    opt_dev,
    opt_fen,
});

const opt_fullscreen = zcon.Cli.Option{
    .alias_long = "fullscreen",
    .alias_short = "",
    .desc = "#dgry use the fullscreen frontend",
    .help = "not sure this is used atm",
};
const opt_dev = zcon.Cli.Option{
    .alias_long = "enable-dev-commands",
    .alias_short = "",
    .desc = "#dgry enable access to dev commands, also disables draws by insufficient materal",
    .help = "not sure this is used atm",
};
const opt_fen = zcon.Cli.Option{
    .alias_long = "fen",
    .alias_short = "",
    .desc = "#dgry load position from fen string #d:'#yel:<AFFILIATION>'",
    .arguments = "#d:'#yel:<AFFILIATION>'",
    .help = "not sure this is used atm",
};
const opt_affiliation = zcon.Cli.Option{
    .alias_long = "affiliation",
    .alias_short = "a",
    .arguments = "#d:'#yel:<AFFILIATION>'",
    .desc = "#dgry play as affiliation #d:'#yel:<AFFILIATION>'\n#d:'#yel:<AFFILIATION>'; can be one of #i:white;, #i:black;, or #i:random;",
    .help = "not sure this is used atm",
};
