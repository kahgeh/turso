const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdk_kit_archive = b.path("../../target/debug/libturso_sdk_kit.a");

    const turso_module = b.addModule("turso", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    turso_module.addIncludePath(b.path("src"));
    turso_module.addObjectFile(sdk_kit_archive);
    turso_module.linkSystemLibrary("c", .{});
    turso_module.linkFramework("CoreFoundation", .{});

    const root_tests = b.addTest(.{
        .name = "root-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    root_tests.root_module.addIncludePath(b.path("src"));
    root_tests.root_module.addObjectFile(sdk_kit_archive);
    root_tests.root_module.linkSystemLibrary("c", .{});
    root_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&root_tests.step);
    const run_root_tests = b.addRunArtifact(root_tests);

    const basic_tests = b.addTest(.{
        .name = "basic-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/basic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    basic_tests.root_module.addImport("turso", turso_module);
    basic_tests.root_module.addIncludePath(b.path("src"));
    basic_tests.root_module.addObjectFile(sdk_kit_archive);
    basic_tests.root_module.linkSystemLibrary("c", .{});
    basic_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&basic_tests.step);
    const run_basic_tests = b.addRunArtifact(basic_tests);

    const test_step = b.step("test", "Run Zig binding tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_basic_tests.step);
}
