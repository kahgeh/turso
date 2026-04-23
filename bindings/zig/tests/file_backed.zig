const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "file-backed databases reopen and share committed state" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/file-backed.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    {
        var db = turso.db.Database.init(allocator);
        try db.create(&.{ .path = db_path });
        defer db.deinit();

        const conn1 = try db.connect();
        defer {
            conn1.deinit();
            allocator.destroy(conn1);
        }

        const conn2 = try db.connect();
        defer {
            conn2.deinit();
            allocator.destroy(conn2);
        }

        var create_stmt = try support.prepare(allocator, conn1, "CREATE TABLE t(id INTEGER PRIMARY KEY, name TEXT)");
        defer create_stmt.deinit();
        _ = try create_stmt.stmt.execute();

        var insert_stmt = try support.prepare(allocator, conn1, "INSERT INTO t(name) VALUES ('alice')");
        defer insert_stmt.deinit();
        try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute());

        var count_stmt = try support.prepare(allocator, conn2, "SELECT COUNT(*) FROM t");
        defer count_stmt.deinit();
        try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
        try std.testing.expectEqual(@as(i64, 1), count_stmt.stmt.rowValueInt(0));
        try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try count_stmt.stmt.step());
    }

    {
        var db = turso.db.Database.init(allocator);
        try db.create(&.{ .path = db_path });
        defer db.deinit();

        const conn = try db.connect();
        defer {
            conn.deinit();
            allocator.destroy(conn);
        }

        var count_stmt = try support.prepare(allocator, conn, "SELECT COUNT(*) FROM t");
        defer count_stmt.deinit();
        try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
        try std.testing.expectEqual(@as(i64, 1), count_stmt.stmt.rowValueInt(0));
    }
}
