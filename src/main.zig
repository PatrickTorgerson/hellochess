// ********************************************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2022 Patrick Torgerson
//  MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const zcon = @import("zcon");
const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");
const FullscreenFrontend = @import("frontend/Fullscreen.zig");

var use_fullscreen: bool = false;
var use_dev_commands: bool = false;

pub fn main() !void {
    var writer = zcon.Writer.init();
    defer writer.flush();
    defer writer.useDefaultColors();

    // parse command line
    const parse_success = parseCli(&writer) catch |err| {
        switch (err) {
            // it would be cool if we could get the option name here :/
            error.unrecognized_option => writer.put("\n#red unrecognized option\n"),
            else => return err,
        }
        return;
    };
    if (!parse_success) return;

    if (use_fullscreen) {
        var fullscreen = FullscreenFrontend{ .frontend = Frontend.passAndPlay(use_dev_commands) };
        try fullscreen.run(&writer);
    } else {
        var @"inline" = InlineFrontend{ .frontend = Frontend.passAndPlay(use_dev_commands) };
        try @"inline".run(&writer);
    }
}

pub fn parseCli(writer: *zcon.Writer) !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();

    var cli = try zcon.Cli.init(allocator, writer, option, input);
    defer cli.deinit();

    cli.help_callback = help;

    try cli.addOption(.{
        .alias_long = "fullscreen",
        .alias_short = "",
        .desc = "use the fullscreen frontend",
        .help = "not sure this is used atm",
    });
    try cli.addOption(.{
        .alias_long = "enable-dev-commands",
        .alias_short = "",
        .desc = "enable access to dev commands",
        .help = "not sure this is used atm",
    });

    return try cli.parse();
}

/// callback to handle command line options
pub fn option(cli: *zcon.Cli) !bool {
    if (cli.isArg("fullscreen")) {
        use_fullscreen = true;
        return true;
    } else if (cli.isArg("enable-dev-commands")) {
        use_dev_commands = true;
        // TODO: incompatable with network play
        return true;
    }
    return false;
}

/// callback to handle non option commandline args
pub fn input(cli: *zcon.Cli) !bool {
    _ = cli;
    return false;
}

/// callback to handle help options
pub fn help(cli: *zcon.Cli) !bool {
    cli.writer.put("\n==== Usage ====\n\n#indent hellochess [OPTIONS]\n\n==== Options ====\n\n");
    cli.writer.indent(1);
    cli.printOptionHelp();
    cli.writer.unindent(1);
    cli.writer.putChar('\n');
    return false;
}
