// ********************************************************************************
//! https://github.com/PatrickTorgerson/hellochess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const zcon = @import("zcon");
const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");
const FullscreenFrontend = @import("frontend/Fullscreen.zig");

var use_fullscreen: bool = false;

pub fn main() !void {
    if (!try parse_cli()) {
        return;
    }

    if (use_fullscreen) {
        var frontend = FullscreenFrontend{ .frontend = Frontend.init() };
        try frontend.run();
    } else {
        var frontend = InlineFrontend{ .frontend = Frontend.init() };
        try frontend.run();
    }
}

pub fn parse_cli() !bool {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var allocator = arena.allocator();
    var cli = try zcon.Cli.init(allocator, option, input);
    defer cli.deinit();

    cli.help_callback = help;

    try cli.add_option(.{
        .alias_long = "fullscreen",
        .alias_short = "",
        .desc = "use the fullscreen frontend",
        .help = "not sure this is used atm",
    });

    return try cli.parse();
}

pub fn option(cli: *zcon.Cli) !bool {
    if (cli.is_arg("fullscreen")) {
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
    _ = cli.print_help();
    return false;
}
