const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "open create insert query over memory" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT)");
    defer create_stmt.deinit();
    try std.testing.expectEqual(@as(u64, 0), try create_stmt.stmt.execute());

    var insert_stmt = try support.prepare(allocator, fixture.conn, "INSERT INTO users(name) VALUES ('ada')");
    defer insert_stmt.deinit();
    try std.testing.expectEqual(@as(u64, 1), try insert_stmt.stmt.execute());
    try std.testing.expectEqual(@as(i64, 1), fixture.conn.lastInsertRowId());

    var query_stmt = try support.prepare(allocator, fixture.conn, "SELECT id, name FROM users");
    defer query_stmt.deinit();

    try std.testing.expectEqual(@as(i64, 2), query_stmt.stmt.columnCount());
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query_stmt.stmt.step());
    try std.testing.expectEqual(turso.val.ValueKind.integer, query_stmt.stmt.rowValueKind(0));
    try std.testing.expectEqual(turso.val.ValueKind.text, query_stmt.stmt.rowValueKind(1));
    try std.testing.expectEqual(@as(i64, 1), query_stmt.stmt.rowValueInt(0));

    const name = try query_stmt.stmt.rowValueText(1);
    defer allocator.free(name);
    try std.testing.expectEqualStrings("ada", name);

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try query_stmt.stmt.step());

    try fixture.close();
}

test "finalize partially consumed statement and keep connection usable" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(allocator, fixture.conn, "CREATE TABLE items(value INTEGER)");
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute();

    var insert_stmt = try support.prepare(
        allocator,
        fixture.conn,
        "INSERT INTO items(value) VALUES (1), (2) RETURNING value",
    );
    defer insert_stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try insert_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 1), insert_stmt.stmt.rowValueInt(0));

    try insert_stmt.finalize();

    var count_stmt = try support.prepare(allocator, fixture.conn, "SELECT COUNT(*) FROM items");
    defer count_stmt.deinit();

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try count_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 2), count_stmt.stmt.rowValueInt(0));
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try count_stmt.stmt.step());

    try fixture.close();
}
