// ********************************************************************************
//* https://github.com/PatrickTorgerson/hellochess
//* Copyright (c) 2022 Patrick Torgerson
//* MIT license, see LICENSE for more information
// ********************************************************************************

//! Here is the logic and main loop for the fullscreen front end
//! This front end uses a full alternate buffer

const std = @import("std");
const chess = @import("../hellochess.zig");
const zcon = @import("zcon");

const Frontend = @import("Frontend.zig");

frontend: Frontend,

pub fn run() !void {
    zcon.alternate_buffer();
    defer zcon.main_buffer();
}
