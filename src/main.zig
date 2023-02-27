// ********************************************************************************
//! https://github.com/PatrickTorgerson/hellochess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const zcon = @import("zcon");
const Frontend = @import("frontend/Frontend.zig");
const InlineFrontend = @import("frontend/Inline.zig");

pub fn main() !void {
    zcon.write("\n == Hello Chess ==\n #dgry '/exit' to quit , '/help' for more commands #def\n\n");
    var frontend = InlineFrontend{ .frontend = Frontend.init() };
    try frontend.run();
}
