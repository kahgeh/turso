const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    // The Zig binding consumes the Rust static archive directly from the workspace build.
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

    const params_tests = b.addTest(.{
        .name = "params-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/params.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    params_tests.root_module.addImport("turso", turso_module);
    params_tests.root_module.addIncludePath(b.path("src"));
    params_tests.root_module.addObjectFile(sdk_kit_archive);
    params_tests.root_module.linkSystemLibrary("c", .{});
    params_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&params_tests.step);
    const run_params_tests = b.addRunArtifact(params_tests);

    const metadata_tests = b.addTest(.{
        .name = "metadata-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/metadata.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    metadata_tests.root_module.addImport("turso", turso_module);
    metadata_tests.root_module.addIncludePath(b.path("src"));
    metadata_tests.root_module.addObjectFile(sdk_kit_archive);
    metadata_tests.root_module.linkSystemLibrary("c", .{});
    metadata_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&metadata_tests.step);
    const run_metadata_tests = b.addRunArtifact(metadata_tests);

    const multi_statement_tests = b.addTest(.{
        .name = "multi-statement-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/multi_statement.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    multi_statement_tests.root_module.addImport("turso", turso_module);
    multi_statement_tests.root_module.addIncludePath(b.path("src"));
    multi_statement_tests.root_module.addObjectFile(sdk_kit_archive);
    multi_statement_tests.root_module.linkSystemLibrary("c", .{});
    multi_statement_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&multi_statement_tests.step);
    const run_multi_statement_tests = b.addRunArtifact(multi_statement_tests);

    const regression_tests = b.addTest(.{
        .name = "regression-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/regressions.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    regression_tests.root_module.addImport("turso", turso_module);
    regression_tests.root_module.addIncludePath(b.path("src"));
    regression_tests.root_module.addObjectFile(sdk_kit_archive);
    regression_tests.root_module.linkSystemLibrary("c", .{});
    regression_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&regression_tests.step);
    const run_regression_tests = b.addRunArtifact(regression_tests);

    const types_tests = b.addTest(.{
        .name = "types-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/types.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    types_tests.root_module.addImport("turso", turso_module);
    types_tests.root_module.addIncludePath(b.path("src"));
    types_tests.root_module.addObjectFile(sdk_kit_archive);
    types_tests.root_module.linkSystemLibrary("c", .{});
    types_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&types_tests.step);
    const run_types_tests = b.addRunArtifact(types_tests);

    const test_step = b.step("test", "Run Zig binding tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_basic_tests.step);
    test_step.dependOn(&run_params_tests.step);
    test_step.dependOn(&run_metadata_tests.step);
    test_step.dependOn(&run_multi_statement_tests.step);
    test_step.dependOn(&run_regression_tests.step);
    test_step.dependOn(&run_types_tests.step);
}
