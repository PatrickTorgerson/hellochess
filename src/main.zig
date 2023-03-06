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

pub fn main() !void {
    var writer = zcon.Writer.init();
    defer writer.flush();

    if (!try parseCli(&writer)) {
        return;
    }

    if (use_fullscreen) {
        var frontend = FullscreenFrontend{ .frontend = Frontend.init() };
        try frontend.run(&writer);
    } else {
        var frontend = InlineFrontend{ .frontend = Frontend.init() };
        try frontend.run(&writer);
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

    return try cli.parse();
}

pub fn option(cli: *zcon.Cli) !bool {
    if (cli.isArg("fullscreen")) {
        use_fullscreen = true;
        return true;
    }
    return false;
}

pub fn input(cli: *zcon.Cli) !bool {
    _ = cli;
    return false;
}

pub fn help(cli: *zcon.Cli) !bool {
    cli.writer.put("\n== Usage\n\n#indent hellochess [--fullscreen]\n\n== Options\n\n");
    cli.writer.indent(1);
    cli.printOptionHelp();
    cli.writer.unindent(1);
    return false;
}
