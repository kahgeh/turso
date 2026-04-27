const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

fn openFileBacked(allocator: std.mem.Allocator, path: []const u8) !turso.db.Database {
    var db = turso.db.Database.init(allocator);
    try db.create(&.{
        .path = path,
    });
    return db;
}

fn releaseWriteLock(stmt: *turso.stmt.Statement) void {
    const ts = std.c.timespec{
        .sec = 0,
        .nsec = 50 * std.time.ns_per_ms,
    };
    _ = std.c.nanosleep(&ts, null);
    _ = stmt.execute(.{}) catch |err| {
        std.debug.panic("commit failed while releasing write lock: {}", .{err});
    };
}

test "busy timeout can be changed at runtime for later writes" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/contention.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    var db = try openFileBacked(allocator, db_path);
    defer db.deinit();

    var conn1 = try db.connect();
    defer conn1.deinit();

    var conn2 = try db.connect();
    defer conn2.deinit();

    var setup_stmt = try support.prepare(allocator, &conn1, "CREATE TABLE t(id INTEGER PRIMARY KEY, value INTEGER)");
    defer setup_stmt.deinit();
    _ = try setup_stmt.stmt.execute(.{});

    var insert_stmt = try support.prepare(allocator, &conn1, "INSERT INTO t(id, value) VALUES (1, 0)");
    defer insert_stmt.deinit();
    try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute(.{}));

    var begin_stmt = try support.prepare(allocator, &conn1, "BEGIN IMMEDIATE");
    defer begin_stmt.deinit();
    _ = try begin_stmt.stmt.execute(.{});

    try conn2.setBusyTimeout(0);
    var first_update = try support.prepare(allocator, &conn2, "UPDATE t SET value = value + 1 WHERE id = 1");
    defer first_update.deinit();
    try std.testing.expectError(error.Busy, first_update.stmt.execute(.{}));

    try conn2.setBusyTimeout(250);
    var commit_stmt = try support.prepare(allocator, &conn1, "COMMIT");
    defer commit_stmt.deinit();
    const releaser = try std.Thread.spawn(.{}, releaseWriteLock, .{&commit_stmt.stmt});
    defer releaser.join();

    var second_update = try support.prepare(allocator, &conn2, "UPDATE t SET value = value + 1 WHERE id = 1");
    defer second_update.deinit();
    try std.testing.expectEqual(@as(u64, 1), try second_update.stmt.execute(.{}));

    var verify_stmt = try support.prepare(allocator, &conn2, "SELECT value FROM t WHERE id = 1");
    defer verify_stmt.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try verify_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 1), verify_stmt.stmt.rowValueInt(0));
}
