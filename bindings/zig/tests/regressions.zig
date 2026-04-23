const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "insert returning survives partial fetch after finalize" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INT)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a) VALUES (1),(2) RETURNING a");
    defer stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 1), stmt.stmt.rowValueInt(0));
    try stmt.finalize();

    var count_stmt = try support.prepare(allocator, fixture.conn, "SELECT COUNT(*) FROM t");
    defer count_stmt.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 2), count_stmt.stmt.rowValueInt(0));
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try count_stmt.stmt.step());
}

test "insert returning survives explicit transaction with partial fetch" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INT)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var begin_stmt = try support.prepare(allocator, fixture.conn, "BEGIN");
    defer begin_stmt.deinit();
    _ = try begin_stmt.stmt.execute();

    var stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a) VALUES (10),(20) RETURNING a");
    defer stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 10), stmt.stmt.rowValueInt(0));
    try stmt.finalize();

    var commit_stmt = try support.prepare(allocator, fixture.conn, "COMMIT");
    defer commit_stmt.deinit();
    _ = try commit_stmt.stmt.execute();

    var count_stmt = try support.prepare(allocator, fixture.conn, "SELECT COUNT(*) FROM t");
    defer count_stmt.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 2), count_stmt.stmt.rowValueInt(0));
}

test "on conflict do nothing returning yields no rows" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INT PRIMARY KEY)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var insert_stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a) VALUES(1)");
    defer insert_stmt.deinit();
    _ = try insert_stmt.stmt.execute();

    var stmt = try support.prepare(
        allocator,
        fixture.conn,
        "INSERT INTO t(a) VALUES(1) ON CONFLICT(a) DO NOTHING RETURNING a",
    );
    defer stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try stmt.stmt.step());

    var count_stmt = try support.prepare(allocator, fixture.conn, "SELECT COUNT(*) FROM t");
    defer count_stmt.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 1), count_stmt.stmt.rowValueInt(0));
}

test "subqueries joins alter table generate_series and json helpers" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t(a INT)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var insert_stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO t(a) VALUES (1),(2),(3),(4)");
    defer insert_stmt.deinit();
    _ = try insert_stmt.stmt.execute();

    var subquery_stmt = try support.prepare(
        allocator,
        fixture.conn,
        "SELECT a FROM (SELECT a FROM t WHERE a > 1) WHERE a < 4 ORDER BY a",
    );
    defer subquery_stmt.deinit();

    var subquery_rows = std.array_list.Managed(i64).init(allocator);
    defer subquery_rows.deinit();
    while (true) {
        switch (try subquery_stmt.stmt.step()) {
            .TURSO_ROW => try subquery_rows.append(subquery_stmt.stmt.rowValueInt(0)),
            .TURSO_DONE => break,
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expectEqualSlices(i64, &.{ 2, 3 }, subquery_rows.items);

    var join_schema = try support.prepare(allocator, fixture.conn, "CREATE TABLE t1(id INT PRIMARY KEY, name TEXT)");
    defer join_schema.deinit();
    _ = try join_schema.stmt.execute();
    var join_schema2 = try support.prepare(allocator, fixture.conn, "CREATE TABLE t2(id INT PRIMARY KEY, age INT)");
    defer join_schema2.deinit();
    _ = try join_schema2.stmt.execute();
    var join_insert1 = try support.prepare(allocator, fixture.conn, "INSERT INTO t1(id, name) VALUES (1,'a'),(2,'b'),(3,'c')");
    defer join_insert1.deinit();
    _ = try join_insert1.stmt.execute();
    var join_insert2 = try support.prepare(allocator, fixture.conn, "INSERT INTO t2(id, age) VALUES (1,10),(3,30)");
    defer join_insert2.deinit();
    _ = try join_insert2.stmt.execute();

    var join_stmt = try support.prepare(
        allocator,
        fixture.conn,
        "SELECT t1.id, t1.name, t2.age FROM t1 JOIN t2 ON t1.id = t2.id ORDER BY t1.id",
    );
    defer join_stmt.deinit();

    var join_rows = std.array_list.Managed([3]i64).init(allocator);
    defer join_rows.deinit();
    while (true) {
        switch (try join_stmt.stmt.step()) {
            .TURSO_ROW => {
                const name = try join_stmt.stmt.rowValueText(1);
                defer allocator.free(name);
                try join_rows.append(.{
                    join_stmt.stmt.rowValueInt(0),
                    @intCast(name.len),
                    join_stmt.stmt.rowValueInt(2),
                });
            },
            .TURSO_DONE => break,
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expectEqual(@as(usize, 2), join_rows.items.len);
    try std.testing.expectEqualSlices(i64, &.{ 1, 1, 10 }, &join_rows.items[0]);
    try std.testing.expectEqualSlices(i64, &.{ 3, 1, 30 }, &join_rows.items[1]);

    var alter_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE t3(id INT PRIMARY KEY)");
    defer alter_stmt.deinit();
    _ = try alter_stmt.stmt.execute();
    var alter_stmt2 = try support.prepare(allocator, fixture.conn, "ALTER TABLE t3 ADD COLUMN name TEXT");
    defer alter_stmt2.deinit();
    _ = try alter_stmt2.stmt.execute();
    var alter_insert = try support.prepare(allocator, fixture.conn, "INSERT INTO t3(id, name) VALUES(1, 'hello')");
    defer alter_insert.deinit();
    _ = try alter_insert.stmt.execute();
    var alter_query = try support.prepare(allocator, fixture.conn, "SELECT name FROM t3 WHERE id = 1");
    defer alter_query.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try alter_query.stmt.step());
    const altered_name = try alter_query.stmt.rowValueText(0);
    defer allocator.free(altered_name);
    try std.testing.expectEqualStrings("hello", altered_name);

    var series_stmt = try support.prepare(allocator, fixture.conn, "SELECT value FROM generate_series(1,5)");
    defer series_stmt.deinit();
    var series_values = std.array_list.Managed(i64).init(allocator);
    defer series_values.deinit();
    while (true) {
        switch (try series_stmt.stmt.step()) {
            .TURSO_ROW => try series_values.append(series_stmt.stmt.rowValueInt(0)),
            .TURSO_DONE => break,
            else => return error.TestUnexpectedResult,
        }
    }
    try std.testing.expectEqualSlices(i64, &.{ 1, 2, 3, 4, 5 }, series_values.items);

    var json_stmt = try support.prepare(
        allocator,
        fixture.conn,
        "SELECT json_extract('{\"x\": [1,2,3]}', '$.x[1]'), json_array_length('[1,2,3]')",
    );
    defer json_stmt.deinit();
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try json_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 2), json_stmt.stmt.rowValueInt(0));
    try std.testing.expectEqual(@as(i64, 3), json_stmt.stmt.rowValueInt(1));
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try json_stmt.stmt.step());
}
