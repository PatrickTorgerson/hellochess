// ********************************************************************************
//! https://github.com/PatrickTorgerson/chess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const chess = @import("chess.zig");
const zcon = @import("zcon");
const inline_frontend = @import("inline-frontend.zig");

pub fn main() !void {
    zcon.write("\n == Hello Chess ==\n #dgry '/exit' to quit , '/help' for more commands #def\n\n");
    try inline_frontend.entry_point();
}
