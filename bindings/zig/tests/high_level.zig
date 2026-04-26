const std = @import("std");
const turso = @import("turso");

test "builder opens database and connect convenience owns lifecycle" {
    const allocator = std.testing.allocator;

    var opened = try turso.db
        .newLocal(allocator, ":memory:")
        .withVfs("memory")
        .connect();
    defer opened.deinit();

    try std.testing.expect(opened.connection.getAutocommit());
    try std.testing.expectEqual(@as(u64, 0), try opened.connection.execute("CREATE TABLE t(value TEXT)"));
    try std.testing.expectEqual(@as(u64, 1), try opened.connection.execute("INSERT INTO t(value) VALUES ('builder')"));
}

test "execute batch and query collect owned rows" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer opened.deinit();

    const conn = try opened.connect();
    defer {
        conn.deinit();
        allocator.destroy(conn);
    }

    try std.testing.expectEqual(
        @as(u64, 2),
        try conn.executeBatch(
            "CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT, payload BLOB); " ++
                "INSERT INTO t(value, payload) VALUES ('alpha', x'0102'), ('beta', x'0304');",
        ),
    );

    var result = try conn.query("SELECT id, value, payload, NULL FROM t ORDER BY id");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 4), result.columns.len);
    try std.testing.expectEqualStrings("id", result.columns[0].name);
    try std.testing.expectEqual(@as(usize, 2), result.rows.len);

    try std.testing.expectEqual(@as(i64, 1), result.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("alpha", result.rows[0].values[1].text);
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, result.rows[0].values[2].blob);
    try std.testing.expectEqual(turso.val.ValueKind.null, std.meta.activeTag(result.rows[0].values[3]));

    try std.testing.expectEqual(@as(i64, 2), result.rows[1].values[0].integer);
    try std.testing.expectEqualStrings("beta", result.rows[1].values[1].text);
    try std.testing.expectEqualSlices(u8, &.{ 0x03, 0x04 }, result.rows[1].values[2].blob);
}

test "transaction wrapper commits and rolls back explicitly" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    _ = try opened.connection.execute("CREATE TABLE t(value INTEGER)");

    var committed = try opened.connection.transaction();
    try std.testing.expect(!opened.connection.getAutocommit());
    try std.testing.expectEqual(@as(u64, 1), try committed.execute("INSERT INTO t(value) VALUES (1)"));
    try committed.commit();
    try std.testing.expect(opened.connection.getAutocommit());

    var rolled_back = try opened.connection.transaction();
    try std.testing.expectEqual(@as(u64, 1), try rolled_back.execute("INSERT INTO t(value) VALUES (2)"));
    try rolled_back.rollback();
    try std.testing.expect(opened.connection.getAutocommit());

    var result = try opened.connection.query("SELECT value FROM t ORDER BY value");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.rows[0].values[0].integer);
}

test "async io builder keeps statement retry helpers transparent" {
    const allocator = std.testing.allocator;
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const db_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/high-level-async.db",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(db_path);

    var opened = try turso.Builder
        .newLocal(allocator, db_path)
        .withAsyncIO(true)
        .connect();
    defer opened.deinit();

    _ = try opened.connection.execute("CREATE TABLE t(value TEXT)");
    _ = try opened.connection.execute("INSERT INTO t(value) VALUES ('async')");

    var result = try opened.connection.query("SELECT value FROM t");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.rows.len);
    try std.testing.expectEqualStrings("async", result.rows[0].values[0].text);
}
