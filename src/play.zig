// *******************************************************
//  https://github.com/PatrickTorgerson/hellochess
//  Copyright (c) 2023 Patrick Torgerson
//  MIT license, see LICENSE for more information
// *******************************************************

const std = @import("std");
const zcon = @import("zcon");
const parsley = @import("parsley");

const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");
const FullscreenFrontend = @import("frontend/Fullscreen.zig");
const Position = @import("hellochess/Position.zig");

pub const command_sequence = "play";
pub const description_line = "start pass and play game";
pub const description_full = description_line;
pub const positionals = &[_]parsley.Positional{};

pub fn run(
    _: *void,
    _: std.mem.Allocator,
    writer: *zcon.Writer,
    _: parsley.Positionals(@This()),
    opts: parsley.Options(@This()),
) anyerror!void {
    const mode: Frontend.PlayMode = if (opts.@"enable-dev-commands") .development else .pass_and_play;
    const frontend = Frontend.init(mode, .white);
    const position = if (opts.fen) |fen|
        Position.fromFen(fen) catch {
            writer.put("invalid fen string\n");
            return;
        }
    else
        Position.init();

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

pub const options = &[_]parsley.Option{
    .{
        .name = "fullscreen",
        .name_short = null,
        .description = "use the fullscreen frontend",
        .arguments = &[_]parsley.Argument{},
    },
    .{
        .name = "enable-dev-commands",
        .name_short = null,
        .description = "enable access to dev commands, also disables draws by insufficient materal",
        .arguments = &[_]parsley.Argument{},
    },
    .{
        .name = "fen",
        .name_short = 'f',
        .description = "load position from fen string",
        .arguments = &[_]parsley.Argument{.string},
    },
};
