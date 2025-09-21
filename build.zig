
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const sqlite = b.dependency("sqlite", .{
        .target = target,
        .optimize = optimize });

    const exec = b.addExecutable(.{
        .name = "sqlite3-cli",
        .root_source_file = b.path("Sources/main.zig"),
        .target = target,
        .optimize = optimize });
    exec.root_module.addImport("sqlite3", sqlite.module("sqlite"));
    b.installArtifact(exec);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("Sources/tests.zig"),
            .target = target,
            .optimize = optimize })
    });
    tests.root_module.addImport("sqlite3", sqlite.module("sqlite"));
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "use-case tests");
    test_step.dependOn(&run_tests.step);

    const docs = b.addInstallDirectory(.{
        .source_dir = tests.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs" });
    const docs_step = b.step("docs", "generate docs");
    docs_step.dependOn(&docs.step);
}
