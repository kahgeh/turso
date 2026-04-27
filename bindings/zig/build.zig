const std = @import("std");

const NativePaths = struct {
    sdk_include: std.Build.LazyPath,
    sync_include: std.Build.LazyPath,
    sdk_archive: std.Build.LazyPath,
    sync_archive: std.Build.LazyPath,
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const native_paths = resolveNativePaths(b);

    const turso_module = b.addModule("turso", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    linkTursoNative(turso_module, native_paths);

    const root_tests = b.addTest(.{
        .name = "root-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    linkTursoNative(root_tests.root_module, native_paths);
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
    linkTursoNative(basic_tests.root_module, native_paths);
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
    linkTursoNative(params_tests.root_module, native_paths);
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
    linkTursoNative(metadata_tests.root_module, native_paths);
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
    linkTursoNative(multi_statement_tests.root_module, native_paths);
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
    linkTursoNative(regression_tests.root_module, native_paths);
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
    linkTursoNative(types_tests.root_module, native_paths);
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
    linkTursoNative(errors_tests.root_module, native_paths);
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
    linkTursoNative(file_backed_tests.root_module, native_paths);
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
    linkTursoNative(encryption_tests.root_module, native_paths);
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
    linkTursoNative(contention_tests.root_module, native_paths);
    b.default_step.dependOn(&contention_tests.step);
    const run_contention_tests = b.addRunArtifact(contention_tests);

    const mvcc_tests = b.addTest(.{
        .name = "mvcc-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/mvcc.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    mvcc_tests.root_module.addImport("turso", turso_module);
    linkTursoNative(mvcc_tests.root_module, native_paths);
    b.default_step.dependOn(&mvcc_tests.step);
    const run_mvcc_tests = b.addRunArtifact(mvcc_tests);

    const async_io_tests = b.addTest(.{
        .name = "async-io-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/async_io.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    async_io_tests.root_module.addImport("turso", turso_module);
    linkTursoNative(async_io_tests.root_module, native_paths);
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
    linkTursoNative(high_level_tests.root_module, native_paths);
    b.default_step.dependOn(&high_level_tests.step);
    const run_high_level_tests = b.addRunArtifact(high_level_tests);

    const sync_config_tests = b.addTest(.{
        .name = "sync-config-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sync_config.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sync_config_tests.root_module.addImport("turso", turso_module);
    linkTursoNative(sync_config_tests.root_module, native_paths);
    b.default_step.dependOn(&sync_config_tests.step);
    const run_sync_config_tests = b.addRunArtifact(sync_config_tests);

    const sync_e2e_tests = b.addTest(.{
        .name = "sync-e2e-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/sync_e2e.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sync_e2e_tests.root_module.addImport("turso", turso_module);
    linkTursoNative(sync_e2e_tests.root_module, native_paths);
    b.default_step.dependOn(&sync_e2e_tests.step);
    const run_sync_e2e_tests = b.addRunArtifact(sync_e2e_tests);

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
    test_step.dependOn(&run_mvcc_tests.step);
    test_step.dependOn(&run_async_io_tests.step);
    test_step.dependOn(&run_high_level_tests.step);
    test_step.dependOn(&run_sync_config_tests.step);
    test_step.dependOn(&run_sync_e2e_tests.step);

    addPackageStep(b);
}

fn resolveNativePaths(b: *std.Build) NativePaths {
    const standalone = pathExists(b, "include/turso.h") and
        pathExists(b, "include/turso_sync.h") and
        pathExists(b, "lib/libturso_sdk_kit.a") and
        pathExists(b, "lib/libturso_sync_sdk_kit.a");

    if (standalone) {
        return .{
            .sdk_include = b.path("include"),
            .sync_include = b.path("include"),
            .sdk_archive = b.path("lib/libturso_sdk_kit.a"),
            .sync_archive = b.path("lib/libturso_sync_sdk_kit.a"),
        };
    }

    return .{
        .sdk_include = b.path("../../sdk-kit"),
        .sync_include = b.path("../../sync/sdk-kit"),
        .sdk_archive = b.path("../../target/debug/libturso_sdk_kit.a"),
        .sync_archive = b.path("../../target/debug/libturso_sync_sdk_kit.a"),
    };
}

fn pathExists(b: *std.Build, sub_path: []const u8) bool {
    b.build_root.handle.access(b.graph.io, sub_path, .{}) catch return false;
    return true;
}

fn linkTursoNative(module: *std.Build.Module, paths: NativePaths) void {
    module.addIncludePath(paths.sdk_include);
    module.addIncludePath(paths.sync_include);
    module.addObjectFile(paths.sdk_archive);
    module.addObjectFile(paths.sync_archive);
    module.linkSystemLibrary("c", .{});
    module.linkFramework("CoreFoundation", .{});
}

fn addPackageStep(b: *std.Build) void {
    const version = b.option([]const u8, "package-version", "Version suffix for the standalone package tarball") orelse "local";
    const package_name = b.fmt("turso-zig-{s}", .{version});
    const archive_path = b.fmt("zig-pkg/{s}.tar.gz", .{package_name});

    const build_sdk = b.addSystemCommand(&.{
        "cargo",
        "build",
        "--manifest-path",
        b.pathFromRoot("../../Cargo.toml"),
        "--package",
        "turso_sdk_kit",
        "--lib",
    });
    const build_sync_sdk = b.addSystemCommand(&.{
        "cargo",
        "build",
        "--manifest-path",
        b.pathFromRoot("../../Cargo.toml"),
        "--package",
        "turso_sync_sdk_kit",
        "--lib",
    });

    const package_files = b.addWriteFiles();
    _ = package_files.addCopyFile(b.path("README.md"), "README.md");
    _ = package_files.addCopyFile(b.path("build.zig"), "build.zig");
    _ = package_files.addCopyFile(b.path("build.zig.zon"), "build.zig.zon");
    _ = package_files.addCopyDirectory(b.path("src"), "src", .{});
    _ = package_files.addCopyDirectory(b.path("tests"), "tests", .{});
    _ = package_files.addCopyFile(b.path("../../sdk-kit/turso.h"), "include/turso.h");
    _ = package_files.addCopyFile(b.path("../../sync/sdk-kit/turso_sync.h"), "include/turso_sync.h");
    _ = package_files.addCopyFile(b.path("../../target/debug/libturso_sdk_kit.a"), "lib/libturso_sdk_kit.a");
    _ = package_files.addCopyFile(b.path("../../target/debug/libturso_sync_sdk_kit.a"), "lib/libturso_sync_sdk_kit.a");
    package_files.step.dependOn(&build_sdk.step);
    package_files.step.dependOn(&build_sync_sdk.step);

    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", b.pathFromRoot("zig-pkg") });

    const tar = b.addSystemCommand(&.{ "tar", "-czf", archive_path, "-C" });
    tar.setCwd(b.path("."));
    tar.addDirectoryArg(package_files.getDirectory());
    tar.addArg(".");
    tar.step.dependOn(&mkdir.step);

    const package_step = b.step("package", "Build a standalone Zig package tarball");
    package_step.dependOn(&tar.step);
}
