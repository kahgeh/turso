const std = @import("std");
const turso = @import("turso");
const support = @import("support.zig");

test "column metadata returns owned copies and declared types" {
    const allocator = std.testing.allocator;

    var fixture = try support.openInMemory(allocator);
    defer fixture.deinit();

    var create_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "CREATE TABLE t(id INTEGER, name TEXT)",
    );
    defer create_stmt.deinit();
    _ = try create_stmt.stmt.execute(.{});

    var insert_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "INSERT INTO t(id, name) VALUES (1, 'alice')",
    );
    defer insert_stmt.deinit();
    _ = try insert_stmt.stmt.execute(.{});

    var query_stmt = try support.prepare(
        allocator,
        &fixture.conn,
        "SELECT id, name FROM t",
    );
    defer query_stmt.deinit();

    try std.testing.expectEqual(@as(i64, 2), query_stmt.stmt.columnCount());

    const name0_first = try query_stmt.stmt.columnName(0);
    defer allocator.free(name0_first);
    const name1_first = try query_stmt.stmt.columnName(1);
    defer allocator.free(name1_first);
    const type0_first = try query_stmt.stmt.columnDecltype(0);
    defer allocator.free(type0_first);
    const type1_first = try query_stmt.stmt.columnDecltype(1);
    defer allocator.free(type1_first);

    const name0_second = try query_stmt.stmt.columnName(0);
    defer allocator.free(name0_second);
    const type1_second = try query_stmt.stmt.columnDecltype(1);
    defer allocator.free(type1_second);

    try std.testing.expectEqualStrings("id", name0_first);
    try std.testing.expectEqualStrings("name", name1_first);
    try std.testing.expectEqualStrings("INTEGER", type0_first);
    try std.testing.expectEqualStrings("TEXT", type1_first);
    try std.testing.expectEqualStrings("id", name0_second);
    try std.testing.expectEqualStrings("TEXT", type1_second);

    try std.testing.expectEqual(turso.status.StatusCode.TURSO_ROW, try query_stmt.stmt.step());
    try std.testing.expectEqual(@as(i64, 1), query_stmt.stmt.rowValueInt(0));
    const row_name = try query_stmt.stmt.rowValueText(1);
    defer allocator.free(row_name);
    try std.testing.expectEqualStrings("alice", row_name);
    try std.testing.expectEqual(turso.status.StatusCode.TURSO_DONE, try query_stmt.stmt.step());

    try query_stmt.finalize();

    try std.testing.expectEqualStrings("id", name0_first);
    try std.testing.expectEqualStrings("name", name1_first);
    try std.testing.expectEqualStrings("INTEGER", type0_first);
    try std.testing.expectEqualStrings("TEXT", type1_first);
}
