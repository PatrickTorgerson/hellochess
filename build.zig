// ********************************************************************************
//! https://github.com/PatrickTorgerson/chess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const zcon = @import("src/zcon/build.zig");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const zcon_module = zcon.module(b);
    const network_module = b.addModule("network", .{
        .source_file = .{ .path = "src/zig-network/network.zig" },
    });

    const exe = b.addExecutable(.{
        .name = "hellochess",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("zcon", zcon_module);
    exe.addModule("network", network_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest(.{
        .name = "hellotests",
        .root_source_file = .{ .path = "src/hellochess.zig" },
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe_tests);
    const test_run_cmd = b.addRunArtifact(exe_tests);
    test_run_cmd.step.dependOn(b.getInstallStep());
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&test_run_cmd.step);
}
