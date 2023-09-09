// ********************************************************************************
//! https://github.com/PatrickTorgerson/chess
//! Copyright (c) 2022 Patrick Torgerson
//! MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcon_module = b.dependency("zcon", .{}).module("zcon");
    const network_module = b.dependency("network", .{}).module("network");

    const exe = b.addExecutable(.{
        .name = "hellochess",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.addModule("zcon", zcon_module);
    exe.addModule("network", network_module);
    if (builtin.os.tag != .windows) {
        exe.linkSystemLibrary("c");
    }
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
