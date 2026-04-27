const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_lib_dir = b.option(
        []const u8,
        "native-lib-dir",
        "Directory containing libturso_sdk_kit.a and libturso_sync_sdk_kit.a",
    ) orelse "../../../target/debug";

    const turso_module = b.addModule("turso", .{
        .root_source_file = b.path("../../../bindings/zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdk_kit_archive = b.path(b.fmt("{s}/libturso_sdk_kit.a", .{native_lib_dir}));
    const sync_sdk_kit_archive = b.path(b.fmt("{s}/libturso_sync_sdk_kit.a", .{native_lib_dir}));

    turso_module.addIncludePath(b.path("../../../sdk-kit"));
    turso_module.addIncludePath(b.path("../../../sync/sdk-kit"));
    turso_module.addObjectFile(sdk_kit_archive);
    turso_module.addObjectFile(sync_sdk_kit_archive);
    turso_module.linkSystemLibrary("c", .{});
    turso_module.linkFramework("CoreFoundation", .{});

    const exe = b.addExecutable(.{
        .name = "binding-bench-zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("turso", turso_module);
    exe.root_module.addIncludePath(b.path("../../../sdk-kit"));
    exe.root_module.addIncludePath(b.path("../../../sync/sdk-kit"));
    exe.root_module.addObjectFile(sdk_kit_archive);
    exe.root_module.addObjectFile(sync_sdk_kit_archive);
    exe.root_module.linkSystemLibrary("c", .{});
    exe.root_module.linkFramework("CoreFoundation", .{});

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);

    const run_step = b.step("run", "Run binding benchmark");
    run_step.dependOn(&run.step);
}
