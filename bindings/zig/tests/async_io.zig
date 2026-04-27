const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

fn openAsyncFileBacked(allocator: std.mem.Allocator, path: []const u8) !turso.db.Database {
    var db = turso.db.Database.init(allocator);
    try db.create(&.{
        .path = path,
        .async_io = true,
    });
    return db;
}

test "async io databases retry execute and step transparently" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/async-io.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    var db = try openAsyncFileBacked(allocator, db_path);
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    var create_stmt = try support.prepare(allocator, &conn, "CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var insert_stmt = try support.prepare(allocator, &conn, "INSERT INTO t(value) VALUES ('alpha')");
    defer insert_stmt.deinit();
    try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute());

    var select_stmt = try support.prepare(allocator, &conn, "SELECT value FROM t WHERE id = 1");
    defer select_stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try select_stmt.stmt.step());
    const value = try select_stmt.stmt.rowValueText(0);
    defer allocator.free(value);
    try std.testing.expectEqualStrings("alpha", value);
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try select_stmt.stmt.step());
}

test "async io can be driven explicitly" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/explicit-async-io.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    var db = try openAsyncFileBacked(allocator, db_path);
    defer db.deinit();

    var conn = try db.connect();
    defer conn.deinit();

    var create_stmt = try support.prepare(allocator, &conn, "CREATE TABLE t(value TEXT)");
    defer create_stmt.deinit();

    while (true) {
        const result = try create_stmt.stmt.executeOnce();
        switch (result.status_code) {
            .TURSO_IO => try create_stmt.stmt.runIO(),
            .TURSO_OK, .TURSO_DONE => break,
            else => return error.TestUnexpectedResult,
        }
    }

    var insert_stmt = try support.prepare(allocator, &conn, "INSERT INTO t(value) VALUES ('explicit')");
    defer insert_stmt.deinit();
    _ = try insert_stmt.stmt.execute();

    var select_stmt = try support.prepare(allocator, &conn, "SELECT value FROM t");
    defer select_stmt.deinit();

    while (true) {
        switch (try select_stmt.stmt.stepOnce()) {
            .TURSO_IO => try select_stmt.stmt.runIO(),
            .TURSO_ROW => break,
            .TURSO_DONE => return error.TestUnexpectedResult,
            else => return error.TestUnexpectedResult,
        }
    }

    const value = try select_stmt.stmt.rowValueText(0);
    defer allocator.free(value);
    try std.testing.expectEqualStrings("explicit", value);
}
