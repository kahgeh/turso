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

    const errors_tests = b.addTest(.{
        .name = "errors-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/errors.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    errors_tests.root_module.addImport("turso", turso_module);
    errors_tests.root_module.addIncludePath(b.path("src"));
    errors_tests.root_module.addObjectFile(sdk_kit_archive);
    errors_tests.root_module.linkSystemLibrary("c", .{});
    errors_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&errors_tests.step);
    const run_errors_tests = b.addRunArtifact(errors_tests);

    const file_backed_tests = b.addTest(.{
        .name = "file-backed-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/file_backed.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    file_backed_tests.root_module.addImport("turso", turso_module);
    file_backed_tests.root_module.addIncludePath(b.path("src"));
    file_backed_tests.root_module.addObjectFile(sdk_kit_archive);
    file_backed_tests.root_module.linkSystemLibrary("c", .{});
    file_backed_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&file_backed_tests.step);
    const run_file_backed_tests = b.addRunArtifact(file_backed_tests);

    const encryption_tests = b.addTest(.{
        .name = "encryption-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/encryption.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    encryption_tests.root_module.addImport("turso", turso_module);
    encryption_tests.root_module.addIncludePath(b.path("src"));
    encryption_tests.root_module.addObjectFile(sdk_kit_archive);
    encryption_tests.root_module.linkSystemLibrary("c", .{});
    encryption_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&encryption_tests.step);
    const run_encryption_tests = b.addRunArtifact(encryption_tests);

    const contention_tests = b.addTest(.{
        .name = "contention-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/contention.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    contention_tests.root_module.addImport("turso", turso_module);
    contention_tests.root_module.addIncludePath(b.path("src"));
    contention_tests.root_module.addObjectFile(sdk_kit_archive);
    contention_tests.root_module.linkSystemLibrary("c", .{});
    contention_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&contention_tests.step);
    const run_contention_tests = b.addRunArtifact(contention_tests);

    const async_io_tests = b.addTest(.{
        .name = "async-io-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/async_io.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    async_io_tests.root_module.addImport("turso", turso_module);
    async_io_tests.root_module.addIncludePath(b.path("src"));
    async_io_tests.root_module.addObjectFile(sdk_kit_archive);
    async_io_tests.root_module.linkSystemLibrary("c", .{});
    async_io_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&async_io_tests.step);
    const run_async_io_tests = b.addRunArtifact(async_io_tests);

    const high_level_tests = b.addTest(.{
        .name = "high-level-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/high_level.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    high_level_tests.root_module.addImport("turso", turso_module);
    high_level_tests.root_module.addIncludePath(b.path("src"));
    high_level_tests.root_module.addObjectFile(sdk_kit_archive);
    high_level_tests.root_module.linkSystemLibrary("c", .{});
    high_level_tests.root_module.linkFramework("CoreFoundation", .{});
    b.default_step.dependOn(&high_level_tests.step);
    const run_high_level_tests = b.addRunArtifact(high_level_tests);

    const test_step = b.step("test", "Run Zig binding tests");
    test_step.dependOn(&run_root_tests.step);
    test_step.dependOn(&run_basic_tests.step);
    test_step.dependOn(&run_params_tests.step);
    test_step.dependOn(&run_metadata_tests.step);
    test_step.dependOn(&run_multi_statement_tests.step);
    test_step.dependOn(&run_regression_tests.step);
    test_step.dependOn(&run_types_tests.step);
    test_step.dependOn(&run_errors_tests.step);
    test_step.dependOn(&run_file_backed_tests.step);
    test_step.dependOn(&run_encryption_tests.step);
    test_step.dependOn(&run_contention_tests.step);
    test_step.dependOn(&run_async_io_tests.step);
    test_step.dependOn(&run_high_level_tests.step);
}
