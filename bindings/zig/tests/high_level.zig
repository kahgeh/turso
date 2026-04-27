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

test "default local builder and prepare use zero-terminated fast paths" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    try std.testing.expectEqual(@as(u64, 0), try opened.connection.execute("CREATE TABLE t(value TEXT)"));
    var stmt = try opened.connection.prepareSingle("INSERT INTO t(value) VALUES (?1)");
    defer {
        stmt.finalize() catch {};
        stmt.deinit();
    }
    try stmt.bindText(1, "fast");
    try std.testing.expectEqual(@as(u64, 1), try stmt.execute());

    var query = try opened.connection.prepareSingle("SELECT value FROM t");
    defer {
        query.finalize() catch {};
        query.deinit();
    }
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query.step());
    const value = try query.rowValueText(0);
    defer allocator.free(value);
    try std.testing.expectEqualStrings("fast", value);
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try query.step());

    const dynamic_sql = try std.fmt.allocPrint(allocator, "SELECT value FROM t", .{});
    defer allocator.free(dynamic_sql);

    var dynamic_query = try opened.connection.prepareSingle(dynamic_sql);
    defer {
        dynamic_query.finalize() catch {};
        dynamic_query.deinit();
    }
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try dynamic_query.step());
    const dynamic_value = try dynamic_query.rowValueText(0);
    defer allocator.free(dynamic_value);
    try std.testing.expectEqualStrings("fast", dynamic_value);
}

test "execute batch and query collect owned rows" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").build();
    defer opened.deinit();

    var conn = try opened.connect();
    defer conn.deinit();

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

test "rows streams borrowed row views" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    _ = try opened.connection.executeBatch(
        "CREATE TABLE t(id INTEGER PRIMARY KEY, value TEXT, payload BLOB); " ++
            "INSERT INTO t(value, payload) VALUES ('alpha', x'0102'), ('beta', x'0304');",
    );

    var rows = try opened.connection.rows("SELECT id, value, payload FROM t ORDER BY id");
    defer rows.deinit();

    const first = (try rows.next()).?;
    try std.testing.expectEqual(@as(usize, 3), first.len());
    try std.testing.expectEqual(@as(i64, 1), try first.int(0));
    try std.testing.expectEqualStrings("alpha", try first.text(1));
    try std.testing.expectEqualSlices(u8, &.{ 0x01, 0x02 }, try first.blob(2));

    const second = (try rows.next()).?;
    try std.testing.expectEqual(@as(i64, 2), try second.int(0));
    try std.testing.expectEqualStrings("beta", try second.text(1));
    try std.testing.expectEqualSlices(u8, &.{ 0x03, 0x04 }, try second.blob(2));

    try std.testing.expectEqual(null, try rows.next());
    try std.testing.expectEqual(null, try rows.next());
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

test "pragma statements can be queried and updated through connection helpers" {
    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    var journal_mode = try opened.connection.query("PRAGMA journal_mode");
    defer journal_mode.deinit();

    try std.testing.expectEqual(@as(usize, 1), journal_mode.rows.len);
    try std.testing.expectEqual(turso.val.ValueKind.text, std.meta.activeTag(journal_mode.rows[0].values[0]));
    try std.testing.expect(journal_mode.rows[0].values[0].text.len > 0);

    _ = try opened.connection.execute("PRAGMA user_version = 37");

    var user_version = try opened.connection.query("PRAGMA user_version");
    defer user_version.deinit();

    try std.testing.expectEqual(@as(usize, 1), user_version.rows.len);
    try std.testing.expectEqual(@as(i64, 37), user_version.rows[0].values[0].integer);
}

test "query rows can be mapped into caller-owned structs after transaction commit" {
    const User = struct {
        email: []const u8,
        age: i64,
    };

    const allocator = std.testing.allocator;

    var opened = try turso.Builder.newLocal(allocator, ":memory:").connect();
    defer opened.deinit();

    _ = try opened.connection.execute("CREATE TABLE users(email TEXT, age INTEGER)");

    var tx = try opened.connection.transaction();
    try std.testing.expectEqual(@as(u64, 1), try tx.execute("INSERT INTO users(email, age) VALUES ('foo@example.com', 21)"));
    try std.testing.expectEqual(@as(u64, 1), try tx.execute("INSERT INTO users(email, age) VALUES ('bar@example.com', 22)"));
    try tx.commit();

    var result = try opened.connection.query("SELECT email, age FROM users WHERE email LIKE '%@example.com' ORDER BY age");
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.rows.len);

    const first = User{
        .email = result.rows[0].values[0].text,
        .age = result.rows[0].values[1].integer,
    };
    const second = User{
        .email = result.rows[1].values[0].text,
        .age = result.rows[1].values[1].integer,
    };

    try std.testing.expectEqualStrings("foo@example.com", first.email);
    try std.testing.expectEqual(@as(i64, 21), first.age);
    try std.testing.expectEqualStrings("bar@example.com", second.email);
    try std.testing.expectEqual(@as(i64, 22), second.age);
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
